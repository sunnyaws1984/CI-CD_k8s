
#!/bin/bash

set -e

echo "======================================"
echo " Kubernetes Kubeconfig Export"
echo "======================================"

# Source kubeconfig
SOURCE="${KUBECONFIG:-$HOME/.kube/config}"

# Detect operating system
OS="$(uname -s)"

case "$OS" in

    Darwin*)
        echo "Detected OS: macOS"
        DESKTOP="$HOME/Desktop"
        ;;

    MINGW*|MSYS*|CYGWIN*)
        echo "Detected OS: Windows (Git Bash)"

        # Git Bash home directory
        WINDOWS_HOME="$HOME"

        # Desktop location
        DESKTOP="$WINDOWS_HOME/Desktop"
        ;;

    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Destination
DESTINATION="$DESKTOP/kubeconfig"

# Check source
if [ ! -f "$SOURCE" ]; then
    echo "ERROR: Kubeconfig not found: $SOURCE"
    exit 1
fi

# Check Desktop
mkdir -p "$DESKTOP"

# Copy kubeconfig
cp "$SOURCE" "$DESTINATION"

# Set permissions
chmod 600 "$DESTINATION" 2>/dev/null || true

echo ""
echo "Kubeconfig exported successfully!"
echo "Source      : $SOURCE"
echo "Destination : $DESTINATION"

echo ""
echo "Current Kubernetes Context:"

kubectl config current-context

echo ""
echo "Export completed!"
