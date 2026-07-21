#!/bin/bash
# Package or install the Parakeet models so a second machine (e.g. a locked-down
# work Mac) never has to download them from Hugging Face.
#
#   models.sh export             → build/dictator-models-v3.tar.gz
#   models.sh install <tar.gz>   → ~/Library/Application Support/Dictator/models/
set -euo pipefail
cd "$(dirname "$0")/.."

FOLDER="parakeet-tdt-0.6b-v3-coreml"
CACHE="$HOME/Library/Application Support/FluidAudio/Models/$FOLDER"
LOCAL="$HOME/Library/Application Support/Dictator/models/$FOLDER"

case "${1:-}" in
export)
    SRC=""
    [ -d "$LOCAL" ] && SRC="$LOCAL"
    [ -z "$SRC" ] && [ -d "$CACHE" ] && SRC="$CACHE"
    if [ -z "$SRC" ]; then
        echo "no models found — run the app or DictatorCLI once first" >&2
        exit 1
    fi
    mkdir -p build
    tar -czf build/dictator-models-v3.tar.gz -C "$(dirname "$SRC")" "$FOLDER"
    echo "wrote build/dictator-models-v3.tar.gz ($(du -h build/dictator-models-v3.tar.gz | cut -f1))"
    echo "ship it via GitHub Release, AirDrop, or USB, then: make install-models FILE=<path>"
    ;;
install-from-repo)
    # Pulls the chunked tarball from this repo's `models` branch on GitHub,
    # so no host other than GitHub is ever contacted.
    git fetch origin models
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    git archive origin/models chunks | tar -x -C "$TMP"
    cat "$TMP"/chunks/dictator-models-v3.tar.gz.part-* > "$TMP/dictator-models-v3.tar.gz"
    EXPECTED="$(cat "$TMP"/chunks/dictator-models-v3.tar.gz.sha256)"
    ACTUAL="$(shasum -a 256 "$TMP/dictator-models-v3.tar.gz" | awk '{print $1}')"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "checksum mismatch — refusing to install (expected $EXPECTED, got $ACTUAL)" >&2
        exit 1
    fi
    "$0" install "$TMP/dictator-models-v3.tar.gz"
    ;;
install)
    FILE="${2:-}"
    if [ ! -f "$FILE" ]; then
        echo "usage: models.sh install <dictator-models-v3.tar.gz>" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$LOCAL")"
    tar -xzf "$FILE" -C "$(dirname "$LOCAL")"
    echo "installed to $LOCAL"
    echo "Dictator will load these on launch — no network access needed, ever"
    ;;
*)
    echo "usage: models.sh {export|install <file>|install-from-repo}" >&2
    exit 1
    ;;
esac
