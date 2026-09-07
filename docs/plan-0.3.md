<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Plan — MIS Linux 0.3

**Status:** current tree (`VERSION=0.3`), close-out, then bump.  
**Operator notes:** [`operator-0.3.md`](operator-0.3.md)  
**Overlays design:** [`overlays.md`](overlays.md)

## What 0.3 owned

- Recipes 05-cross through 10-boot, including linux 7.1.8 and GRUB EFI
  (`EFI/misl` + `BOOTX64.EFI`, `--no-nvram`)
- OpenSSH 10.5p1 after e2fsprogs (`--without-ssl-engine`); nano 9.2
- `misl enter` remounts a stale chroot-prep bind; `misl net on|off`
- `misl sources integrate` (host wget only; `--reintegrate` to change a version)
- Overlays: `terminal` default, `cloud` + `cloud/do` alpha,
  `terminal/tui` / `desktop` / `cloud/aws` / `cloud/gcp` stub
- `misl cloud apply|install|sanitize`, incoming cloud-init 26.2
- `misl img pack` BIOS GPT from the tree (`--from-disk` is the EFI
  volume for metal). `img test` if host qemu exists
- Live ISO/USB: `iso pack|test|inspect|usb`. Kernel has SquashFS,
  overlay, and iso9660 built-in (`CONFIG_SQUASHFS=y`)
- Policy A disk. No swap. `MISL_MAKEFLAGS=-j2` on the 2C/4G VPS
