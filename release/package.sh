#!/usr/bin/env bash
# Packs a compiled typed_openapi into typed_openapi-<version>-<target>.tar.gz
# with the licence, and writes the archive's SHA-256 next to it.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: package.sh <target> <version> <executable> <output-directory>" >&2
  exit 64
fi

target=$1
version=$2
executable=$3
output=$4

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
name="typed_openapi-$version-$target"
case "$target" in
  windows-*) binary=typed_openapi.exe ;;
  *) binary=typed_openapi ;;
esac

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

cp "$executable" "$stage/$binary"
chmod +x "$stage/$binary"
cp "$root/packages/typed_openapi/LICENSE" "$stage/LICENSE"

mkdir -p "$output"
tar -czf "$output/$name.tar.gz" -C "$stage" "$binary" LICENSE

cd "$output"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$name.tar.gz" > "$name.tar.gz.sha256"
else
  shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256"
fi
