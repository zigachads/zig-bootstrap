#!/bin/sh

LLVM_VERSION=${LLVM_VERSION:-"llvmorg-17.0.6"}
ZIG_BRANCH=${ZIG_BRANCH:-"master"}
GIT_ARGS=${GIT_ARGS:-"--depth=1"}

if ! test -x "$(command -v git)"; then
	echo "Git is required." >&2
	exit 1
fi

git clone $GIT_ARGS https://code.flowtr.dev/mirrors/zlib-ng ./zlib-ng
git clone $GIT_ARGS https://code.flowtr.dev/mirrors/zstd zstd
git clone $GIT_ARGS -b "$ZIG_BRANCH" https://code.flowtr.dev/mirrors/zig ./zig
git clone $GIT_ARGS -b "$LLVM_VERSION" https://code.flowtr.dev/mirrors/llvm-project ./llvm-project

