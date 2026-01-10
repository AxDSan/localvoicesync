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

    # Function to test if ydotool actually works
    test_ydotool() {
        # Try a no-op command to see if the daemon responds
        timeout 2 ydotool type "" 2>/dev/null
        return $?
    }

    # Always try to ensure the daemon is running and responsive
    if ! test_ydotool; then
        echo "ydotoold is not responding. Starting fresh daemon..."
        
        # Remove stale socket file if it exists
        sudo rm -f "$USER_SOCKET" 2>/dev/null || true
        
        # Kill any stale ydotoold processes
        sudo pkill -9 ydotoold 2>/dev/null || true
        sleep 0.5
        
        # Start ydotoold with user ownership so the app can access the socket
        echo "Starting ydotoold daemon..."
        sudo ydotoold --socket-path="$USER_SOCKET" --socket-own="$(id -u):$(id -g)" --socket-perm=0660 &
        
        # Wait for the daemon to be responsive
        for i in {1..10}; do
            if test_ydotool; then
                echo "ydotoold started successfully!"
                break
            fi
            echo "Waiting for ydotoold to respond... ($i/10)"
            sleep 0.5
        done
        
        if ! test_ydotool; then
            echo "WARNING: ydotoold is still not responding. Injection may not work."
            echo "Try running 'sudo ydotoold' manually in a separate terminal."
        fi
    else
        echo "ydotoold is already running and responsive"
    fi
    
    echo "Using YDOTOOL_SOCKET=$YDOTOOL_SOCKET"
fi

# Run the Flutter application on Linux
exec flutter run -d linux "$@"
