<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Cloud-init on MIS Linux 0.3 for DigitalOcean

The product is **MIS Linux 0.3** (systemd). Userspace recipes still follow
the LFS 13.1-systemd freeze; this page is not an LFS add-on.

DigitalOcean Custom Images need **cloud-init ≥ 0.7.7**, **sshd on boot**,
**BIOS boot**, **ext3/ext4**, and **ConfigDrive before NoCloud**.

Two images from one volume tree:

| Image                   | Overlay                 | Pack when                                                      |
|-------------------------|-------------------------|----------------------------------------------------------------|
| `misl-0.3-terminal.img` | `terminal` only         | after chapters 5–10, **before** `overlay apply`                |
| `misl-0.3-do.img`       | `terminal` + `cloud/do` | after apply, kernel rebuild, `overlay install cloud`, sanitize |

Same Fedora 44 host walk as [`test-0.3-do-vps.md`](test-0.3-do-vps.md).
Design: [`overlays.md`](overlays.md).

## Walk (clone, terminal, cloud, both images)

```
dnf install -y nano tmux htop git
git clone https://github.com/alkontek/mislinux.git
cd mislinux
export LFS=/mnt/misl
export MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl
export MISL_MAKEFLAGS=-j$(nproc)
cp -n config/misl.conf.example config/misl.conf  # edit for more configruation
./misl env
./misl doctor install
./misl sources fetch
./misl sources check
```

Format the **attached** volume only (`disk apply` does not write):

```
./misl disk plan
parted -s "$MISL_DISK" mklabel gpt
parted -s "$MISL_DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$MISL_DISK" set 1 esp on
parted -s "$MISL_DISK" mkpart root ext4 1025MiB 100%
udevadm settle
mkfs.vfat -F32 "${MISL_DISK}-part1"
mkfs.ext4 -L misl "${MISL_DISK}-part2"
mkdir -p $LFS && mount "${MISL_DISK}-part2" $LFS
mkdir -p $LFS/boot/efi && mount "${MISL_DISK}-part1" $LFS/boot/efi
```

**Run stages 05-10 to generate the default (terminal) tree:**

```
./misl sources stage
./misl prep publish
./misl build-stage 05-cross
./misl build-stage 06-temp
./misl chroot prep
./misl enter
./misl build-stage 07-chroot-temp
./misl build-stage 08-system
./misl build-stage 09-config
./misl build-stage 10-boot
./misl version          # MISL_OVERLAYS="terminal"
logout
```

**Apply the `cloud` and `do` overlays (no host, not in the chroot):**  
```
test -f "$LFS/boot/vmlinuz-7.1.8-misl"
./misl overlay list     # terminal=default; cloud / cloud/do = off
./misl overlay apply cloud do
./misl cloud wheels
./misl enter            # wheels don't work add --net for network
MISL_FORCE=1 ./misl build 10-boot/linux
./misl overlay install cloud
logout
#./misl net off         # if --net was enabled
./misl cloud sanitize
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-cloud-do-terminal.img
```

`./misl cloud apply` is `overlay apply cloud do`. cloud-init is **not**
on `packages.manifest` (`$MISL_MIRROR/incoming/cloud-init-26.2.tar.gz`).
`apply` with no `$LFS` or no 10-boot stamps an empty tree. Never
`wget-list.original`. Volume stays EFI; both `.img` files are BIOS GPT.

---

## 0. Image must already satisfy DO hardware rules

Before cloud-init:

- Partition table **GPT**, bootloader **GRUB BIOS** (`i386-pc`).
  **UEFI is rejected.** That is `img pack --from-tree`, not the EFI
  build volume.
- Root filesystem **ext4**.
- Kernel has **virtio-blk, virtio-net, virtio-pci, ext4, iso9660, vfat,
  serial console** built in (`overlays/cloud/kernel.list` after apply,
  then `MISL_FORCE=1 ./misl build 10-boot/linux`). There is no initramfs.
- Serial on the kernel command line, e.g. `console=ttyS0,115200n8 console=tty0`.
- `sshd` enabled.
- No static IP in `/etc/systemd/network/*.network` that will fight DHCP.

---

## 1. Python runtime deps

0.3 already has Python 3, setuptools, meson, and ninja in 08-system.
`overlay install cloud` uses `pip3 --prefix /usr --no-index
--find-links` for the modules cloud-init still needs:

```
PyYAML
requests
configobj
jsonpatch
jsonschema
oauthlib
```

On the Fedora host (needs DNS, `MISL_FETCH=1`):

```
./misl cloud wheels
```

That `pip download`s binary wheels into `$MISL_SNAPSHOT/incoming/`
(same directory as `cloud-init-26.2.tar.gz`) and stages them into
`$LFS/usr/src/misl/SOURCES`. They do not have to live on the mirror.
jsonschema is **&lt; 4.18** so it does not need `rpds-py` (Rust). Do
**not** `pip install` cloud-init from PyPI. `misl net` is not required
for `cloud install`.

Also, already in the base tree:

- `iproute2` + systemd-networkd
- `e2fsprogs` (`resize2fs`)
- `util-linux` (`sfdisk`) so growpart can expand the partition

---

## 2. Build and install cloud-init from incoming/

Same apply block as above. `overlay install cloud` meson-installs
under `/usr`, not `/usr/local`. Inside the chroot:

```
cloud-init --version  # expect 26.2
```

Units land under `/usr/lib/systemd/system/`
(`cloud-init-local.service`, `cloud-init.service` or
`cloud-init-main.service` / `cloud-init-network.service`,
`cloud-config.service`, `cloud-final.service`) plus a generator.
The overlay enables the stack; do not hand-edit unit links on the host
tree unless you are debugging.

---

## 3. Configure for DigitalOcean

DO apply metadata via **ConfigDrive**. If **NoCloud is listed first**,
the Droplet comes up with a broken network and no SSH key.

`overlay apply do` writes `/etc/cloud/cloud.cfg.d/99-digitalocean.cfg`.
The important line:

```yaml
datasource_list: [ ConfigDrive, DigitalOcean, None, NoCloud ]
```

The generic cloud drop-in (`90-misl-cloud.cfg`) keeps only modules that
work without a package manager (growpart, ssh, hostname, users_groups,
…`). `system_info.distro` is the generic Linux class; package modules
are unused.

0.3 is **root only**. There is no `misl` or `lfs` login user on the
guest. Attach an SSH key when creating the Droplet. Cloud-init writes
that key to root.

---

## 4. Networking

systemd-networkd only. Overlay apply writes
`/etc/systemd/network/20-dhcp.network` as a fallback (cloud-init
rewrites it on first boot from ConfigDrive):

```ini
[Match]
Name=en* eth*

[Network]
DHCP=yes
```

Do **not** enable a second DHCP client that fights networkd.
`misl net` is a host bind of resolv.conf for the chroot session. It is
not written into the image; `net off` before pack.

---

## 5. SSH

Overlay apply writes sshd drop-in: password auth off, pubkey on,
root keys allowed. Password reset from the DigitalOcean panel does not
work on custom images. You **must** attach an SSH key.

```
systemctl enable sshd
```

is already done by the overlay when the unit exists.

---

## 6. Disk grow on first boot

Droplet disk is often larger than the uploaded image. Keep `growpart`
and `resizefs` enabled. `img pack` writes root as **PARTUUID**.
`resize2fs` works on ext4.

---

## 7. Sanitize before you image

```
./misl cloud sanitize
```

That drops machine-id, ssh host keys, and the cloud-init seed so the
first Droplet boot is a new instance. Then pack. Do not boot the packed
tree again except as a Droplet or `img test`.

---

## 8. Export and upload

```
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-do.img
```

`--from-tree` is the DO path (GPT + `bios_grub` + ext4). `--from-disk`
of the EFI build volume is the wrong firmware.

Accepted: raw `.img` (MBR/GPT), qcow2, VHDX, VDI, VMDK; gzip/bzip2 OK
on **Import via URL** (URL must end in `.img.gz`). The control-panel
file picker only lists uncompressed `.img` / `.qcow2` / … and rejects
`.img.gz`. ISO is **not** accepted. ≤ 100 GB uncompressed.

Optional, not a `doctor` dependency: `qemu-img convert -O qcow2 -c`
if `qemu-img` is already on the host.

Create a Droplet from that image → **attach an SSH key**. Recovery
console is serial (`serial-getty@ttyS0`).

---

## 9. First-boot check

```
cloud-init status --wait
cat /run/cloud-init/status.json
cloud-init query ds
# expect ConfigDrive (or DigitalOcean on older cloud-init)
ss -lntp | grep sshd
```

If networking is dead: datasource order is wrong, or NoCloud leftover
seed files exist under `/var/lib/cloud`. Fix, `misl cloud sanitize` on
the build tree, pack again.

---

### What you can ignore on MISL 0.3

Package modules (`package_update`, `packages`, apt/yum/dnf) will not
work. User-data `runcmd` / `write_files` / SSH keys / hostname /
growpart **will**. That is enough for DigitalOcean.
