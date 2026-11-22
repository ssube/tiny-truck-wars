#!/bin/bash
# Exports the Linux, Windows and Web builds and packs each into a zip:
# dist/tiny-truck-wars-<version>-<platform>.zip (and dist/<platform>/
# unpacked, for butler). The desktop ones carry the README, credits,
# changelog and licences; the web one has index.html at its root (as itch.io
# wants), with the licences beside it. The version is project.godot's.
#   ci/package.sh            export, then pack
#   ci/package.sh --no-export   pack what is in builds/ already
# Needs Godot 4.7.2 with its export templates ($GODOT, else godot on the PATH).
set -euo pipefail
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
ENGINE=${GODOT:-godot}
VERSION=$(sed -nE 's/^config\/version="(.*)"$/\1/p' project.godot)
if [ "${1:-}" != "--no-export" ]; then
  rm -rf builds/web
  mkdir -p builds/linux builds/windows builds/web
  "$ENGINE" --headless --path . --export-release Linux builds/linux/tiny-truck-wars.x86_64
  "$ENGINE" --headless --path . --export-release Windows builds/windows/tiny-truck-wars.exe
  "$ENGINE" --headless --path . --export-release Web builds/web/index.html
fi
test -s builds/linux/tiny-truck-wars.x86_64
test -s builds/windows/tiny-truck-wars.exe
test -s builds/web/index.html
rm -rf dist
for platform in linux windows; do
  dir="dist/$platform/tiny-truck-wars-$VERSION-$platform"
  mkdir -p "$dir/licenses"
  cp builds/$platform/* "$dir/"
  cp README.md CREDITS.md CHANGELOG.md LICENSE "$dir/"
  cp licenses/*.txt licenses/*.md "$dir/licenses/"
  (cd "dist/$platform" && zip -qr "../tiny-truck-wars-$VERSION-$platform.zip" "tiny-truck-wars-$VERSION-$platform")
done
# The web build: index.html at the zip's root.
dir="dist/web/tiny-truck-wars-$VERSION-web"
mkdir -p "$dir/licenses"
cp builds/web/* "$dir/"
cp CREDITS.md LICENSE "$dir/"
cp licenses/*.txt licenses/*.md "$dir/licenses/"
(cd "$dir" && zip -qr "../../tiny-truck-wars-$VERSION-web.zip" .)
awk -v v="## $VERSION" '$0 == v {on = 1; next} /^## / && on {exit} on' CHANGELOG.md > dist/notes.md
echo "$VERSION"
