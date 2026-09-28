#!/bin/bash
# LocalVoiceSync doctor: verifies everything the app needs at runtime and
# repairs what it safely can (currently: starting ydotoold as the current user).
#
# Usage: ./doctor.sh [--no-build-checks]
#   --no-build-checks  skip the Flutter/CMake toolchain checks (pre-built binary)
#
# Exit status: 0 when nothing failed (warnings allowed), 1 otherwise.

set -u

BUILD_CHECKS=true
for arg in "$@"; do
    case "$arg" in
        --no-build-checks) BUILD_CHECKS=false ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/localvoicesync"
PREFS_FILE="$DATA_DIR/shared_preferences.json"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-$RUNTIME_DIR/.ydotool_socket}"
export YDOTOOL_SOCKET

if [ -t 1 ]; then
    C_OK=$'\e[32m' C_WARN=$'\e[33m' C_FAIL=$'\e[31m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_OK='' C_WARN='' C_FAIL='' C_DIM='' C_BOLD='' C_RESET=''
fi

FAILURES=0
WARNINGS=0

section() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
ok()      { printf '  %s[ OK ]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn()    { printf '  %s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$1"; WARNINGS=$((WARNINGS + 1)); }
fail()    { printf '  %s[FAIL]%s %s\n' "$C_FAIL" "$C_RESET" "$1"; FAILURES=$((FAILURES + 1)); }
hint()    { printf '         %s-> %s%s\n' "$C_DIM" "$1" "$C_RESET"; }

has() { command -v "$1" &> /dev/null; }

# Reads a string setting the app persisted via shared_preferences, or prints $2.
pref() {
    python3 - "$PREFS_FILE" "$1" "$2" <<'EOF'
import json, sys
path, key, default = sys.argv[1:4]
try:
    value = json.load(open(path)).get("flutter." + key)
except Exception:
    value = None
print(value if isinstance(value, str) and value else default)
EOF
}

require_bin() {
    local bin="$1" pkg="$2"
    if has "$bin"; then
        ok "$bin found"
    else
        fail "$bin not found"
        hint "sudo dnf install $pkg"
    fi
}

# --------------------------------------------------------------------------
if [ "$BUILD_CHECKS" = true ]; then
    section "Build toolchain"
    require_bin flutter "flutter (https://docs.flutter.dev/get-started/install/linux)"
    require_bin cmake cmake
    require_bin ninja ninja-build
    require_bin clang++ clang
    if has pkg-config && pkg-config --exists gtk+-3.0; then
        ok "gtk3 development files found"
    else
        fail "gtk3 development files not found"
        hint "sudo dnf install pkg-config gtk3-devel"
    fi
fi

# --------------------------------------------------------------------------
section "Settings"
if ! has python3; then
    fail "python3 not found (needed to read app settings)"
    hint "sudo dnf install python3"
elif [ -f "$PREFS_FILE" ]; then
    ok "settings file: $PREFS_FILE"
else
    warn "no settings file yet; checking app defaults"
fi

OLLAMA_ENDPOINT="$(pref ollama_endpoint http://localhost:11434)"
OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT%/}"
OLLAMA_MODEL="$(pref ollama_model llama3.2:1b)"
WHISPER_MODEL="$(pref whisper_model_path '')"
if [ -z "$WHISPER_MODEL" ]; then
    # Same fallback order the app uses when no model has been chosen.
    for candidate in "$DATA_DIR/models/ggml-distil-large-v3.5.bin" "$DATA_DIR/models/ggml-large-v3-turbo.bin"; do
        if [ -f "$candidate" ]; then WHISPER_MODEL="$candidate"; break; fi
    done
fi

# --------------------------------------------------------------------------
section "Models"
if [ -n "$WHISPER_MODEL" ] && [ -s "$WHISPER_MODEL" ]; then
    ok "Whisper model: $WHISPER_MODEL ($(du -h "$WHISPER_MODEL" | cut -f1))"
else
    fail "Whisper model not found${WHISPER_MODEL:+: $WHISPER_MODEL}"
    hint "place a ggml model in $DATA_DIR/models/ or pick one in Settings"
fi

VAD_MODEL="$DATA_DIR/models/silero_vad.onnx"
if [ -s "$VAD_MODEL" ]; then
    ok "VAD model: $VAD_MODEL"
else
    fail "VAD model not found: $VAD_MODEL"
fi

# --------------------------------------------------------------------------
section "Microphone"
if has parecord && has pactl; then
    ok "parecord and pactl found"
    if pactl info &> /dev/null; then
        source_name="$(pactl get-default-source 2>/dev/null)"
        if [ -z "$source_name" ]; then
            fail "no default audio input"
            hint "select a microphone in System Settings > Sound"
        elif [[ "$source_name" == *.monitor ]]; then
            warn "default input is a monitor of an output ($source_name); it records speakers, not your voice"
        else
            ok "default input: $source_name"
        fi
        if [ "$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null)" = "Mute: yes" ]; then
            fail "default input is muted"
            hint "pactl set-source-mute @DEFAULT_SOURCE@ 0"
        fi
    else
        fail "cannot reach the PulseAudio/PipeWire server"
        hint "systemctl --user restart pipewire pipewire-pulse"
    fi
else
    fail "parecord/pactl not found (used by the recorder plugin)"
    hint "sudo dnf install pulseaudio-utils"
fi

# --------------------------------------------------------------------------
section "Ollama (text cleanup)"
if ! has curl; then
    fail "curl not found"
    hint "sudo dnf install curl"
elif tags="$(curl -sf --max-time 3 "$OLLAMA_ENDPOINT/api/tags")"; then
    ok "reachable at $OLLAMA_ENDPOINT"
    if printf '%s' "$tags" | python3 -c '
import json, sys
want = sys.argv[1]
names = {m["name"] for m in json.load(sys.stdin).get("models", [])}
sys.exit(0 if want in names or want + ":latest" in names else 1)
' "$OLLAMA_MODEL"; then
        ok "model available: $OLLAMA_MODEL"
    else
        fail "model not pulled: $OLLAMA_MODEL"
        hint "ollama pull $OLLAMA_MODEL"
    fi
else
    fail "not reachable at $OLLAMA_ENDPOINT"
    hint "sudo systemctl start ollama"
fi

# --------------------------------------------------------------------------
# Starts ydotoold as the current user. Needs rw on /dev/uinput, which the
# active session gets via a udev uaccess ACL; no sudo involved.
start_ydotoold() {
    if [ -S "$YDOTOOL_SOCKET" ] && ! rm -f "$YDOTOOL_SOCKET" 2>/dev/null; then
        return 1
    fi
    setsid -f ydotoold --socket-path="$YDOTOOL_SOCKET" --socket-perm=0600 \
        > "$RUNTIME_DIR/ydotoold.log" 2>&1 < /dev/null
    for _ in $(seq 1 20); do
        ydotool_responds && return 0
        sleep 0.25
    done
    return 1
}

ydotool_responds() { timeout 2 ydotool type "" &> /dev/null; }

section "Text injection (${XDG_SESSION_TYPE:-unknown} session)"
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    require_bin ydotool ydotool
    require_bin ydotoold ydotool
    if [ -r /dev/uinput ] && [ -w /dev/uinput ]; then
        ok "/dev/uinput is writable"
    else
        fail "/dev/uinput is not writable by $(id -un)"
        hint "add a udev rule: KERNEL==\"uinput\", TAG+=\"uaccess\"  (then re-login)"
    fi
    if has ydotool && has ydotoold; then
        if ydotool_responds; then
            ok "ydotoold responding on $YDOTOOL_SOCKET"
        elif start_ydotoold; then
            ok "ydotoold started on $YDOTOOL_SOCKET"
        else
            fail "ydotoold not responding on $YDOTOOL_SOCKET"
            if [ -e "$YDOTOOL_SOCKET" ] && [ ! -O "$YDOTOOL_SOCKET" ]; then
                hint "socket is owned by another user (old 'sudo ydotoold'?): sudo pkill ydotoold && sudo rm $YDOTOOL_SOCKET"
            else
                hint "see $RUNTIME_DIR/ydotoold.log"
            fi
        fi
    fi
    if ! has xinput; then
        warn "xinput not found; ydotoold uses it to tune its virtual pointer"
        hint "sudo dnf install xinput"
    fi
else
    require_bin xdotool xdotool
fi

# --------------------------------------------------------------------------
if has nvidia-smi; then
    section "GPU"
    read -r vram_used vram_total < <(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -n1 | tr -d ',')
    vram_free=$((vram_total - vram_used))
    whisper_mb=0
    if [ -n "$WHISPER_MODEL" ] && [ -s "$WHISPER_MODEL" ]; then
        whisper_mb=$(( $(stat -c %s "$WHISPER_MODEL") / 1048576 ))
    fi
    # Whisper needs its weights plus ~300 MB of compute/KV buffers.
    if [ "$vram_free" -ge $((whisper_mb + 300)) ]; then
        ok "VRAM free: ${vram_free} MB of ${vram_total} MB"
    else
        warn "VRAM free: ${vram_free} MB; Whisper needs ~$((whisper_mb + 300)) MB and may fall back to CPU"
        hint "free GPU memory, e.g. unload Ollama models: ollama stop $OLLAMA_MODEL"
    fi
fi

# --------------------------------------------------------------------------
echo
if [ "$FAILURES" -gt 0 ]; then
    printf '%s%d problem(s) found%s, %d warning(s).\n' "$C_FAIL" "$FAILURES" "$C_RESET" "$WARNINGS"
    exit 1
fi
printf '%sAll checks passed%s (%d warning(s)).\n' "$C_OK" "$C_RESET" "$WARNINGS"
