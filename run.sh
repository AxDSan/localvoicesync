#!/bin/bash
# LocalVoiceSync Flutter Launcher

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check for --fast or -f flag to skip building
FAST_MODE=false
for arg in "$@"; do
    if [ "$arg" == "--fast" ] || [ "$arg" == "-f" ]; then
        FAST_MODE=true
        break
    fi
done

# Socket shared by the doctor (which starts ydotoold) and the app (which runs ydotool).
export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.ydotool_socket"

# Kill stale localvoicesync instances first so they don't hold GPU memory
# while the doctor measures it.
pkill -9 localvoicesync 2>/dev/null || true

DOCTOR_ARGS=()
if [ "$FAST_MODE" = true ]; then
    DOCTOR_ARGS+=(--no-build-checks)
fi
if ! ./doctor.sh "${DOCTOR_ARGS[@]}"; then
    echo "Not starting LocalVoiceSync: fix the problems above, then run ./run.sh again."
    exit 1
fi
echo

# Force GDK to use X11 backend even on Wayland sessions.
# This is required for manual window positioning (the interim overlay)
# and transparency to work consistently across different terminals.
# Wayland's security model prevents applications from positioning themselves.
export GDK_BACKEND=x11

if [ "$FAST_MODE" = true ]; then
    BINARY="./build/linux/x64/debug/bundle/localvoicesync"
    if [ -f "$BINARY" ]; then
        echo "Running pre-built binary: $BINARY"
        exec "$BINARY"
    else
        echo "Error: Debug binary not found at $BINARY"
        echo "Please run once without --fast to build the application."
        exit 1
    fi
fi

# Run the Flutter application on Linux
echo "Starting Flutter run..."
exec flutter run -d linux "$@"
