#!/bin/sh
# Generate rust's bootstrap.toml for the rustc build.
#
# The build always runs on the amd64 worker (the rustc package pins
# buildPlatform: linux/amd64), so BUILD is always x86_64-*. The requested target
# platform drives ARCH: x86_64 -> native amd64-host rustc, aarch64 -> cross-built
# aarch64-host rustc.
set -eu

BUILD_ARCH="${BUILD%%-*}"                       # x86_64 (build platform)
RUST_BUILD="${BUILD_ARCH}-unknown-linux-musl"
RUST_TARGET="$(echo "${ARCH}" | sed s/^riscv64$/riscv64gc/)-unknown-linux-musl"

cat <<EOF
[build]
build = "${RUST_BUILD}"
host = ["${RUST_TARGET}"]
target = ["${RUST_TARGET}"]
rustc = "/bootstrap/usr/bin/rustc"
cargo = "/bootstrap/usr/bin/cargo"
# The stage0 (stagex) rustc is not the exact version src/stage0 expects, so tell
# bootstrap to treat it as a local rebuild (use its std/sysroot directly rather
# than a freshly-built stage1 std).
local-rebuild = true
docs = false
vendor = true
extended = true
tools = ["cargo"]

[install]
prefix = "/usr"
sysconfdir = "/etc"

[rust]
channel = "stable"
lld = false
llvm-tools = false

[llvm]
link-shared = true
EOF

# The build platform (x86_64) toolchain is always needed: it is the `build`
# triple (and the host/target for a native amd64 build). Point it at the amd64
# tools LLVM so x.py never falls back to building LLVM from source (which would
# need ninja). Without this block a cross build fails with "Couldn't find ninja".
cat <<EOF

[target.x86_64-unknown-linux-musl]
llvm-config = "/usr/bin/llvm-config"
cc = "clang"
cxx = "clang++"
ar = "llvm-ar"
ranlib = "llvm-ranlib"
linker = "clang"
musl-root = "/usr"
crt-static = false
EOF

if [ "${ARCH}" = "riscv64" ]; then
	# Cross target: aarch64 host, linked against the prebuilt arm64 libLLVM (its
	# llvm-config runs under buildx qemu), compiled/linked with the multi-target
	# clang via wrappers that add --target/--sysroot.
	cat <<EOF

[target.riscv64gc-unknown-linux-musl]
llvm-config = "/usr/bin/riscv64-llvm-config"
cc = "/usr/bin/riscv64-clang"
cxx = "/usr/bin/riscv64-clang++"
ar = "llvm-ar"
ranlib = "llvm-ranlib"
linker = "/usr/bin/riscv64-clang"
musl-root = "/sysroots/riscv64/usr"
crt-static = false
EOF
fi
