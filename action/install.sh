#!/usr/bin/env bash
# Downloads a typed_openapi release binary, checks it against SHA256SUMS and
# prints the path of the executable as the only line on stdout.
set -euo pipefail

fail() {
  echo "install.sh: $1" >&2
  exit 1
}

if [ "$#" -ne 4 ]; then
  echo "usage: install.sh <version> <RUNNER_OS> <RUNNER_ARCH> <directory>" >&2
  exit 64
fi

version=$1
runner_os=$2
runner_arch=$3
directory=$4
releases=${TYPED_OPENAPI_RELEASES:-https://github.com/4akloon/typed_openapi/releases/download}

if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  fail "'$version' is not a version such as 0.1.0"
fi

case "$runner_os" in
  Linux) os=linux ;;
  macOS) os=macos ;;
  Windows) os=windows ;;
  *) fail "there is no binary for $runner_os $runner_arch" ;;
esac
case "$runner_arch" in
  X64) arch=x64 ;;
  ARM64) arch=arm64 ;;
  *) fail "there is no binary for $runner_os $runner_arch" ;;
esac
case "$os-$arch" in
  linux-x64 | linux-arm64 | macos-x64 | macos-arm64 | windows-x64) ;;
  *) fail "there is no binary for $os-$arch" ;;
esac

asset="typed_openapi-$version-$os-$arch.tar.gz"
base="$releases/typed_openapi-v$version"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

download() {
  curl --fail --silent --show-error --location --output "$2" "$1" \
    || fail "could not download $1"
}
download "$base/$asset" "$work/$asset"
download "$base/SHA256SUMS" "$work/SHA256SUMS"

expected=$(awk -v name="$asset" '{ file = $2; sub(/^\*/, "", file) } file == name { print $1; exit }' "$work/SHA256SUMS")
[ -n "$expected" ] || fail "$asset is not in SHA256SUMS"

if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$work/$asset" | awk '{ print $1 }')
else
  actual=$(shasum -a 256 "$work/$asset" | awk '{ print $1 }')
fi
[ "$actual" = "$expected" ] || fail "$asset does not match SHA256SUMS"

mkdir -p "$directory"
tar -xzf "$work/$asset" -C "$directory"

if [ "$os" = windows ]; then
  echo "$directory/typed_openapi.exe"
else
  echo "$directory/typed_openapi"
fi
