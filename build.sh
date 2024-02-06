#!/bin/sh

set -eu

LINK_JOBS=${LINK_JOBS:-"2"}
export CMAKE_BUILD_PARALLEL_LEVEL=${CMAKE_BUILD_PARALLEL_LEVEL:-"16"}
TARGET=${TARGET:-"x86_64-linux-musl"}
MCPU=${MCPU:-"baseline"}
LLVM_PROJECTS=${LLVM_PROJECTS:-"lld;clang"}
LLVM_STATIC=${LLVM_STATIC:-"OFF"}

ROOTDIR="$PWD"
ZIG_VERSION="0.12.0-dev.2551+5b803aecf"

TARGET_OS_AND_ABI=${TARGET#*-} # Example: linux-gnu

# Here we map the OS from the target triple to the value that CMake expects.
TARGET_OS_CMAKE=${TARGET_OS_AND_ABI%-*} # Example: linux
case $TARGET_OS_CMAKE in
	macos) TARGET_OS_CMAKE="Darwin";;
	freebsd) TARGET_OS_CMAKE="FreeBSD";;
	netbsd) TARGET_OS_CMAKE="NetBSD";;
	openbsd) TARGET_OS_CMAKE="FreeBSD";;
	windows) TARGET_OS_CMAKE="Windows";;
	linux) TARGET_OS_CMAKE="Linux";;
	native) TARGET_OS_CMAKE="";;
esac

# First build the libraries for Zig to link against, as well as native `llvm-tblgen`.
mkdir -p "$ROOTDIR/out/build-llvm-host"
cd "$ROOTDIR/out/build-llvm-host"
cmake "$ROOTDIR/llvm-project/llvm" \
	-DLLVM_PARALLEL_LINK_JOBS=${LINK_JOBS} \
	-DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
	-DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DLLVM_ENABLE_PROJECTS="lld;clang" \
	-DLLVM_ENABLE_LIBXML2=OFF \
	-DLLVM_ENABLE_ZSTD=OFF \
	-DLLVM_INCLUDE_UTILS=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DLLVM_TOOL_LLVM_LTO2_BUILD=ON \
	-DLLVM_TOOL_LLVM_LTO_BUILD=ON \
	-DLLVM_TOOL_LTO_BUILD=ON \
	-DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
	-DCLANG_BUILD_TOOLS=OFF \
	-DCLANG_INCLUDE_DOCS=OFF \
	-DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
	-DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
	-DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
	-DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
	-DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
	-DCLANG_TOOL_LIBCLANG_BUILD=OFF
cmake --build . --target install

# Now we build Zig, still with system C/C++ compiler, linking against LLVM,
# Clang, LLD we just built from source.
mkdir -p "$ROOTDIR/out/build-zig-host"
cd "$ROOTDIR/out/build-zig-host"
cmake "$ROOTDIR/zig" \
	-DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
	-DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install

# Now we have Zig as a cross compiler.
ZIG="$ROOTDIR/out/host/bin/zig"

# First cross compile zlib for the target, as we need the LLVM linked into
# the final zig binary to have zlib support enabled.
mkdir -p "$ROOTDIR/out/build-zlib-$TARGET-$MCPU"
cd "$ROOTDIR/out/build-zlib-$TARGET-$MCPU"
cmake "$ROOTDIR/zlib-ng" \
	-DZLIB_COMPAT=ON \
	-DZLIB_ENABLE_TESTS=OFF \
	-DZLIBNG_ENABLE_TESTS=OFF \
	-DBUILD_SHARED_LIBS=OFF \
	-DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/$TARGET-$MCPU" \
	-DCMAKE_PREFIX_PATH="$ROOTDIR/out/$TARGET-$MCPU" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_CROSSCOMPILING=True \
	-DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
	-DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_RC_COMPILER="$ROOTDIR/out/host/bin/llvm-rc" \
	-DCMAKE_AR="$ROOTDIR/out/host/bin/llvm-ar" \
	-DCMAKE_RANLIB="$ROOTDIR/out/host/bin/llvm-ranlib"
cmake --build . --target install

# Same deal for zstd.
# The build system for zstd is whack so I just put all the files here.
mkdir -p "$ROOTDIR/out/$TARGET-$MCPU/lib"
cp "$ROOTDIR/zstd/lib/zstd.h" "$ROOTDIR/out/$TARGET-$MCPU/include/zstd.h"
cd "$ROOTDIR/out/$TARGET-$MCPU/lib"
$ZIG build-lib \
	--name zstd \
	-target $TARGET \
	-mcpu=$MCPU \
	-fstrip -OReleaseSmall \
	-lc \
	"$ROOTDIR/zstd/lib/decompress/zstd_ddict.c" \
	"$ROOTDIR/zstd/lib/decompress/zstd_decompress.c" \
	"$ROOTDIR/zstd/lib/decompress/huf_decompress.c" \
	"$ROOTDIR/zstd/lib/decompress/huf_decompress_amd64.S" \
	"$ROOTDIR/zstd/lib/decompress/zstd_decompress_block.c" \
	"$ROOTDIR/zstd/lib/compress/zstdmt_compress.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_opt.c" \
	"$ROOTDIR/zstd/lib/compress/hist.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_ldm.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_fast.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_compress_literals.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_double_fast.c" \
	"$ROOTDIR/zstd/lib/compress/huf_compress.c" \
	"$ROOTDIR/zstd/lib/compress/fse_compress.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_lazy.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_compress.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_compress_sequences.c" \
	"$ROOTDIR/zstd/lib/compress/zstd_compress_superblock.c" \
	"$ROOTDIR/zstd/lib/deprecated/zbuff_compress.c" \
	"$ROOTDIR/zstd/lib/deprecated/zbuff_decompress.c" \
	"$ROOTDIR/zstd/lib/deprecated/zbuff_common.c" \
	"$ROOTDIR/zstd/lib/common/entropy_common.c" \
	"$ROOTDIR/zstd/lib/common/pool.c" \
	"$ROOTDIR/zstd/lib/common/threading.c" \
	"$ROOTDIR/zstd/lib/common/zstd_common.c" \
	"$ROOTDIR/zstd/lib/common/xxhash.c" \
	"$ROOTDIR/zstd/lib/common/debug.c" \
	"$ROOTDIR/zstd/lib/common/fse_decompress.c" \
	"$ROOTDIR/zstd/lib/common/error_private.c" \
	"$ROOTDIR/zstd/lib/dictBuilder/zdict.c" \
	"$ROOTDIR/zstd/lib/dictBuilder/divsufsort.c" \
	"$ROOTDIR/zstd/lib/dictBuilder/fastcover.c" \
	"$ROOTDIR/zstd/lib/dictBuilder/cover.c"

# Rebuild LLVM with Zig.
mkdir -p "$ROOTDIR/out/build-llvm-$TARGET-$MCPU"
cd "$ROOTDIR/out/build-llvm-$TARGET-$MCPU"
cmake "$ROOTDIR/llvm-project/llvm" \
	-DLLVM_PARALLEL_LINK_JOBS=${LINK_JOBS} \
	-DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/$TARGET-$MCPU" \
	-DCMAKE_PREFIX_PATH="$ROOTDIR/out/$TARGET-$MCPU" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_CROSSCOMPILING=True \
	-DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
	-DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
	-DCMAKE_RC_COMPILER="$ROOTDIR/out/host/bin/llvm-rc" \
	-DCMAKE_AR="$ROOTDIR/out/host/bin/llvm-ar" \
	-DCMAKE_RANLIB="$ROOTDIR/out/host/bin/llvm-ranlib" \
	-DZLIB_USE_STATIC_LIBS=ON \
	-DLLVM_ENABLE_BACKTRACES=OFF \
	-DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
	-DLLVM_ENABLE_LIBEDIT=OFF \
	-DLLVM_ENABLE_LIBPFM=OFF \
	-DLLVM_ENABLE_LIBXML2=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
	-DLLVM_ENABLE_PLUGINS=OFF \
	-DLLVM_ENABLE_PROJECTS="$LLVM_PROJECTS" \
	-DLLVM_ENABLE_TERMINFO=OFF \
	-DLLVM_ENABLE_Z3_SOLVER=OFF \
	-DLLVM_ENABLE_ZLIB=FORCE_ON \
	-DLLVM_ENABLE_ZSTD=FORCE_ON \
	-DLLVM_USE_STATIC_ZSTD=ON \
	-DLLVM_TABLEGEN="$ROOTDIR/out/host/bin/llvm-tblgen" \
	-DLLVM_BUILD_TOOLS=ON \
	-DLLVM_BUILD_STATIC=${LLVM_STATIC} \
	-DLLVM_INCLUDE_UTILS=ON \
	-DLLVM_INSTALL_UTILS=ON \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
	-DLLVM_TOOL_LLVM_LTO2_BUILD=ON \
	-DLLVM_TOOL_LLVM_LTO_BUILD=ON \
	-DLLVM_TOOL_LTO_BUILD=ON \
	-DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
	-DLLVM_ENABLE_PIC=OFF \
	-DCLANG_TABLEGEN="$ROOTDIR/out/build-llvm-host/bin/clang-tblgen" \
	-DCLANG_BUILD_TOOLS=ON \
	-DCLANG_INCLUDE_DOCS=OFF \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCLANG_ENABLE_ARCMT=ON \
	-DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
	-DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
	-DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
	-DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
	-DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
	-DCLANG_TOOL_LIBCLANG_BUILD=ON \
	-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
	-DLIBCLANG_BUILD_STATIC=ON
cmake --build . --target install

# Finally, we can cross compile Zig itself, with Zig.
cd "$ROOTDIR/zig"
$ZIG build \
	--prefix "$ROOTDIR/out/zig-$TARGET-$MCPU" \
	--search-prefix "$ROOTDIR/out/$TARGET-$MCPU" \
	-Dstatic-llvm \
	-Doptimize=ReleaseSmall \
	-Dstrip \
	-Dtarget="$TARGET" \
	-Dcpu="$MCPU" \
	-Dversion-string="$ZIG_VERSION"
