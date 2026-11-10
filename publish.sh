#!/bin/bash
# Publish the built viewer (app/) as the only commit of branch `pages` on origin (force push).
#   ./publish.sh [remote]        remote defaults to origin
# The branch holds just the static site (index.html at its root), suitable for GitHub Pages
# with "Deploy from a branch: pages / (root)". The working tree and master are not touched.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
REMOTE=${1:-origin}
URL=$(git -C "$ROOT" remote get-url "$REMOTE")
[ -f "$ROOT/app/index.html" ] || { echo "app/index.html missing; build first" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -r "$ROOT/app/." "$TMP/"
touch "$TMP/.nojekyll"  # serve files as-is (no Jekyll processing)

SRC=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
git -C "$TMP" init -q -b pages
git -C "$TMP" config user.name "$(git -C "$ROOT" config user.name || echo publish)"
git -C "$TMP" config user.email "$(git -C "$ROOT" config user.email || echo publish@localhost)"
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "Publish viewer (source $SRC)"
git -C "$TMP" push -f "$URL" pages:pages
echo "published $(du -sh "$ROOT/app" | cut -f1) to $REMOTE/pages"
