#!/usr/bin/env bash
# Install the precompiled musl toolchain used to link static Linux binaries.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -s):$(uname -m) == Linux:x86_64 ]] || {
  echo 'The musl toolchain installer requires an x86_64 Linux build host.' >&2
  exit 1
}
arch=${1:-x86_64}
case "$arch" in
  x86_64) checksum=c5d410d9f82a4f24c549fe5d24f988f85b2679b452413a9f7e5f7b956f2fe7ea ;;
  aarch64) checksum=c909817856d6ceda86aa510894fa3527eac7989f0ef6e87b5721c58737a06c38 ;;
  *) echo "Unsupported musl architecture: $arch" >&2; exit 1 ;;
esac
root="$PWD/.ci/musl"
toolchain="$root/$arch-linux-musl-cross"
mkdir -p "$root"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Download and verify the published toolchain before extracting it.
fetch() {
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 "$1" -o "$work/$2"
  echo "$3  $work/$2" | sha256sum --check -
}
if [[ ! -x "$toolchain/bin/$arch-linux-musl-gcc" ]]; then
  fetch "https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/$arch-linux-musl-cross.tgz" toolchain.tgz "$checksum"
  tar -xzf "$work/toolchain.tgz" -C "$root"
fi
