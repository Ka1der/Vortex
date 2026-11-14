#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VortexCore.xcframework Build Script
# Compiles Go sing-box bridge into an Apple XCFramework (iOS, iOS Simulator, macOS)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_DIR="${ROOT_DIR}/CoreGo"
OUTPUT_DIR="${ROOT_DIR}/Frameworks"
OUTPUT_XCFRAMEWORK="${OUTPUT_DIR}/VortexCore.xcframework"

echo "=== Building VortexCore.xcframework ==="
echo "Project Root: ${ROOT_DIR}"
echo "CoreGo Dir:   ${CORE_DIR}"
echo "Output Path:  ${OUTPUT_XCFRAMEWORK}"

# 1. Check Go compiler installation
if ! command -v go >/dev/null 2>&1; then
    echo "ERROR: Go is not installed or not in PATH."
    echo "Install Go via Homebrew: brew install go"
    echo "Or download official binary from: https://go.dev/dl/"
    exit 1
fi

GO_VERSION=$(go version)
echo "Found Go: ${GO_VERSION}"

# 2. Check and set Xcode Developer Directory
if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
echo "Using DEVELOPER_DIR: ${DEVELOPER_DIR:-$(xcode-select -p)}"

# 3. Check and install gomobile
export GOPATH="${HOME}/go"
export PATH="${GOPATH}/bin:${PATH}"

if ! command -v gomobile >/dev/null 2>&1; then
    echo "Installing gomobile tool..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
fi

# 4. Prepare output directory
mkdir -p "${OUTPUT_DIR}"
rm -rf "${OUTPUT_XCFRAMEWORK}"

# 5. Build XCFramework with gomobile bind
cd "${CORE_DIR}"

echo "Downloading Go dependencies..."
go mod tidy

echo "Compiling XCFramework for iOS, iOS Simulator, and macOS..."
gomobile bind \
    -target ios,iossimulator,macos \
    -iosversion 17.0 \
    -o "${OUTPUT_XCFRAMEWORK}" \
    -ldflags="-s -w" \
    ./bridge

echo "=== Build Succeeded ==="
echo "XCFramework created at: ${OUTPUT_XCFRAMEWORK}"
ls -la "${OUTPUT_XCFRAMEWORK}"
