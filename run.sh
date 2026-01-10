#!/bin/bash
# LocalVoiceSync Flutter Launcher

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if ! command -v flutter &> /dev/null; then
    echo "Error: flutter command not found."
    echo "Please install Flutter and make sure it is in your PATH."
    exit 1
fi

# Ensure ydotoold is running for Wayland injection
if command -v ydotoold &> /dev/null; then
    if ! pgrep -x "ydotoold" &> /dev/null; then
        echo "Starting ydotoold daemon..."
        # Start ydotoold in the background. It may prompt for sudo.
        sudo ydotoold &
        # Give it a moment to initialize the socket
        sleep 1
    fi
    
    # Export the socket path so ydotool can find it (it defaults to root's socket if run with sudo)
    export YDOTOOL_SOCKET="/run/user/0/.ydotool_socket"
    if [ ! -S "$YDOTOOL_SOCKET" ]; then
        # Fallback to standard user socket if root socket doesn't exist
        export YDOTOOL_SOCKET="/run/user/$(id -u)/.ydotool_socket"
    fi
    echo "Using YDOTOOL_SOCKET=$YDOTOOL_SOCKET"
fi

# Run the Flutter application on Linux
exec flutter run -d linux "$@"
