<!--
SPDX-License-Identifier: MIT
Copyright (c) 2026 Nguyen Minh Tien <zizuzacker@gmail.com>
Blog: https://embeddedlinux.blog/
Created: 2026-06-17
-->

# Android Automotive OS on FRDM-IMX95

*by Nguyen Minh Tien · [embeddedlinux.blog](https://embeddedlinux.blog/) · 2026-06-17*

Build and boot **Android Automotive OS (AAOS)** on the NXP **FRDM-IMX95** (15×15) using the
`imx-automotive-16.0.0_1.3.0` BSP — which officially targets only the **i.MX95 EVK** (19×19).
This repo documents the adaptation and ships the patches that make it boot.

> **Unofficial.** Not affiliated with NXP. You must download the NXP BSP yourself under its
> EULA — no NXP source or blobs are redistributed here, only small interoperability diffs.

## Tested against

| | |
|---|---|
| BSP | `imx-automotive-16.0.0_1.3.0` |
| Android | 16 (`android-16.0.0_r4`) |
| Kernel | 6.12.58 (merged with AOSP GKI `android16-6.12-2025-12_r7`) |
| U-Boot | v2025.04 |
| GPU | Mali-G310 (proprietary `r54p1-11eac0`) |
| TEE | Trusty OS |
| Board | FRDM-IMX95 (15×15, LPDDR4X) |
| Result | Boots to `sys.boot_completed=1` — CarService, Mali, DRM/DPU, SurfaceFlinger up |

> NXP renames/moves these files between BSP releases. If a patch doesn't apply cleanly,
> check the version above first — line numbers drift across releases.

## TL;DR — what the EVK→FRDM port actually takes

**4 small patches + flashing to eMMC over UUU.** Two of the patches fix real NXP
build-script bugs that otherwise brick the boot:

1. **DDR OEI mismatch** — the stock script ships the EVK's LPDDR5 DDR timing in the FRDM
   SPL, so the 15×15 LPDDR4X board fails DDR training:
   `DDR OEI: Board mx95lp5 ... done, err = -1` and hangs before U-Boot.
2. **UUU flash rejects the FRDM target** — `illegal parameter "15x15-frdm"`, because the
   flash script's validation arrays omit it (even though it can build the image).

Patches live in [`patches/`](patches/) and are **applied by hand** (see
[§4](#4-apply-the-patches-by-hand)).

## Repo layout

```
patches/   the diffs (0000 = all-in-one; 0001–0004 = individual). Apply by hand.
scripts/   get_all_prerequisite.sh — installs host packages + cross toolchains
README.md  this guide
```

---

## 0. Hardware / host requirements

- Ubuntu 22.04 64-bit build host
- **450 GB** free disk (source ~100 GB + build output ~80–120 GB)
- **32 GB RAM** (or 16 GB + 32 GB swap — works, just slower; lower the `-j` on build)
- NXP.com account (for the proprietary package download)
- Internet (`repo sync` pulls ~100–120 GB)
- An FRDM-IMX95 board, a USB-C cable to the **i.MX USB1** port, and a UART console

Throughout this guide:

```bash
export WORKSPACE=$HOME/frdm-imx95-android-automotive/workspace          # where repo sync lives
export BSP_DIR=$HOME/frdm-imx95-android-automotive/imx-automotive-16.0.0_1.3.0   # unpacked NXP package
export MY_ANDROID=${WORKSPACE}/android_build         # the synced source tree
```

---

## 1. Prerequisites — run the script

```bash
./scripts/get_all_prerequisite.sh
```

This installs everything in Steps 1–2 of NXP's guide, idempotently:

- host build packages (apt)
- AArch64 GCC (U-Boot/kernel), AArch32 GCC (Cortex-M), Cortex-M GCC (M7/SM) under `/opt`
- Android kernel prebuilts (clang, build-tools, rust, clang-tools), pinned by SHA
- appends the toolchain env vars to `~/.bashrc`

Open a new shell afterwards (or `source ~/.bashrc`). Then set your git identity:

```bash
git config --global user.name  "Your Name"
git config --global user.email "your.email@example.com"
```

---

## 2. Download the proprietary package from NXP

Requires NXP.com login + EULA acceptance:
<https://www.nxp.com/webapp/Download?colCode=16.0.0_1.3.0_AUTOMOTIVE_SOURCE&appType=license>

If that link 404s, search **"i.MX Android Automotive"** on nxp.com, or:
**Design Center → Software → i.MX Software → Android → Automotive releases**.

Unpack `imx-automotive-16.0.0_1.3.0.tar.gz` to `${BSP_DIR}`. It contains
`imx_android_setup.sh` (the master setup script) plus the proprietary HAL binaries,
firmware blobs, and GPU drivers.

---

## 3. Sync the source

```bash
# repo tool
mkdir -p ~/bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
export PATH=${PATH}:~/bin

mkdir -p ${WORKSPACE} && cd ${WORKSPACE}

# NXP setup: repo init + repo sync + copy proprietary blobs into place
source ${BSP_DIR}/imx_android_setup.sh
```

This runs `repo init -u https://github.com/nxp-imx/imx-manifest -b imx-android-16
-m imx-automotive-16.0.0_1.3.0.xml`, syncs (~100–120 GB, hours), and copies the blobs.
The source tree ends up at `${MY_ANDROID}`.

**If `wireless-regdb` sync fails with an SSL error:**

```bash
git config --global http.sslVerify false
# then re-run: source ${BSP_DIR}/imx_android_setup.sh
```

---

## 4. Apply the patches (by hand)

The diffs are rooted at `device/nxp/`, so apply them from there with `-p1`. **Apply the
all-in-one `0000` OR the individual `0001–0004` — not both** (they overlap and will
conflict).

```bash
cd ${MY_ANDROID}/device/nxp
PATCHES=/path/to/this/repo/patches

# sanity-check first
git apply --check ${PATCHES}/0000-frdm-imx95-automotive-boot-all.patch

# Option A — everything at once:
git apply ${PATCHES}/0000-frdm-imx95-automotive-boot-all.patch

# Option B — individually (do NOT also apply 0000):
#   git apply ${PATCHES}/0001-ddr-oei-build-both-lpddr4x-and-lpddr5.patch
#   git apply ${PATCHES}/0002-add-frdm-bootloader-config-to-car-section.patch
#   git apply ${PATCHES}/0003-add-frdm-dtb-to-car2-dts-config.patch
#   git apply ${PATCHES}/0004-uuu-accept-15x15-frdm-feature.patch
```

> If `git apply` complains (whitespace / line drift on a different BSP rev), fall back to
> `patch -p1 < ${PATCHES}/0000-...patch` from `${MY_ANDROID}/device/nxp`, or apply the
> changes by reading §6 below and editing the 3 files by hand.

What each patch does:

| Patch | File(s) | Why |
|---|---|---|
| `0001` | `imx9/evk_95/AndroidUboot.sh` | **DDR fix** — build *both* DDR OEI variants unconditionally so the FRDM SPL ships LPDDR4X timing (see §6.5) |
| `0002` | `imx9/evk_95/UbootKernelBoardConfig.mk` | add the FRDM bootloader + UUU target to the CAR section |
| `0003` | `imx9/evk_95/BoardConfig.mk` | add the FRDM DTB to the car2 DTS config |
| `0004` | `common/tools/uuu_imx_android_flash.sh` | let the UUU flash script accept the `15x15-frdm` feature |
| `0000` | all of the above | convenience all-in-one |

> The UUU change (`0004`) also has to be applied to the **built output copy** of the
> script you actually run — see [§7.0](#70-patch-the-uuu-flash-script).

---

## 5. Build the EVK-95 automotive target (validation)

Build stock EVK-95 first to validate the environment before adapting for FRDM.

```bash
cd ${MY_ANDROID}
source build/envsetup.sh
lunch evk_95_car2-nxp_stable-userdebug
./imx-make.sh -j$(nproc) 2>&1 | tee build-log.txt
```

**Why `evk_95_car2` not `evk_95_car`:** `car2` runs EVS on the Cortex-A cores (no M7
firmware dependency at boot) — simpler. `car` runs EVS on the Cortex-M7 and needs the M7
firmware ready before Android boots. Build time ~4–8 h on a 12-core / 32 GB host.
Output: `${MY_ANDROID}/out/target/product/evk_95/`.

### Key output images

| File | Description |
|---|---|
| `spl-imx95.bin` | SPL (first-stage bootloader, eMMC boot0) |
| `bootloader-imx95.img` | U-Boot proper (bootloader_a/b) |
| `boot.img` | Android boot image (kernel + ramdisk) |
| `vendor_boot.img` | Vendor boot image |
| `super.img` | system + vendor + product |
| `dtbo-imx95.img` | Device tree overlay image |
| `vbmeta-imx95.img` | Verified boot metadata |
| `partition-table.img` | GPT table |
| `u-boot-imx95-evk-uuu.imx` | Bootloader for UUU flashing |

---

## 6. Adapt for FRDM-IMX95

After verifying the EVK build, the patches in §4 are exactly the following changes. Good
news from the source tree: the car2 DTBO overlay is board-agnostic, the FRDM kernel DTB +
overlays already exist, and the SM firmware/GPU/ATF are all SoC-level.

> **The gotcha (§6.5):** `AndroidUboot.sh`'s `build_pre_image()` is *meant* to select the
> FRDM OEI (`mx95lp4x-15`, LPDDR4X) when the config name contains `15x15`, but it checks
> `$2` — an argument `uboot.mk` never passes. So the stock script only ever builds the EVK
> `mx95lp5` (LPDDR5) OEI, the FRDM SPL boots with the wrong DDR timing
> (`DDR OEI: Board mx95lp5 ... err = -1`), and the board hangs before U-Boot.

### 6.1 — `UbootKernelBoardConfig.mk` (patch 0002)

Add FRDM to the car2 block, and the FRDM UUU target:

```makefile
# In the PRODUCT_IMX_CAR=true, car2 block:
    TARGET_BOOTLOADER_CONFIG += imx95-15x15-frdm:imx95_15x15_frdm_android_trusty_dual_defconfig
# After the existing verdin-uuu line (move it out of the non-CAR section):
TARGET_BOOTLOADER_CONFIG += imx95-15x15-frdm-uuu:imx95_15x15_frdm_android_uuu_defconfig
```

The name `imx95-15x15-frdm` contains `15x15`, which makes `AndroidUboot.sh` build the OEI
with `board=mx95lp4x-15`, copy `imx95_15x15_mcu_demo.img` as M7 firmware, and build mkimage
with `LPDDR_TYPE=lpddr4x`.

### 6.2 — `BoardConfig.mk` (patch 0003)

The FRDM DTS config exists only in the non-CAR section. Add it to the car2 section:

```makefile
    TARGET_BOARD_DTS_CONFIG += imx95-15x15-frdm:imx95-15x15-frdm.dtb
```

### 6.3 — car2 DTBO overlay (no change)

`imx95-19x19-evk-car2.dtso` only does `&vehicle_core { status = "okay"; };` — board-agnostic.
The kernel's `imx95-15x15-frdm.dts` defines the base hardware; the overlay just enables the
Vehicle HAL node on top.

### 6.4 — U-Boot defconfig (use existing)

Use `imx95_15x15_frdm_android_trusty_dual_defconfig` directly. Versus the EVK
`androidauto2_trusty` config the differences are minor U-Boot features (splash/display
removed, `CONFIG_ANDROID_AUTO_SUPPORT=y`, attestation ID). Android overrides partition
layout via GPT at flash time, so it doesn't care. (You can author a proper FRDM automotive
defconfig later if you want.)

### 6.5 — `AndroidUboot.sh` — build the FRDM OEI (patch 0001) — **the DDR fix**

`build_pre_image()` picks the OEI by inspecting `$2`, but `uboot.mk` calls it with no
args, so the `15x15` branch never runs and only the LPDDR5 OEI gets built. Fix: build
**both** DDR OEI variants unconditionally, so whichever one `build_imx_uboot` later needs is
present:

```bash
# replace the `if echo "$2" | grep -q "15x15"` block (after the `oei=tcm` line) with:
    make -C ${BOARD_OEI_PATH} OEI_CROSS_COMPILE="${SM_OEI_CROSS_COMPILE}" board=mx95lp4x-15 r=b0 oei=ddr d=1 all 1>/dev/null || exit 1
    make -C ${BOARD_OEI_PATH} OEI_CROSS_COMPILE="${SM_OEI_CROSS_COMPILE}" board=mx95lp5    r=b0 oei=ddr d=1 all 1>/dev/null || exit 1
```

Then rebuild just the bootloader: `./imx-make.sh bootloader -j$(nproc)`. A correct boot
shows `DDR OEI: ... Board mx95lp4x-15 ... TRAINING complete ... err = 0`.

### 6.6 — Kernel & SM (no change)

Kernel DTB (`imx95-15x15-frdm.dts` + overlays), `gki_defconfig` + `imx95_car_gki.fragment`,
the SM firmware (`mx95evk-android`, SoC-level), Mali, and ATF/BL31 all work as-is.

---

## 7. Flash to FRDM-IMX95 (eMMC via UUU)

**Flash to eMMC, not SD.** The Trusty dual-bootloader image needs the eMMC RPMB hardware
partition for secure storage; NXP's script hard-blocks `-t sd` with Trusty
(*"can not boot up from SD with trusty enabled"*).

### 7.0 — Patch the UUU flash script

Patch `0004` covers the source, but you must also patch the **built output copy** — that's
the one you run:

- `${MY_ANDROID}/device/nxp/common/tools/uuu_imx_android_flash.sh` (source — patch 0004)
- `${MY_ANDROID}/out/target/product/evk_95/uuu_imx_android_flash.sh` (output — patch by hand)

```bash
# append 15x15-frdm to the two imx95 arrays in each file:
imx95_uboot_feature=(evk-uuu secure-unlock verdin verdin-uuu 15x15-frdm)
imx95_dtb_feature=(... verdin-adv7535-ap1302 15x15-frdm)
```

### 7.1 — Install UUU ≥ 1.5.x

The script needs `uuu ≥ 1.5.179`. **Ubuntu's apt `uuu` (1.4.193) is too old.**

```bash
cd /tmp
wget https://github.com/nxp-imx/mfgtools/releases/download/uuu_1.5.201/uuu
sudo install -m 0755 uuu /usr/local/bin/uuu
uuu -v        # confirm 1.5.x
```

### 7.2 — Serial-download mode

i.MX95 serial download = `BOOT_MODE[3:0] = X001`, **USB 2.0 / USB1 only**:

1. Set FRDM boot switch **SW7 = `1001`**.
2. Connect the **i.MX USB1 USB-C port** to the host — **NOT** the MCU-Link/debug-UART
   USB-C (that one enumerates as `1a86:55d5 QinHeng Quad_Serial` and gives the `ttyACM`
   console; it cannot download).
3. Power-cycle (boot mode is latched only at power-on reset).

Verify the SoC enumerated as the downloader before flashing:

```bash
lsusb | grep 1fc9       # expect: 1fc9:015d NXP Semiconductors OO Blank 95
```

If it doesn't appear: wrong USB-C port, charge-only cable, or boot switch not in `X001`
(try `SW7 = 0001` if your board's switch bit-order is reversed).

### 7.3 — Flash

```bash
cd ${MY_ANDROID}/out/target/product/evk_95
sudo ./uuu_imx_android_flash.sh -f imx95 -u 15x15-frdm -d 15x15-frdm -e
```

- `-u 15x15-frdm` → FRDM SPL + bootloader + `u-boot-imx95-15x15-frdm-uuu.imx` USB loader
- `-d 15x15-frdm` → FRDM `dtbo` + `vbmeta`
- `-e` → erase userdata; default target is eMMC; dual-bootloader auto-detected from GPT

Wait for `>>> Flashing successfully completed <<<` (the ~1.3 GB `super` partition is the
slow part over USB 2.0).

### Boot mode switches (FRDM-IMX95)

| Mode | SW7 (1–4) | BOOT_MODE | |
|---|---|---|---|
| Serial download (UUU) | `1001` | `X001` | Flashing via USB1 |
| eMMC boot | `0010` | — | Normal boot |

After flashing: set **SW7 = `0010`** and power-cycle. Boot path:
SPL → BL31/Trusty → U-Boot → kernel → Android Automotive.

### Why not SD / `dd`

- **Trusty + SD is blocked** — no RPMB on SD; the script refuses it and you hit
  `rpmb_storage_send failed` / `bad static rpmb size`.
- **`dd` makes an invalid GPT** — `partition-table.img` is only the *primary* GPT; `dd`
  never writes the backup GPT, so U-Boot rejects it (`GPT is invalid` → `Load metadata fail`).

If you really need SD boot, rebuild U-Boot with the **non-Trusty**
`imx95_15x15_frdm_android_defconfig` and flash `-t sd` — you lose TEE-backed Keymint /
secure storage.

### First-boot known issues (non-fatal)

A good boot reaches `sys.boot_completed=1` (~75 s) with CarService, Mali, DRM/DPU, and
SurfaceFlinger up. Expected non-fatal items:

| Symptom | Meaning | Action |
|---|---|---|
| `Authentication key not yet programmed`, `rpmb_storage_send failed`, `AVB ... Public key rejected`, `Keymaster TIPC client not initialized` | eMMC RPMB exists but its auth key isn't provisioned; boots only because the device is `UNLOCK`. Verified boot/attestation degraded. | One-time RPMB key provisioning; fine to ignore for dev. |
| U-Boot `Fail to setup video link`; kernel `pixel-interleaver Failed to create device link` | No display panel/HDMI link (GPU/DRM stack itself is fine). | Connect a supported display + a display overlay (see Issue 5). |
| `bad CRC, using default environment` | U-Boot env not yet written. | `saveenv` at the U-Boot prompt. |
| `avc: denied` for `life_time`/`pre_eol_info`, `arm.mali.platform.ICompression`, `/dev/hidraw*` | Enforced SELinux denials for eMMC-health sysfs, Mali compression HAL, EVS HID probing. | Cosmetic on first boot; add sepolicy allow rules if needed. |

---

## Build targets reference

| Lunch target | Description | Use case |
|---|---|---|
| `evk_95_car-nxp_stable-userdebug` | AAOS + EVS on M7 | Full automotive with early camera |
| `evk_95_car2-nxp_stable-userdebug` | AAOS + EVS on A55 | Simpler — recommended for FRDM |
| `evk_95-nxp_stable-userdebug` | Regular Android (not automotive) | If AAOS isn't needed |

### car vs car2

| Feature | evk_95_car | evk_95_car2 |
|---|---|---|
| EVS on M7 (early boot camera) | Yes | No |
| EVS on A55 (after Android boot) | Yes | Yes |
| M7 firmware required | Yes | No |
| U-Boot defconfig | `*_androidauto_trusty_*` | `*_androidauto2_trusty_*` |
| Complexity for FRDM port | Higher (M7 FW adaptation) | Lower (recommended first) |

---

## Troubleshooting

**Build OOM (`ninja`/`javac` killed, signal 9).** Lower parallelism (`./imx-make.sh -j6`),
or build in stages: `./imx-make.sh bootloader kernel -j$(nproc)` then `make -j4`.

**No space left on device.** Build output grows to ~80–120 GB. Free space (clear large
stale caches/downloads) or extend the disk before building.

**FRDM boots to U-Boot but kernel panics/hangs (wrong DTB).** Ensure §6.2 is applied. At
the U-Boot prompt: `printenv fdtfile` should be `imx95-15x15-frdm.dtb`; if not,
`setenv fdtfile imx95-15x15-frdm.dtb; saveenv`.

**`DDR OEI: ... Board mx95lp5 ... err = -1` (hangs before U-Boot).** The FRDM SPL shipped
the LPDDR5 OEI. Apply patch `0001` (§6.5), rebuild the bootloader. This is a build-script
bug, **not** a naming problem — your `TARGET_BOOTLOADER_CONFIG` name was already correct;
the OEI binary it needed simply was never compiled.

**No display output (ADB works, no HDMI).** Likely a missing display overlay, not a driver
issue (Mali is SoC-level). Check overlays:
`ls vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx95-15x15-frdm-*`
(e.g. `-boe-wxga-lvds-panel.dts`, `-waveshare-7inch-c-panel.dtso`).

**Vehicle HAL not found / Car apps missing.** The car2 DTBO wasn't applied. Verify:
`adb shell dmesg | grep vehicle` — `vehicle_core` should be `okay`.

---

## NXP documents

| Document | ID |
|---|---|
| Android Automotive User's Guide | UG10176 |
| Android Automotive Quick Start Guide | UG10177 |
| Android Security User's Guide | UG10158-AUTO |
| ML User Guide for Android | UG10338 |
| Release Notes | RN00227 |

---

## Author

**Nguyen Minh Tien** — <zizuzacker@gmail.com>
Blog: <https://embeddedlinux.blog/> · GitHub: [@Zk47T](https://github.com/Zk47T)

If this saved you time, a ⭐ on the repo or a visit to the blog is appreciated.

## License

[MIT](LICENSE) — covers the guide, patches, and scripts in this repo only. The NXP BSP and
the files these patches modify remain under NXP's own license; download them from NXP.
