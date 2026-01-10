#!/bin/bash
# LocalVoiceSync Flutter Launcher

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if ! command -v flutter &> /dev/null; then
    echo "Error: flutter command not found."
    echo "Please install Flutter and make sure it is in your PATH."
    exit 1
fi

# Check for xinput (required by ydotoold to function correctly)
if ! command -v xinput &> /dev/null; then
    echo "Warning: xinput not found. ydotoold may not function correctly."
    echo "Attempting to install xinput..."
    sudo dnf install -y xinput
fi

# Ensure ydotoold is running for Wayland injection
if command -v ydotoold &> /dev/null; then
    # Define a consistent socket path in the user's runtime directory
    USER_SOCKET="/run/user/$(id -u)/.ydotool_socket"
    export YDOTOOL_SOCKET="$USER_SOCKET"

    # Check if the socket actually exists and is usable, not just if a process is "running"
    if [ ! -S "$USER_SOCKET" ]; then
        echo "ydotoold socket not found. Starting daemon..."
        
        # Kill any stale ydotoold processes first
        sudo pkill -9 ydotoold 2>/dev/null || true
        sleep 0.5
        
        # Start ydotoold with user ownership so the app can access the socket
        sudo ydotoold --socket-path="$USER_SOCKET" --socket-own="$(id -u):$(id -g)" --socket-perm=0660 &
        
        # Wait for the socket to appear
        for i in {1..10}; do
            if [ -S "$USER_SOCKET" ]; then
                echo "ydotoold started successfully!"
                break
            fi
            echo "Waiting for ydotoold socket... ($i/10)"
            sleep 0.5
        done
        
        if [ ! -S "$USER_SOCKET" ]; then
            echo "WARNING: ydotoold socket still not available. Injection may not work."
        fi
    else
        echo "ydotoold socket already exists at $USER_SOCKET"
    fi
    
    echo "Using YDOTOOL_SOCKET=$YDOTOOL_SOCKET"
fi

# Run the Flutter application on Linux
exec flutter run -d linux "$@"
