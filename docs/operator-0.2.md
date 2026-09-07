<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Operator notes — MIS Linux 0.2

Freeze: **LFS 13.1-systemd** (stable). Docs: https://www.linuxfromscratch.org/lfs/view/systemd/
Sources: `misl-1.0-systemd/wget-list` only. Never `wget-list.original`.
Do not run `misl sources fetch` from an agent session (`MISL_FETCH=0` there).

Identity: bootstrap is **0.2** (major.minor only). Product goal is **1.0 (Farpoint)**
(`MISL_DIST_VERSION` / `MISL_DIST_CODENAME` in `config/misl.conf`). `misl version`
and `misl os-release` print the composed file. `misl bump minor|major|X.Y`
rewrites `VERSION`, `config/misl.conf`, and `config/misl.conf.example`
(`misl bump 1.0` sets Farpoint). `misl prep` writes os-release to
`$LFS/usr/lib/os-release` and `$LFS/etc/os-release`. Do not set `VERSION_ID=1.0`
until Farpoint ships.

## Parameters

| Knob              | This VPS                                                         |
|-------------------|------------------------------------------------------------------|
| `LFS`             | `/mnt/misl`                                                      |
| `MISL_DISK`       | `/dev/disk/by-id/scsi-0DO_Volume_misl`                           |
| `MISL_MAKEFLAGS`  | `-j2` (2 CPU / 4 GiB)                                            |
| `MISL_SNAPSHOT`   | `/var/cache/misl/misl-1.0-systemd` (shared with user `lfs`)      |
| `MISL_MIRROR`     | `https://makeitsolinux.org/downloads/misl-1.0-systemd`           |
| `MISL_FETCH`      | `1` on the VPS (`0` in agent sessions)                           |
| `MISL_FIRMWARE`   | `efi` (target machine). `bios` or `auto` if needed               |
| `MISL_PART_BOOT`  | `/dev/disk/by-id/scsi-0DO_Volume_misl-part1` (1 GiB FAT32 ESP)   |
| `MISL_PART_ROOT`  | `/dev/disk/by-id/scsi-0DO_Volume_misl-part2` (ext4 `/`)          |

Environment overrides `config/misl.conf`:

```
LFS=/mnt/misl MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl ./misl disk plan
```

`misl disk apply` still does **not** format in 0.2 (policy A). Run the printed
`parted`/`mkfs`/`mount` yourself. No swap partition.

## Snapshot fetch

`misl sources fetch` creates `$MISL_SNAPSHOT` if missing
(`/var/cache/misl/misl-1.0-systemd` unless you change it), pulls `wget-list` +
`md5sums` from `$MISL_MIRROR`, then wgets every needed file in the list into
`sources/` and `patches/`. Existing files are skipped. SysV leftovers on
`unused-sysv.list` are skipped. `wget-list.original` is refused.

The snapshot lives on the **host**, next to `mislinux/`. It is not the target
disk. `misl sources stage` hardlinks into `$LFS` after the volume is mounted.

Kernel tarball name is `linux-7.1.8.tar.xz`.

## Host user

Do **not** pre-create a build user. `misl prep` (as root) creates group and
user `lfs`, home `~lfs`, and the book chapter-4 `.bash_profile` / `.bashrc`
(including `MAKEFLAGS=-j2`). It also chowns `$LFS/{usr,var,tools,etc}` so
chapter 5 can write logs. If `lfs` cannot read the checkout under `/root`,
prep copies `mislinux/` into `~lfs/mislinux` (not the tarball snapshot).

Chapter 5–6 recipes refuse to run as root. There is no login user on the
*target* system in 0.2.

## What to run (Fedora 44 host, 50 GiB attached volume)

### Stage numbers

`stages/NN-*` follows LFS chapter numbers, not systemd or SysV. `01-variant/`
is reserved for a future distro/init picker. `02-host` and `02-disk` are
both chapter 2 (`misl doctor` and `misl disk`). `build-stage` starts at
`05-cross`.

### Config

`config/misl.conf` is already pinned for this host: `LFS=/mnt/misl`,
`MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl`, `MISL_MAKEFLAGS=-j2`,
`MISL_FIRMWARE=efi`, `MISL_FETCH=1`. Work from the `mislinux/` tree.

### Host toolchain

Minimal Fedora cloud images are missing gcc/binutils/bison and the book
`yacc` name. Fedora 44 `bison` does not ship `/usr/bin/yacc`.

```
./misl doctor install
./misl doctor
```

### Fetch sources (host disk, long)

```
./misl sources fetch
./misl sources check
```

### Disk plan

Default firmware is **efi** even on a BIOS droplet. Use `MISL_FIRMWARE=bios`
only if the machine that will *boot* this disk is BIOS.

```
./misl disk plan
```

### Partition and mount (destroys the volume)

Unmount first if you already laid out `bios_grub` or an ext4 `/boot`.

```
parted -s /dev/disk/by-id/scsi-0DO_Volume_misl mklabel gpt
parted -s /dev/disk/by-id/scsi-0DO_Volume_misl mkpart ESP fat32 1MiB 1025MiB
parted -s /dev/disk/by-id/scsi-0DO_Volume_misl set 1 esp on
parted -s /dev/disk/by-id/scsi-0DO_Volume_misl mkpart root ext4 1025MiB 100%
udevadm settle
mkfs.vfat -F32 /dev/disk/by-id/scsi-0DO_Volume_misl-part1
mkfs.ext4 -L misl /dev/disk/by-id/scsi-0DO_Volume_misl-part2
mkdir -p /mnt/misl
mount /dev/disk/by-id/scsi-0DO_Volume_misl-part2 /mnt/misl
mkdir -p /mnt/misl/boot/efi
mount /dev/disk/by-id/scsi-0DO_Volume_misl-part1 /mnt/misl/boot/efi
```

`10-boot/grub` writes `/boot/efi/EFI/misl/grubx64.efi` and the removable
`/boot/efi/EFI/BOOT/BOOTX64.EFI`. Keep the ESP mounted at `$LFS/boot/efi`
on the host and at `/boot/efi` inside the chroot.

### Stage onto the target and chapter 4

```
./misl sources stage
./misl prep
```

If prep ran before the grant/publish fix:

```
./misl prep publish
```

Do not copy `misl-1.0-systemd` tarballs into `~lfs`. They are already on
`$LFS` after stage.

### Chapter 5 cross toolchain (user `lfs` only)

Chapter 5/6 run as `lfs`. From root after `prep publish`:

```
./misl build-stage 05-cross
./misl status
```

`misl` re-execs as `lfs` without a login shell. `su - lfs -c` hits
the book `exec env -i` profile and drops you at `lfs:~$`.

`gcc-pass1` is the long one on 2C/4G. Logs:

`/mnt/misl/var/lib/misl/logs/`

Add **host** swap on the Fedora disk if gcc OOMs. Do not put swap on
`MISL_DISK`.

### Chapter 6 temporary tools (still user `lfs`)

Book order. `gcc-pass2` is the other long compile.

```
./misl build-stage 06-temp
./misl status
```

Same re-exec as chapter 5. Individual names: `./misl build 06-temp/m4`.

### Chapter 7 chroot temporary tools (root)

Finish 06-temp first (`gcc-pass2` done). Then on the **host**, as root:

```
cd /root/mislinux   # or ~/mislinux if that tree is current
./misl chroot prep
./misl enter
```

Inside the chroot (`LFS=/`, cwd `/usr/src/misl/mislinux`):

```
./misl build gettext
./misl build bison
./misl build perl
./misl build python
./misl build texinfo
./misl build util-linux
./misl status
```

`exit` leaves the chroot. Virtfs stays mounted until reboot or umount.
If Python (ch7) fails missing zlib, build `08-system/zlib` first.

### Chapter 8 system slice (root, inside chroot)

This is only the packages that were stubbed in the 0.2 graph, not the
full LFS chapter 8. `glibc` / `xz` pick the first *unstamped* recipe,
so after ch5/ch6 they resolve to 08-system.

Full LFS 13.1-systemd chapter 8 is in `stages/08-system/` (80 packages,
book order in `packages.manifest`). Inside the chroot:

```
./misl build-stage 08-system
./misl status
```

Or run individual names (`./misl build meson`, `./misl build systemd`).
Stamps skip work that is already done. `gcc` final is the long compile.
Do not set `passwd root` in the shadow recipe; do that in 09-config
(`MISL_ROOT_HASH` from `openssl passwd -6`).

### Chapter 9 config and chapter 10 boot (root, inside chroot)

`enter` bind-mounts the host tree and mounts the ESP at `/boot/efi`.

```
./misl build-stage 09-config
./misl build-stage 10-boot
./misl status
```

`09-config/usr-bin` copies `mislinux/usr/bin/` onto the target `/usr/bin`
(`stardate` and any later overlay scripts).

`09-config` writes hostname, hosts, DHCP networkd, locale, fstab (UUID), os-release,
inputrc, adjtime. 10 builds `vmlinuz-7.1.8-misl` and installs GRUB to
`/boot/efi/EFI/misl/` plus the removable `EFI/BOOT/BOOTX64.EFI` fallback.
inputrc, adjtime. Dump it with `./misl config`. Re-apply with
`./misl config apply`.

`10-boot` builds `vmlinuz-7.1.8-misl` and installs GRUB to
`/boot/efi/EFI/misl/` plus `EFI/BOOT/BOOTX64.EFI`.
Kernel compile is the long step on 2C/4G.

Partitions (do not leave these blank if `misl disk plan` is not in this
shell). EFI, this volume:

```
MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl
MISL_PART_BOOT=/dev/disk/by-id/scsi-0DO_Volume_misl-part1
MISL_PART_ROOT=/dev/disk/by-id/scsi-0DO_Volume_misl-part2
```

Empty `MISL_PART_*` is filled from `MISL_DISK` + `MISL_FIRMWARE` by
`misl_disk_resolve_parts` (`-partN` on by-id devices). BIOS uses
part1=`bios_grub`, part2=`/boot`, part3=root.

`efibootmgr` is **not** in 0.2. `grub-install` uses `--no-nvram` and the
removable path so a chroot/VPS without firmware NVRAM still gets boot
files on the ESP. Add `efibootmgr` later (0.3+) on a real EFI machine
if you want a `Boot####` entry labeled MISL. Until then firmware that
honours `EFI/BOOT/BOOTX64.EFI` is enough.
