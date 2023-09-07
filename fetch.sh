#!/bin/sh

LLVM_VERSION=${LLVM_VERSION:-"llvmorg-17.0.0-rc4"}
ZIG_BRANCH=${ZIG_BRANCH:-"llvm17"}
GIT_ARGS=${GIT_ARGS:-"--depth=1"}

if ! [ -x "$(command -v git)" ]; then
	echo "Git is required." >&2
	exit 1
fi

git clone $GIT_ARGS https://github.com/zlib-ng/zlib-ng ./zlib-ng
git clone $GIT_ARGS https://github.com/facebook/zstd zstd
git clone $GIT_ARGS -b "$ZIG_BRANCH" https://github.com/ziglang/zig ./zig
git clone $GIT_ARGS -b "$LLVM_VERSION" https://github.com/llvm/llvm-project ./llvm-project

