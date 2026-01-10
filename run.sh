#!/bin/bash
# LocalVoiceSync Flutter Launcher

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if ! command -v flutter &> /dev/null; then
    echo "Error: flutter command not found."
    echo "Please install Flutter and make sure it is in your PATH."
    exit 1
fi

# Run the Flutter application on Linux
exec flutter run -d linux "$@"
