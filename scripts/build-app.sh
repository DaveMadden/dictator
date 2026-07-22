#!/bin/bash
# Builds Dictator.app from the SwiftPM executable — no Xcode required,
# only the Command Line Tools. Ad-hoc signs the result.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Dictator.app"
SWIFTPM_ROOT="$PWD/.swiftpm"
SWIFT_SCRATCH="$PWD/.build"
MODULE_CACHE="$SWIFT_SCRATCH/ModuleCache.noindex"

# If full Xcode is installed but Command Line Tools are selected, prefer the
# coherent Xcode toolchain to avoid compiler/SDK version skew.
if [ -z "${DEVELOPER_DIR:-}" ] \
    && [ -d /Applications/Xcode.app/Contents/Developer ] \
    && [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    echo "note: using Xcode toolchain from $DEVELOPER_DIR"
fi

# Keep SwiftPM and Clang caches inside the repo so builds do not depend on
# private user cache directories being writable.
mkdir -p "$SWIFTPM_ROOT/cache" "$SWIFTPM_ROOT/config" "$SWIFTPM_ROOT/security" "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
SWIFT_BUILD_ARGS=(
    -c "$CONFIG"
    --cache-path "$SWIFTPM_ROOT/cache"
    --config-path "$SWIFTPM_ROOT/config"
    --security-path "$SWIFTPM_ROOT/security"
    --manifest-cache local
    --scratch-path "$SWIFT_SCRATCH"
)

swift build "${SWIFT_BUILD_ARGS[@]}"
BIN="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/Dictator"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dictator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles resolve relative to the executable's directory.
find "$(dirname "$BIN")" -maxdepth 1 -name '*.bundle' \
    -exec cp -R {} "$APP/Contents/MacOS/" \;

# llama.framework is embedded only when the executable actually links it.
# Testing the binary (not the build directory) keeps a stale artifact from an
# earlier DICTATOR_LLM=1 build out of a clean bundle.
if otool -L "$APP/Contents/MacOS/Dictator" | grep -q 'llama\.framework' \
    && [ -d "$(dirname "$BIN")/llama.framework" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$(dirname "$BIN")/llama.framework" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Dictator"
fi

# A "Dictator Dev" signing cert (create via Keychain Access → Certificate
# Assistant, type: Code Signing) keeps the signature stable across rebuilds so
# macOS permission grants survive. Falls back to ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Dictator Dev"; then
    SIGN_ID="Dictator Dev"
else
    SIGN_ID="-"
    echo "note: no 'Dictator Dev' cert found — ad-hoc signing (permissions reset each rebuild)"
fi
codesign --force --deep --sign "$SIGN_ID" --identifier com.davidmadden.dictator "$APP"

echo "Built $APP (signed: $SIGN_ID)"
