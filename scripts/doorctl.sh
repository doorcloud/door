#!/bin/sh

# doorctl installer
# POSIX sh compatible. Run with:
#   curl -sSL https://raw.githubusercontent.com/doorcloud/door/main/scripts/doorctl.sh | sh -s
#   curl -sSL https://raw.githubusercontent.com/doorcloud/door/main/scripts/doorctl.sh | sh -s -- v2.5.0

OWNER="doorcloud"
REPO="door"
BINARY="doorctl"

if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(curl -fsSL -I "https://github.com/$OWNER/$REPO/releases/latest" | grep -i "^location:" | awk -F"/" '{print $NF}' | tr -d '\r')
    if [ -z "$VERSION" ]; then
        echo "Error: failed to resolve the latest $BINARY release." >&2
        exit 1
    fi
fi

UNAME=$(uname)
ARCH=$(uname -m)
case "$UNAME" in
    Darwin)
        case "$ARCH" in
            arm64) SUFFIX="_Darwin_arm64" ;;
            *)     SUFFIX="_Darwin_x86_64" ;;
        esac
        ;;
    Linux)
        case "$ARCH" in
            aarch64|arm64) SUFFIX="_Linux_arm64" ;;
            i386|i686)       SUFFIX="_Linux_i386" ;;
            *)               SUFFIX="_Linux_x86_64" ;;
        esac
        ;;
    *)
        echo "Error: unsupported operating system '$UNAME'." >&2
        exit 1
        ;;
esac

TARBALL_NAME="doorctl${SUFFIX}.tar.gz"
TARBALL_URL="https://github.com/$OWNER/$REPO/releases/download/$VERSION/$TARBALL_NAME"
CHECKSUMS_URL="https://github.com/$OWNER/$REPO/releases/download/$VERSION/checksums.txt"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR" || exit 1

echo "Downloading $BINARY $VERSION for $UNAME $ARCH..."
curl -fsSL "$TARBALL_URL" -o "$TARBALL_NAME"
if [ $? -ne 0 ]; then
    echo "Error: failed to download $TARBALL_URL" >&2
    exit 1
fi

curl -fsSL "$CHECKSUMS_URL" -o checksums.txt
if [ $? -ne 0 ]; then
    echo "Error: failed to download $CHECKSUMS_URL" >&2
    exit 1
fi

if command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum"
else
    echo "Warning: neither shasum nor sha256sum found; skipping checksum verification." >&2
    SHA_CMD=""
fi

if [ -n "$SHA_CMD" ]; then
    EXPECTED_HASH=$(awk -v f="$TARBALL_NAME" '
        {
            gsub(/^\*/, "", $2)
            if ($2 == f) { print $1; exit }
        }
    ' checksums.txt)
    if [ -z "$EXPECTED_HASH" ]; then
        echo "Error: checksum for $TARBALL_NAME not found in checksums.txt" >&2
        exit 1
    fi
    ACTUAL_HASH=$($SHA_CMD "$TARBALL_NAME" | awk '{print $1}')
    if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
        echo "Error: checksum verification failed for $TARBALL_NAME." >&2
        echo "  expected: $EXPECTED_HASH" >&2
        echo "  actual:   $ACTUAL_HASH" >&2
        exit 1
    fi
    echo "Checksum verified."
fi

tar -xzf "$TARBALL_NAME"
if [ $? -ne 0 ]; then
    echo "Error: failed to extract $TARBALL_NAME" >&2
    exit 1
fi

chmod +x "$TMP_DIR/doorctl"

# Determine install destination
USE_SUDO=""
if [ -n "${DOORCTL_INSTALL_DIR:-}" ]; then
    TARGET_DIR="$DOORCTL_INSTALL_DIR"
elif [ -d "/opt/homebrew/bin" ] && [ -w "/opt/homebrew/bin" ]; then
    TARGET_DIR="/opt/homebrew/bin"
elif [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    TARGET_DIR="/usr/local/bin"
elif [ -t 1 ] && [ -r /dev/tty ]; then
    printf "Install %s to /usr/local/bin? This requires sudo. [Y/n] " "$BINARY" > /dev/tty
    read -r answer < /dev/tty
    case "$answer" in
        [Yy]*|"")
            TARGET_DIR="/usr/local/bin"
            USE_SUDO=1
            ;;
        *)
            echo "Installation cancelled." >&2
            exit 1
            ;;
    esac
else
    TARGET_DIR="$HOME/.local/bin"
    mkdir -p "$TARGET_DIR"
    FALLBACK_DIR=1
fi

if [ -n "${DOORCTL_DRY_RUN:-}" ]; then
    echo "Dry run: selected install destination is $TARGET_DIR"
    exit 0
fi

if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR" || {
        echo "Error: failed to create directory $TARGET_DIR" >&2
        exit 1
    }
fi

if [ "$USE_SUDO" = "1" ]; then
    sudo install -m 0755 "$TMP_DIR/doorctl" "$TARGET_DIR/doorctl"
elif command -v install >/dev/null 2>&1; then
    install -m 0755 "$TMP_DIR/doorctl" "$TARGET_DIR/doorctl"
else
    cp "$TMP_DIR/doorctl" "$TARGET_DIR/doorctl" && chmod 0755 "$TARGET_DIR/doorctl"
fi
if [ $? -ne 0 ]; then
    echo "Error: failed to install $BINARY to $TARGET_DIR" >&2
    exit 1
fi

echo ""
echo "$BINARY $VERSION installed successfully"
echo "  architecture: $UNAME $ARCH"
echo "  destination:  $TARGET_DIR/doorctl"

VERSION_OUT=$("$TARGET_DIR/doorctl" version 2>/dev/null | head -n 1 || true)
if [ -n "$VERSION_OUT" ]; then
    echo "  version:      $VERSION_OUT"
fi

echo ""
echo "Next steps:"
echo "  doorctl config --server-url <YOUR_DOOR_URL> --organization <YOUR_ORG>"

if [ "${FALLBACK_DIR:-}" = "1" ]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *)
            echo ""
            echo "Add ~/.local/bin to your PATH:"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo "Add that line to your shell profile (e.g. ~/.zshrc, ~/.bashrc) to make it permanent."
            ;;
    esac
fi
