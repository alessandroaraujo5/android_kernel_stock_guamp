#!/bin/bash
set -e

# ================= CONFIG =================
DEVICE="$1"
UPLD=1

if [ -z "$DEVICE" ]; then
    echo "Uso: ./build.sh <device>"
    exit 1
fi

UPLD_PROV="https://oshi.at"
UPLD_PROV2="https://transfer.sh"

# ================= DEPENDÊNCIAS =================
sudo apt-get update
sudo apt-get install -y \
    bc bison flex \
    build-essential \
    libssl-dev libelf-dev \
    ccache zip curl git

# ================= TOOLCHAIN =================
mkdir -p clang
curl -L https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android11-release/clang-r383902.tar.gz \
| tar -xz -C clang

git clone --depth=1 -b android11-release \
https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
binutils

git clone --depth=1 -b android11-release \
https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 \
binutils-32

# ================= ANYKERNEL =================
git clone --depth=1 https://github.com/100Daisy/AnyKernel3 -b "sunburn-$DEVICE"

# ================= ENV =================
export PATH="$PWD/clang/bin:$PWD/binutils/bin:$PWD/binutils-32/bin:$PATH"
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1

# ================= BUILD =================
rm -rf out
mkdir out

make vendor/sunburn-"$DEVICE"_defconfig O=out ARCH=arm64

make -j"$(nproc)" \
    O=out \
    ARCH=arm64 \
    CC=clang \
    HOSTCC=clang \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi-

# ================= PACKAGE =================
IMG="out/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
    echo "❌ Build falhou"
    exit 1
fi

cp "$IMG" AnyKernel3/
cd AnyKernel3

BUILD_TIME=$(date +"%d%m%Y-%H%M")
KERNEL_NAME="SunBurn-$DEVICE-$BUILD_TIME"
zip -r9 "$KERNEL_NAME.zip" ./*

cd ..

# ================= UPLOAD =================
if [ "$UPLD" = 1 ]; then
    curl -T "AnyKernel3/$KERNEL_NAME.zip" "$UPLD_PROV"
    echo
    curl -T "AnyKernel3/$KERNEL_NAME.zip" "$UPLD_PROV2"
fi

echo "✅ Kernel gerado: AnyKernel3/$KERNEL_NAME.zip"