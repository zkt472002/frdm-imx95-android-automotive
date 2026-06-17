#!/usr/bin/env bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nguyen Minh Tien <zizuzacker@gmail.com>
# Blog: https://embeddedlinux.blog/
# Created: 2026-06-17
#
# get_all_prerequisite.sh
# -----------------------
# One-shot host setup for building Android Automotive (imx-automotive-16.0.0_1.3.0)
# for FRDM-IMX95 on Ubuntu 22.04.
#
# Installs:
#   1. Host build packages (apt)
#   2. AArch64 GCC   (U-Boot / kernel)
#   3. AArch32 GCC   (Cortex-M firmware)
#   4. Cortex-M GCC  (M7 FW / System Manager)
#   5. Android kernel prebuilts (clang, build-tools, rust, clang-tools) pinned by SHA
#   6. Persists the required env vars to ~/.bashrc
#
# Re-running is safe: each step is skipped if its target already exists.
# Toolchains are installed under /opt (needs sudo). Run as a normal user; the
# script calls sudo only where required.
#
set -euo pipefail

OPT=/opt
PREBUILTS="${OPT}/android-kernel-prebuilts-6.12"

AARCH64_DIR="${OPT}/arm-gnu-toolchain-12.3.rel1-x86_64-aarch64-none-linux-gnu"
AARCH32_DIR="${OPT}/arm-gnu-toolchain-12.3.rel1-x86_64-arm-none-eabi"
ARMGCC_DIR_PATH="${OPT}/gcc-arm-none-eabi-9-2020-q2-update"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

# --- 1. Host packages -------------------------------------------------------
log "Installing host build packages (apt)"
sudo apt-get update
sudo apt-get install -y \
  uuid uuid-dev \
  zlib1g-dev liblz-dev \
  liblzo2-2 liblzo2-dev \
  lzop \
  git curl \
  u-boot-tools \
  mtd-utils \
  android-sdk-libsparse-utils \
  device-tree-compiler \
  gdisk \
  m4 \
  bison \
  flex make \
  libssl-dev \
  gcc-multilib \
  libgnutls28-dev \
  swig \
  liblz4-tool \
  libdw-dev \
  dwarves \
  bc cpio tar lz4 rsync \
  ninja-build clang \
  build-essential \
  libncurses5 \
  xxd \
  unzip \
  efitools

# --- 2. AArch64 GCC (U-Boot / kernel) --------------------------------------
if [ ! -d "${AARCH64_DIR}" ]; then
  log "Installing AArch64 GCC -> ${AARCH64_DIR}"
  tmp=$(mktemp -d)
  curl -L -o "${tmp}/aarch64.tar.xz" \
    https://developer.arm.com/-/media/Files/downloads/gnu/12.3.rel1/binrel/arm-gnu-toolchain-12.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
  sudo tar -xJf "${tmp}/aarch64.tar.xz" -C "${OPT}"
  rm -rf "${tmp}"
else
  log "AArch64 GCC already present, skipping"
fi

# --- 3. AArch32 GCC (Cortex-M firmware) ------------------------------------
if [ ! -d "${AARCH32_DIR}" ]; then
  log "Installing AArch32 GCC -> ${AARCH32_DIR}"
  tmp=$(mktemp -d)
  curl -L -o "${tmp}/aarch32.tar.xz" \
    https://developer.arm.com/-/media/Files/downloads/gnu/12.3.rel1/binrel/arm-gnu-toolchain-12.3.rel1-x86_64-arm-none-eabi.tar.xz
  sudo tar -xJf "${tmp}/aarch32.tar.xz" -C "${OPT}"
  rm -rf "${tmp}"
else
  log "AArch32 GCC already present, skipping"
fi

# --- 4. Cortex-M GCC (M7 FW / System Manager) ------------------------------
if [ ! -d "${ARMGCC_DIR_PATH}" ]; then
  log "Installing Cortex-M GCC -> ${ARMGCC_DIR_PATH}"
  tmp=$(mktemp -d)
  curl -L -o "${tmp}/armgcc.tar.bz2" \
    https://developer.arm.com/-/media/Files/downloads/gnu-rm/9-2020q2/gcc-arm-none-eabi-9-2020-q2-update-x86_64-linux.tar.bz2
  sudo tar -xjf "${tmp}/armgcc.tar.bz2" -C "${OPT}"
  rm -rf "${tmp}"
else
  log "Cortex-M GCC already present, skipping"
fi

# --- 5. Android kernel prebuilts (pinned by SHA) ---------------------------
# clone_pinned <repo-url> <dest> <sha>
clone_pinned() {
  local url="$1" dest="$2" sha="$3"
  if [ -d "${dest}/.git" ]; then
    log "Prebuilt already present: ${dest} (skipping)"
    return
  fi
  log "Fetching $(basename "${dest}") @ ${sha:0:12}"
  sudo git clone --no-checkout --depth 1 "${url}" "${dest}"
  sudo git -C "${dest}" fetch --depth 1 origin "${sha}"
  sudo git -C "${dest}" checkout "${sha}"
}

clone_pinned https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
  "${PREBUILTS}/clang/host/linux-x86" 66acdd82ee62e4aaa4248f03191c59dfed9db193
clone_pinned https://android.googlesource.com/kernel/prebuilts/build-tools \
  "${PREBUILTS}/kernel-build-tools" 3c5e4f14b451ec85167c38b917d2459687abd7f4
clone_pinned https://android.googlesource.com/platform/prebuilts/rust \
  "${PREBUILTS}/rust" 5156e7f81ae254c79ee736e44c960e75ad685c67
clone_pinned https://android.googlesource.com/platform/prebuilts/clang-tools \
  "${PREBUILTS}/clang-tools" 17329f6590e2872dcf04a0c96a176be089470cd9

# --- 6. Persist env vars ----------------------------------------------------
BASHRC="${HOME}/.bashrc"
MARK="# >>> frdm-imx95-android toolchains >>>"
if ! grep -qF "${MARK}" "${BASHRC}" 2>/dev/null; then
  log "Appending toolchain env vars to ${BASHRC}"
  {
    echo ""
    echo "${MARK}"
    echo "export AARCH64_GCC_CROSS_COMPILE=${AARCH64_DIR}/bin/aarch64-none-linux-gnu-"
    echo "export AARCH32_GCC_CROSS_COMPILE=${AARCH32_DIR}/bin/arm-none-eabi-"
    echo "export ARMGCC_DIR=${ARMGCC_DIR_PATH}"
    echo "export KERNEL_PREBUILTS_PATH=${PREBUILTS}"
    echo "# <<< frdm-imx95-android toolchains <<<"
  } >> "${BASHRC}"
else
  log "Toolchain env vars already in ${BASHRC}, skipping"
fi

log "Done. Open a new shell (or 'source ${BASHRC}') so the env vars take effect."
echo "    Next: configure git, download the NXP BSP, then 'repo sync' (see README)."
