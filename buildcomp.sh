#!/bin/bash

# ================= COLOR =================
cyan='\033[0;36m'
blue='\033[0;34m'
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
white='\033[0m'

# ================= HEADER =================
echo -e "$cyan===========================\033[0m"
echo -e "$cyan= START COMPILING KERNEL  =\033[0m"
echo -e "$cyan===========================\033[0m"
echo -e "$blue...KSABAR...\033[0m"

echo -e -ne "$green==                        (10%)\r"; sleep 0.7
echo -e -ne "$green=====                     (33%)\r"; sleep 0.7
echo -e -ne "$green=============             (66%)\r"; sleep 0.7
echo -e -ne "$green=======================   (100%)\r"
echo -ne "\n"


# ================= PATH =================
DEFCONFIG=vendor/vince_defconfig
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ========== TOOLCHAIN (CLANG) ===========
export PATH="$ROOTDIR/clang-zyc/bin:$PATH"

# ================= BUILD USER/HOST =================
export KBUILD_BUILD_USER=RahmatSobrian
export KBUILD_BUILD_HOST=Github

# ================= INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="Vince"
CLANG="WeebX Clang"

# =============== DATE (WIB) ===============
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y")

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
IMG_USED="unknown"
MD5_HASH="unknown"
ZIP_NAME=""

# ================= FUNCTION =================
clone_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        echo -e "$yellow[+] Cloning AnyKernel3...$white"
        git clone -b vince https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1
    fi
}

get_toolchain_info() {
    if command -v clang >/dev/null 2>&1; then
        if clang --version | grep -qi "WeebX\|XSans0"; then
            CLANG_VER=$(clang --version | head -n1 | sed 's/.*version //')
            TC_INFO="WeebX Clang ${CLANG_VER}"
        else
            CLANG_VER=$(clang --version | head -n1)
            TC_INFO="Clang (${CLANG_VER})"
        fi
    else
        TC_INFO="$CLANG (not found in PATH)"
    fi
}

get_kernel_version() {
    if [ -f "Makefile" ]; then
        VERSION=$(grep -E '^VERSION =' Makefile | awk '{print $3}')
        PATCHLEVEL=$(grep -E '^PATCHLEVEL =' Makefile | awk '{print $3}')
        SUBLEVEL=$(grep -E '^SUBLEVEL =' Makefile | awk '{print $3}')
        KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
    else
        KERNEL_VERSION="unknown"
    fi
}

send_telegram_start() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="🚀 *Kernel CI Build Test Started*"
}

send_telegram_error() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="❌ *Kernel CI Build Test Failed*

📄 *Log attached below*"
    send_telegram_log
}

send_telegram_log() {
    LOG_FILE="$ROOTDIR/logs/build.txt"
    [ ! -f "$LOG_FILE" ] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${LOG_FILE}"
}

# ================= CLEAN =================
clean() {
    echo -e "\n$red[!] CLEANING UP$white\n"
    rm -rf out
    make mrproper
}

# ================= BUILD KERNEL =================
build_kernel() {
    echo -e "$yellow[+] Sending telegram start...$white"
    send_telegram_start

    echo -e "$yellow[+] Getting toolchain info...$white"
    get_toolchain_info

    echo -e "$yellow[+] Removing out folder...$white"
    rm -rf out

    echo -e "$yellow[+] Creating out folder...$white"
    mkdir -p out

    echo -e "$yellow[+] Preparing kernel config...$white"
    echo -e "$green==================================\033[0m"
    echo -e "$green= [!] START BUILD ${DEFCONFIG}\033[0m"
    echo -e "$green==================================\033[0m"

    make O=out ARCH=arm64 ${DEFCONFIG} || {
        echo -e "\n$red[!] DEFCONFIG FAILED$white\n"
        send_telegram_error
        exit 1
    }

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    echo -e "$yellow[+] Building Kernel...$white"
    make -j$(nproc --all) \
      O=out \
      ARCH=arm64 \
      CC=clang \
      LD=ld.lld \
      LLVM=1 \
      LLVM_IAS=1 \
      CROSS_COMPILE=aarch64-linux-gnu- \
      CROSS_COMPILE_ARM32=arm-linux-gnueabi- || {
        echo -e "\n$red[!] BUILD FAILED$white\n"
        send_telegram_error
        exit 1
    }

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    echo -e "$yellow[+] Getting kernel version...$white"
    get_kernel_version

    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

# =============== PACK KERNEL ===============
pack_kernel() {
    echo -e "$yellow[+] Cloning AnyKernel...$white"
    clone_anykernel

    echo -e "$yellow[+] Packing AnyKernel...$white"
    cd "$ANYKERNEL_DIR" || exit 1
    rm -f Image* *.zip

    if [ -f "$KIMG_DTB" ]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
    elif [ -f "$KIMG" ]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
    else
        echo -e "$red[!] FIX YOUR KERNEL SOURCE BRUH !?$white"
        send_telegram_error
        exit 1
    fi

    echo -e "$yellow[+] Zipping kernel...$white"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md"
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')

    echo -e "$green[✓] Zip created: $ZIP_NAME ($IMG_USED)$white"
}

# ============= UPLOAD TO TELEGRAM =============
upload_telegram() {
    ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"
    [ ! -f "$ZIP_PATH" ] && return

    echo -e "$yellow[+] Uploading to Telegram...$white"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${ZIP_PATH}" \
        -F parse_mode=Markdown \
        -F caption="🔥 *Kernel CI Build Test Success*

📱 *Device* : ${DEVICE}
📦 *Kernel Name* : ${KERNEL_NAME}
🍃 *Kernel Version* : ${KERNEL_VERSION}

🛠 *Toolchain* :
\`${TC_INFO}\`

⌛ *Build Time* : ${BUILD_TIME}
🕒 *Build Date* : ${BUILD_DATETIME}

🔐 *MD5* :
\`${MD5_HASH}\`

❓ *Need Test*"

    send_telegram_log

    echo -e "$green===========================\033[0m"
    echo -e "$green=  SUCCESS COMPILE KERNEL  \033[0m"
    echo -e "$green=  Device    : $DEVICE \033[0m"
    echo -e "$green=  Defconfig : $DEFCONFIG \033[0m"
    echo -e "$green=  Toolchain : $TC_INFO \033[0m"
    echo -e "$green=  Build Time: $BUILD_TIME \033[0m"
    echo -e "$green=  Have A Brick Day Nihahahah \033[0m"
    echo -e "$green===========================\033[0m"
}

# ================= RUN =================
START=$(TZ=Asia/Jakarta date +%s)

clean
build_kernel
pack_kernel
upload_telegram

END=$(TZ=Asia/Jakarta date +%s)
echo -e "$green[✓] Done in $((END - START)) seconds$white"
