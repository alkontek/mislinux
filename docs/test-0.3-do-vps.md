<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Test 0.3 on a Fedora 44 DigitalOcean VPS

End-to-end on a bare Fedora 44 Droplet: clone → `terminal` base on the
attached volume → `cloud/do` overlay → compressed BIOS Custom Image.

The VPS is the **build host**. The `.img` is what DigitalOcean boots.
Volume firmware stays **efi**. `img pack --from-tree` is **BIOS GPT**.
Do not `dd` the EFI volume for a Custom Image.

- Disk and freeze: [`operator-0.2.md`](operator-0.2.md)
- Image and overlay notes: [`operator-0.3.md`](operator-0.3.md)
- Overlay design: [`overlays.md`](overlays.md)
- [`cloud-init-on-misl-0.3-for-do.md`](cloud-init-on-misl-0.3-for-do.md)

## Droplet

- Fedora 44 x86_64. 2 vCPU / 4 GiB is enough with `-j2`.
- Attach the 50 GiB volume `misl` (`scsi-0DO_Volume_misl`).
- SSH in as root. Do **not** put swap on `MISL_DISK`. Host swap on the
  Fedora disk is OK if gcc OOMs.

### Two images from one volume tree:

| Image                   | Overlay                     | Pack when                                                      |
|-------------------------|-----------------------------|----------------------------------------------------------------|
| `misl-0.3-terminal.img` | `terminal` only             | after chapters 5–10, **before** `overlay apply`                |
| `misl-0.3-do.img`       | `terminal` + `cloud` + `do` | after apply, kernel rebuild, `overlay install cloud`, sanitize |

_Images in this doc are packed with `--from-tree` that fits the distribution_
_and cloud scenarios. You can also pack `--from-disk` that would result the raw_
_image being the size of the disk, for example for machine backups._

---

## 1. Clone and config

```
dnf install -y nano tmux htop git
git clone https://github.com/alkontek/mislinux.git && cd mislinux
git checkout master
git log -1 --oneline
./misl version

cp -n config/misl.conf.example config/misl.conf
```

Environment wins over that file. In this shell, before any other `misl`
command:

```
export LFS=/mnt/misl
export MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl
export MISL_MAKEFLAGS=-j2
./misl env
./misl disk plan
```

`LFS` must be `/mnt/misl`. Do not export `MISL_SNAPSHOT` or `MISL_FETCH`
unless you are changing the defaults. Optional: set `MISL_ROOT_HASH` from
`openssl passwd -6` (local console only) in the config file.

***The Digital Ocean image uses injected SSH keys; password SSH is off.***

## 2. Host toolchain and catalog

```
./misl doctor install
./misl doctor
./misl sources remote
./misl sources fetch
./misl sources check
./misl overlay list
```

## 3. Partition, format, mount (destroys `MISL_DISK`)

`disk apply` is policy A: it prints the plan and stops. Format the
**attached** volume yourself. That is not the Fedora root disk.

```
ls -l /dev/disk/by-id/scsi-0DO_Volume_misl
./misl disk plan
```

If `MISL_DISK` is missing or is the disk behind `/`, stop.

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
findmnt /mnt/misl /mnt/misl/boot/efi
```

`$LFS` is `/mnt/misl`. Keep both mounts for the rest of the walk.

## 4. Stage sources and create `lfs` user

```
./misl sources stage
./misl prep publish
```

## 5. `terminal` (stages 05-10, default layout)

Cross and temp tools run as user `lfs`, as **root**, after `prep publish`:

```
./misl build-stage 05-cross
./misl build-stage 06-temp
./misl status
```

`misl` re-execs those two stages as `lfs` without a login shell.
Do **not** use `su - lfs -c '…'`. The book `~lfs/.bash_profile`
does `exec env -i … bash`, which drops `-c` and leaves you at
`lfs:~$` (`bash: no job control in this shell`). Interactive
`su - lfs` is still fine if you type the builds at that prompt.

Chroot from here, as root on the Fedora host:

```
cd /root/mislinux
./misl chroot prep
./misl enter
./misl build-stage 07-chroot-temp
./misl build-stage 08-system
export MISL_ROOT_HASH=$(openssl passwd -6) # sets the root password hash for 09
./misl build-stage 09-config
./misl build-stage 10-boot
./misl status
./misl version
logout
```

`./misl version` should print `MISL_OVERLAYS="terminal"`. If this tree
is already built through 10-boot, skip to the image you want. Use
`~/mislinux` if that copy is the current tree (`prep publish`).

## 5b. Pack a `terminal` image (optional)

Host root, **before** `overlay apply`. Same BIOS GPT pack as DO; no
cloud-init, no virtio rebuild.

```
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-terminal.img
```

Keep this file if you want a console-only Custom Image. Applying
`cloud/do` next changes the tree on `$LFS`; pack terminal first.

## 6. Overlay `cloud/do`

On the Fedora host, `LFS=/mnt/misl` mounted, **not** inside the chroot:

```
./misl overlay apply cloud do
./misl overlay status
./misl version
```

`./misl cloud apply` is the same as `overlay apply cloud do`.
`./misl version` should print `MISL_OVERLAYS="cloud cloud/do terminal"`.

Rebuild linux so virtio + 8250 are built-in, then install cloud-init
(needs DNS once):

```
./misl enter --net
MISL_FORCE=1 ./misl build 10-boot/linux
./misl overlay install cloud
logout
./misl net off
./misl cloud sanitize
./misl cloud status
```

Leave `misl net` off for a normal build. `sanitize` drops machine-id,
ssh host keys, and the cloud-init seed so the Droplet gets a clean
first boot.

## 7. Pack a compressed `cloud/do` image

Host root. Do **not** use `--from-disk` on this EFI volume.

```
cd /root/mislinux
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-do.img
ls -lh /var/tmp/misl-0.3-terminal.img.gz /var/tmp/misl-0.3-do.img.gz
```

Optional if `qemu-system-x86_64` is already installed (not a `doctor`
dependency):

```
./misl img test
```

Ctrl-a x quits. Virtio hang + IDE login means the kernel rebuild in
step 6 did not take. GRUB hang means `grub-install --target=i386-pc`
failed during pack.

## 8. Import on DigitalOcean

The control-panel picker rejects `.img.gz`, instead do:  
**Backups & Snapshots** > **Custom Images** > **Upload an Image** > **Import via URL**  
and enter with a URL that ends with `.img.gz`


When creating the Droplet from that image:

- Pick a region the image landed in
- **Attach an SSH key** (password SSH is off)
- Recovery console is serial; `serial-getty@ttyS0` is enabled by the overlay

## Checks

```
./misl version
./misl overlay list
./misl overlay status
test -f /mnt/misl/boot/vmlinuz-7.1.8-misl
test -f /var/tmp/misl-0.3-do.img.gz
# optional:
test -f /var/tmp/misl-0.3-terminal.img.gz
```

`overlay list` should show `terminal` as `default` and `cloud` / `cloud/do`
as `on` after step 6.
