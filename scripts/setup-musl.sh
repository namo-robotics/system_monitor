#!/usr/bin/env bash
# Install musl compilers and build the web server's static native libraries.
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
prefix="$toolchain/$arch-linux-musl"
mkdir -p "$root"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Download and verify each source before extracting it.
fetch() {
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 "$1" -o "$work/$2"
  echo "$3  $work/$2" | sha256sum --check -
}
if [[ ! -x "$toolchain/bin/$arch-linux-musl-gcc" ]]; then
  fetch "https://github.com/musl-cc/musl.cc/releases/download/v0.0.1/$arch-linux-musl-cross.tgz" toolchain.tgz "$checksum"
  tar -xzf "$work/toolchain.tgz" -C "$root"
fi
export PATH="$toolchain/bin:$PATH"
# Only the x86_64 build includes the web server.
[[ "$arch" == x86_64 ]] || exit 0
if [[ -f "$prefix/lib/libz.a" && -f "$prefix/lib/libssl.a" && -f "$prefix/lib/libcrypto.a" ]]; then
  exit 0
fi
command -v make >/dev/null
command -v perl >/dev/null
fetch https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz zlib.tar.gz \
  bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
mkdir "$work/zlib"
tar -xzf "$work/zlib.tar.gz" -C "$work/zlib" --strip-components=1
(
  cd "$work/zlib"
  CC=x86_64-linux-musl-gcc AR=x86_64-linux-musl-ar RANLIB=x86_64-linux-musl-ranlib \
    ./configure --static --prefix="$prefix"
  make -j"${BUILD_JOBS:-2}"
  make install
)
fetch https://github.com/openssl/openssl/releases/download/openssl-3.3.7/openssl-3.3.7.tar.gz openssl.tar.gz \
  4900be54e81c4dfe00bb1a10dad33fd8414833573c40d0e9e3274d4ed32e53a2
mkdir "$work/openssl"
tar -xzf "$work/openssl.tar.gz" -C "$work/openssl" --strip-components=1
(
  cd "$work/openssl"
  ./Configure linux-x86_64 no-shared no-dso no-tests no-apps no-docs \
    --cross-compile-prefix=x86_64-linux-musl- --prefix="$prefix" --libdir=lib
  make -j"${BUILD_JOBS:-2}" build_libs
  make install_dev
)
