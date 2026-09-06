<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# ASUS ROG Strix X570 — `desktop/asus/rog-strix-x570`

Status **alpha**. Parent `desktop` (applied automatically), `kernel=1`.
This is the reference layout for future board overlays: `kernel.list`,
`firmware.list`, `files/` (installed and owned by
`misl_overlay_install_files`), no custom apply logic.

## Hardware matrix

| Device | Chip | Driver (kernel.list) | Firmware (firmware.list) | Userland |
|---|---|---|---|---|
| 1G Ethernet | Intel I211 | `IGB=m` | none | networkd (`10-rog-wired.network`, `Driver=igb r8169`) |
| 2.5G Ethernet | Realtek RTL8125 | `R8169=m`, `REALTEK_PHY=m` | `rtl_nic/rtl8125*.fw` | same `.network` |
| Wi-Fi | Intel AX200 | `CFG80211`/`MAC80211`/`IWLWIFI`/`IWLMVM=m` | `iwlwifi-cc-a0-*.ucode` | wpa_supplicant 2.12 + libnl (group=wifi), `25-rog-wireless.network` |
| Bluetooth | AX200 (USB) | `BT=m`, `BT_HCIBTUSB=m` (selects `BT_INTEL`) | `intel/ibt-20-1-3.sfi`, `.ddc` | bluez 5.87 (group=bluetooth) |
| Audio | Realtek ALC1220A (HDA) | `SND_HDA_INTEL=m`, `SND_HDA_CODEC_REALTEK=m` (?) | none | **no alsa-utils** yet |
| CPU / platform | AMD Ryzen (Zen 2/3) | `CPU_SUP_AMD`, `MICROCODE`, `X86_AMD_PLATFORM_DEVICE`, `AMD_IOMMU`, `PINCTRL_AMD` | AMD ucode: initramfs | — |
| Sensors / WDT | k10temp, SP5100 TCO | `SENSORS_K10TEMP=m`, `SP5100_TCO=m` (optional) | none | lm-sensors (group=hw) |
| GPU | any | none on purpose | none | — |

`FW_LOADER_COMPRESS{,_XZ,_ZSTD}=y` so `.xz`/`.zst` firmware loads.

### Uncertain names (check on the VPS before the first ROG build)

- `SND_HDA_CODEC_REALTEK`: 6.17+ moved HDA codecs to `sound/hda/codecs/`;
  the symbol may have been split per codec family. If 10-boot/linux
  reports it did not stick, `grep -rn 'config SND_HDA_CODEC_' sound/` in
  the 7.1 tree and fix the line.
- `MICROCODE_AMD`: removed (folded into `MICROCODE`, def_bool on x86)
  in 6.7, so it is **not** listed; `MICROCODE=y` is.
- `BT_INTEL`, `REALTEK_PHY`: selected by `BT_HCIBTUSB` / `R8169`; only
  `REALTEK_PHY` is requested.
- Firmware names are from memory: `./misl firmware list
  desktop/asus/rog-strix-x570` against the staged tree (or `grep` in
  `WHENCE`). Early boards use `rtl8125a-3.fw`, later `rtl8125b-2.fw`;
  the glob covers both. AX200 BT may want `ibt-20-1-3` or a newer
  `ibt-0040-*` name on recent firmware trees — check `dmesg`.

### Adding a GPU

Append to `kernel.list` (one block), add the firmware, rebuild:

```
# AMD
DRM=y
DRM_AMDGPU=m
# firmware.list: amdgpu/<chip>_*.bin  (e.g. amdgpu/navi10_*)
# NVIDIA (nouveau)
DRM_NOUVEAU=m
# firmware.list: nvidia/<chip>/
```

The NVIDIA vendor driver is out of tree and not part of MISL.

## Regulatory database

`wireless-regdb` 2026.09.03 is built in 08-system (group=wifi):
`regulatory.db` + `.p7s` in `/usr/lib/firmware`, plus `iw` 6.17. Check
`iw reg get` after boot; set the country in
`/etc/modprobe.d/cfg80211.conf` (`options cfg80211 ieee80211_regdom=IL`).

## Userland (groups hw, wifi, bluetooth)

`packages=hw,wifi,bluetooth` in this overlay and in `desktop`. wifi:
libnl, wpa_supplicant, iw, wireless-regdb. bluetooth: bluez 5.87 (glib
is base). hw: hwdata, pciutils (`lspci`), libusb, usbutils (`lsusb`),
ethtool, alsa-lib/ucm-conf/utils, lm-sensors. **Stage and build with the target set**, the overlay is not
applied yet at 08-system time:

    MISL_TARGET_OVERLAYS=rog-strix-x570 ./misl sources stage
    ./misl groups            # hw, wifi, bluetooth (yes)

kernel.list adds BT_RFCOMM, BT_BNEP, BT_HIDP, UHID, INPUT_UINPUT for
the bluez profiles. sbcl is opt-in: `MISL_GROUPS=lisp`.

## Files installed

```
desktop:  /etc/systemd/network/30-wireless.network        (wl*, DHCP)
          /etc/systemd/system/timers.target.wants/fstrim.timer  (link made by apply.sh)
          /usr/share/doc/misl/desktop/{README,wpa_supplicant-IFACE.conf.example}
rog:      /etc/systemd/network/10-rog-wired.network       (Driver=igb r8169)
          /etc/systemd/network/25-rog-wireless.network    (Driver=iwlwifi)
          /etc/modprobe.d/misl-rog-strix-x570.conf        (comments only)
          /usr/share/doc/misl/rog-strix-x570/README
          /usr/lib/firmware/{rtl_nic,intel,iwlwifi-cc-a0-*}  (firmware.list)
```

Base (09-config) already provides `20-dhcp.network`, networkd,
resolved, timesyncd and `vconsole.conf`. Lower-numbered `.network`
files win, so the board's `Driver=` matches take precedence; both NICs
are `RequiredForOnline=no` so one unplugged port does not stall boot.

## Test checklist (on the board)

- [ ] `ip -br link` — two `enp*` and one `wlp*`.
- [ ] `networkctl` — wired `routable` via `10-rog-wired.network`.
- [ ] Wi-Fi: config from the desktop README, then
      `systemctl enable --now wpa_supplicant@wlpXs0`; `networkctl status wlpXs0` routable.
- [ ] `resolvectl status` — DNS from DHCP.
- [ ] `dmesg | grep -i firmware` — rtl8125, iwlwifi, ibt loaded, no `failed`
      except `regulatory.db`.
- [ ] Bluetooth: `ls /sys/class/bluetooth` shows `hci0` (no bluetoothctl yet).
- [ ] Audio: `ls /proc/asound/cards` lists HDA-Intel (no `aplay` yet).
- [ ] Sensors: `cat /sys/class/hwmon/hwmon*/name` includes `k10temp`.
- [ ] `systemctl list-timers fstrim.timer`.
- [ ] `./misl overlay undo desktop/asus/rog-strix-x570 desktop` on the
      host leaves the tree as before.
