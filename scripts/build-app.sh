#!/bin/bash
# Builds Dictator.app from the SwiftPM executable — no Xcode required,
# only the Command Line Tools. Ad-hoc signs the result.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Dictator.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Dictator"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dictator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles resolve relative to the executable's directory.
find "$(dirname "$BIN")" -maxdepth 1 -name '*.bundle' \
    -exec cp -R {} "$APP/Contents/MacOS/" \;

# llama.framework is a dynamic binary target; embed it and point the
# executable's rpath at the bundle's Frameworks directory.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$(dirname "$BIN")/llama.framework" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Dictator"

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
