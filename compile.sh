#!/bin/bash
SECONDS=0
set -e

# ================= PATHS =================
KERNEL_PATH="out/arch/arm64/boot"
OBJ="${KERNEL_PATH}/Image"
GZIP="${KERNEL_PATH}/Image.gz"
CAT="${KERNEL_PATH}/Image.gz-dtb"
DTB="${KERNEL_PATH}/dtb.img"
DTBO="${KERNEL_PATH}/dtbo.img"

# ================= META =================
DATE="$(date +%Y%m%d%H%M)"
KERNEL_NAME_T="derivativeTS-${DATE}.zip"
KERNEL_NAME_R="derivativeRS-${DATE}.zip"

CONFIG_PATH="arch/arm64/configs"
DEFCONFIG="guamp_defconfig"
ORIGINAL="${CONFIG_PATH}/${DEFCONFIG}"
BACKUP="${CONFIG_PATH}/${DEFCONFIG}.bak"

# ================= ENV =================
export USE_CCACHE=1
export KBUILD_BUILD_HOST=builder
export KBUILD_BUILD_USER=khayloaf

# ================= FUNCTIONS =================
KERNELSU_SETUP() {
    if [ ! -d KernelSU ]; then
        echo "➡️ Aplicando KernelSU Next"
        curl -LSs https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh | bash -s legacy
    fi
}

CLANG_SETUP() {
    if [ ! -d clang ]; then
        mkdir -p clang
        wget -q https://github.com/Impqxr/aosp_clang_ci/releases/download/13289611/clang-13289611-linux-x86.tar.xz -O clang.tar.xz
        tar -xf clang.tar.xz -C clang
        mv clang/clang-*/* clang
        rm -rf clang.tar.xz clang/clang-*
    fi
    export PATH="$PWD/clang/bin:$PATH"
}

BUILD_KERNEL() {
    rm -rf out && mkdir out

    git restore drivers/Makefile drivers/Kconfig || true
    rm -rf KernelSU drivers/kernelsu

    KERNELSU_SETUP
    CLANG_SETUP

    make O=out ARCH=arm64 "$DEFCONFIG"

    make -j"$(nproc)" \
        O=out ARCH=arm64 \
        CC=clang LD=ld.lld \
        AR=llvm-ar NM=llvm-nm \
        OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
        LLVM=1 LLVM_IAS=1
}

PACKAGE_KERNEL() {
    ZIP_NAME="$1"

    for f in "$OBJ" "$CAT" "$DTB" "$DTBO"; do
        [ -f "$f" ] || { echo "❌ Build incompleto"; exit 1; }
    done

    rm -rf anykernel
    git clone --depth=1 https://github.com/kylieeXD/AK3-Surya.git -b master anykernel

    cp "$OBJ" "$CAT" anykernel/kernels/

    cd anykernel
    zip -r9 "../$ZIP_NAME" .
    cd ..
}

UPLOAD() {
    FILE="$1"
    echo "➡️ Uploading $FILE"

    curl --fail --progress-bar \
        --connect-timeout 10 \
        --max-time 300 \
        -F "file=@$FILE" \
        https://store1.gofile.io/contents/uploadfile \
    || curl --fail --progress-bar \
        --connect-timeout 10 \
        --max-time 300 \
        -F "file=@$FILE" \
        https://store2.gofile.io/contents/uploadfile \
    || echo "⚠️ Upload falhou"
}

# ================= MAIN =================
rm -f compile.log

(
    BUILD_KERNEL
    PACKAGE_KERNEL "$KERNEL_NAME_T"
    UPLOAD "$KERNEL_NAME_T"

    cp "$ORIGINAL" "$BACKUP"
    sed -i 's/^CONFIG_CAMERA_BOOTCLOCK_TIMESTAMP=.*/# CONFIG_CAMERA_BOOTCLOCK_TIMESTAMP is not set/' "$ORIGINAL"

    BUILD_KERNEL
    PACKAGE_KERNEL "$KERNEL_NAME_R"
    UPLOAD "$KERNEL_NAME_R"

    mv "$BACKUP" "$ORIGINAL"
) | tee compile.log

echo -e "\n✅ Completed in $((SECONDS / 60))m $((SECONDS % 60))s\n"