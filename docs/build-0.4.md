<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Building MIS Linux 0.4 from scratch

Image names: `misl-<version>[-<tag>]`, tag from the applied leaf
overlay(s) or `MISL_IMG_TAG` (see "Image names" in `operator-0.4.md`).
Three images (A terminal, B DigitalOcean, C ROG Strix X570), each built
on its own tree from the same base steps:

| Path | Image                                              | Overlays applied                         | Selection (before sources fetch) |
|------|----------------------------------------------------|------------------------------------------|----------------------------------|
| A    | `misl-0.4.img`, `.iso`                             | none (`terminal`)                        | base only                        |
| B    | `misl-0.4-cloud-do.img.gz`                         | `cloud`, `cloud/do`                      | `MISL_TARGET_OVERLAYS=cloud/do`  |
| C    | `misl-0.4-desktop-asus-rog-strix-x570.img`, `.iso` | `desktop`, `desktop/asus/rog-strix-x570` | `MISL_GROUPS=all`                |

Build host: Fedora 44 x86_64, as **root**, in `tmux` (08-system and
the kernel run for hours). Run every command from the repo directory:
`img pack` writes `misl-<version>-<tag>.img` there and `iso pack` puts
the `.iso` next to it. The tag is `do` with `cloud/do`, the board leaf
with a desktop board overlay, `img` otherwise.

Paths do not stack: `cloud` is one-way and board and cloud overlays
are not meant to share a tree. Start each path on a fresh tree, or run
`misl reset --all` first (section 3).

## 1. Host prep (once)

```
git clone https://github.com/alkontek/mislinux.git && cd mislinux
git checkout 0.4-dev
./misl doctor install       # dnf: build deps + img/iso tools (grub2, xorriso, squashfs-tools, mtools, cpio, rsync)
./misl doctor               # must end with no FAIL
cp -n config/misl.conf.example config/misl.conf
```

`qemu-system-x86_64` (for `img test` / `iso test`) is optional and not
installed by doctor.

Common environment (put it in `~/.bashrc` or re-export in every shell):

```
export LFS=/mnt/misl
export MISL_DISK=/dev/disk/by-id/<your-volume>
export MISL_MAKEFLAGS=-j2
export MISL_DOCS="python-docs sqlite-docs tcl-docs"    # optional
```

Defaults that stay: `MISL_SNAPSHOT=/var/cache/misl/misl-1.0-systemd`
(all downloads), `MISL_FIRMWARE=efi`, `MISL_FSTYPE=ext4`,
`MISL_DRY_RUN=1`. Optional: `MISL_HOSTNAME`, `MISL_TIMEZONE`,
`MISL_ROOT_HASH` (`openssl passwd -6`).

`./misl env` prints every setting as misl sees it, with its source
(`env`, `misl.conf`, `default` or `unset`); the environment wins over
`misl.conf`. `./misl env export` prints the set ones as `export` lines.

## 2. The volume

**Destructive.** `MISL_DISK` is never defaulted. Check it is not the
host root disk; `./misl disk plan` warns if it is. `disk apply` stops
after its checks and plan (Policy A): partition and mount by hand with
the commands `disk plan` prints.

Fresh volume (EFI layout):

```
D=$MISL_DISK
./misl disk plan
parted -s $D mklabel gpt
parted -s $D mkpart ESP fat32 1MiB 1025MiB
parted -s $D set 1 esp on
parted -s $D mkpart root ext4 1025MiB 100%
udevadm settle
mkfs.vfat -F32 $D-part1
mkfs.ext4 -L misl $D-part2
mkdir -p $LFS && mount $D-part2 $LFS
mkdir -p $LFS/boot/efi && mount $D-part1 $LFS/boot/efi
```

Existing volume: mount `-part2` on `$LFS` and `-part1` on
`$LFS/boot/efi`. After a host reboot: re-export, re-mount;
`./misl enter` re-does the chroot mounts.

## 3. Start over: `misl reset --all` (optional)

Wipes the tree and every build intermediate, keeps the downloads, so a
path can run from scratch without fetching again:

```
./misl reset --all --dry-run       # lists what it unmounts and deletes, with sizes
./misl reset --all                 # type yes (or MISL_FORCE=1)
```

| Deletes                                                     | Keeps                                              |
|-------------------------------------------------------------|----------------------------------------------------|
| everything inside `$LFS` (tools, usr, etc, var, …)          | `$MISL_SNAPSHOT`: sources, patches, docs, incoming |
| build state: stamps, logs, pkglog, overlay reset snapshot   | the repo and `config/misl.conf`                    |
| staged sources and build dirs in `$LFS/usr/src/misl`        | the `lfs` user                                     |
| contents of the boot partition (`$LFS/boot/efi` or `/boot`) | `$LFS` and boot mounts, filesystems, partitions    |
| non-image leftovers in `/var/tmp/misl-*`                    | every built image (`*.img`, `*.img.gz`, `*.iso`)   |
| with `--lfs-home`: `~lfs/mislinux`, `~lfs/misl-1.0-systemd` | `lost+found`                                       |

It unmounts the chroot DNS bind, the bootstrap bind and the chroot
mounts first, and refuses `LFS` empty or `/`, any other mount under
`$LFS`, a snapshot inside `$LFS`, and a `misl-*` image inside `$LFS`.
It never partitions, formats or unmounts `$LFS`.

## 4. Base build (every path)

Export the path's selection (section 5, 6 or 7) **before**
`sources fetch`: it decides which package sources are fetched and
staged.

```
./misl sources remote          # HEAD check of the mirror, no download
./misl sources fetch           # snapshot + wget-list files for the selection (+ MISL_DOCS)
./misl sources check
./misl sources stage           # hardlink into $LFS/usr/src/misl
./misl groups                  # selection and members
./misl prep publish            # layout + lfs user + copy mislinux into ~lfs
./misl build-stage 05-cross    # runs as lfs
./misl build-stage 06-temp
./misl chroot prep
./misl enter
./misl build-stage 07-chroot-temp
./misl build-stage 08-system
./misl build-stage 09-config   # installs MISL_DOCS at the end
./misl build-stage 10-boot     # linux, grub, linux-firmware
./misl status
logout
```

One recipe: `./misl build 08-system/strace` (in `enter`);
`MISL_FORCE=1` rebuilds a stamped recipe. Logs: `./misl logs [name]`.

## 5. Path A: terminal image

```
./misl reset --all                       # optional, fresh tree
export MISL_GROUPS= MISL_TARGET_OVERLAYS=
# section 4
./misl version                           # MISL_OVERLAYS="terminal"
./misl img pack --from-tree              # -> misl-0.4.img
./misl iso pack --uefi                   # optional -> misl-0.4.iso
./misl img test                          # optional, qemu
```

Artifact: `misl-0.4.img` (and `misl-0.4.iso`).

## 6. Path B: cloud/do image

```
./misl reset --all                       # optional, fresh tree
export MISL_GROUPS= MISL_TARGET_OVERLAYS=cloud/do
# section 4
./misl overlay apply cloud/do            # applies cloud first; one-way
./misl cloud fetch                       # cloud-init + pinned wheels -> incoming/ + SOURCES
./misl enter
MISL_FORCE=1 ./misl build 10-boot/linux  # cloud kernel.list
./misl overlay install cloud             # cloud-init, pip --no-index from incoming/
logout
./misl cloud sanitize                    # machine-id, ssh host keys, cloud-init seed
./misl cloud status
./misl img pack --from-tree --gzip       # -> misl-0.4-cloud-do.img.gz
./misl img test                          # optional, qemu virtio
```

Artifact: `misl-0.4-cloud-do.img.gz`. Upload to DigitalOcean: Custom
Images → Import via URL (the upload picker does not take `.img.gz`),
distribution Other; create a Droplet with an SSH key. Check: serial
console login, `ssh root@…` with the key, `cloud-init status --long`
done, `networkctl` routable, `/etc/os-release` MIS Linux 0.4.

## 7. Path C: desktop/asus/rog-strix-x570 image

```
./misl reset --all                       # optional, fresh tree
export MISL_GROUPS=all MISL_TARGET_OVERLAYS=
# section 4
./misl overlay apply desktop/asus/rog-strix-x570   # applies desktop first
./misl firmware list desktop/asus/rog-strix-x570   # every entry installed
./misl enter
MISL_FORCE=1 ./misl build 10-boot/linux  # board kernel.list; fails if a symbol did not stick
logout
./misl initramfs list | grep -E 'igb|r8169|nvme|ahci'
./misl img pack --from-tree              # -> misl-0.4-desktop-asus-rog-strix-x570.img
./misl iso pack --uefi                   # -> misl-0.4-desktop-asus-rog-strix-x570.iso
./misl iso usb --list
MISL_FORCE=1 ./misl iso usb misl-0.4-desktop-asus-rog-strix-x570.iso /dev/disk/by-id/usb-<Vendor_Model_Serial>-0:0
```

Artifact: `misl-0.4-desktop-asus-rog-strix-x570.img` and
`misl-0.4-desktop-asus-rog-strix-x570.iso` (on the USB stick).
`iso usb` wipes the stick; unplug other USB disks. On the board (UEFI,
Secure Boot off): both wired NICs routable, Wi-Fi with `wpa_supplicant@<wlp>`
(`/usr/share/doc/misl/desktop/README`), `bluetoothctl list`,
`aplay -l`, `sensors`. Details: `docs/hardware/rog-strix-x570.md`.
