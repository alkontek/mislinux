<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Operator notes — MIS Linux 0.3

Bootstrap is **0.3**. Freeze and disk path stay the 0.2 notes
([`operator-0.2.md`](operator-0.2.md)). This page is the mid-build source add,
overlays, and the DigitalOcean image path.

- Mid-build `sources integrate` on the host (`--reintegrate` to change a version)
- OpenSSH 10.5p1 and nano 9.2 in 08-system
- Overlays: `terminal` is the base; `cloud/` is opt-in
- BIOS GPT image: cloud-init from `incoming/`, `img pack`, `img test`
- Live ISO/USB for UEFI and BIOS: `iso pack`, `iso test`, `iso inspect`, `iso usb`
- Kernel 7.1.8-misl: SquashFS + overlay + iso9660 built-in; virtio/8250 via the cloud overlay
- Session-only chroot DNS (`misl net`). `enter` remounts a stale chroot-prep bind

## Overlays

The base install has no hypervisor extras. `overlays/` adds named stacks.
`cloud` is virtio/serial + cloud-init. `do` is DigitalOcean on top of
`cloud`. See [`overlays.md`](overlays.md).

```
./misl overlay list
./misl overlay apply cloud do
./misl overlay undo do cloud
```

Undo children first. Apply records owned paths in
`$LFS/var/lib/misl/overlays/<name>/owned`. Undo deletes those files,
then the stamp. A second undo of the same name is a no-op.

## DigitalOcean Custom Image

cloud-init is **not** on `packages.manifest`. The tarball is
`$MISL_MIRROR/incoming/cloud-init-26.2.tar.gz`. DO needs BIOS, ext4,
cloud-init, and sshd. See
[`cloud-init-on-misl-0.3-for-do.md`](cloud-init-on-misl-0.3-for-do.md).
Full Fedora 44 VPS walk (clone → `terminal` → `cloud/do` → `.img.gz`):
[`test-0.3-do-vps.md`](test-0.3-do-vps.md).

```
# host, LFS mounted
./misl cloud wheels             # pip download into incoming/; needs host DNS
./misl cloud apply
./misl enter
./misl cloud install
logout
./misl cloud sanitize
./misl img pack                 # BIOS GPT .img from the $LFS tree
# or: ./misl img pack --from-disk -o /var/tmp/misl.img
# or: ./misl img pack --gzip
```

`cloud apply` lists every file it wrote in `$LFS/var/lib/misl/cloud.report`.
`cloud apply` is safe to run again. `cloud undo` removes only the files
apply owns. Attach an SSH key when creating the Droplet. Agent sessions
keep `MISL_FETCH=0` and must not fetch incoming/.

### Chroot DNS (`misl net`)

The chroot already uses the host network namespace. Name lookup still
fails because `$LFS/etc/resolv.conf` often points at systemd-resolved
under the chroot `/run` tmpfs (empty). That is not a permanent network
setup.

| Command              | Where          | Effect                                                    |
|----------------------|----------------|-----------------------------------------------------------|
| `./misl net on`      | Fedora host    | bind-mount host `resolv.conf` over `$LFS/etc/resolv.conf` |
| `./misl net off`     | Fedora host    | unmount that bind; image is unchanged                     |
| `./misl net status`  | host or chroot | whether the bind is up                                    |
| `./misl enter --net` | Fedora host    | `net on` then enter                                       |

`./misl cloud wheels` (host, `MISL_FETCH=1`) runs `pip download
--only-binary :all:` into `$MISL_SNAPSHOT/incoming/` and stages the
`*.whl` files into `$LFS/usr/src/misl/SOURCES`. The mirror does not
need those wheels. `cloud install` then uses `--no-index`. jsonschema
is pinned `<4.18` so it does not need rpds-py. Agent sessions keep
`MISL_FETCH=0` and must not run `cloud wheels`. Leave `misl net` off
for a normal build.

### Image file vs payload

`img pack` does not delete `/tools` or `/usr/src` on the live tree. It
omits them from the rsync. The `.img` is still a full virtual disk
(`truncate -s N G`); `ls -lh` shows that allocated size, not how much
was copied. `du -h file.img` is the sparse on-disk weight.

`--gzip` writes `file.img.gz` next to the raw image. DigitalOcean
**accepts** gzip/bzip2 on URL/API import. The control-panel file picker
only lists `.img`, `.qcow2`, `.vhdx`, `.vdi`, `.vmdk`, so a `.img.gz`
is rejected there even though the backend would take it.

Upload options:

- raw `misl-0.3-do.img` in the picker (large; browsers often fail over a few GiB)
- put `misl-0.3-do.img.gz` on Spaces / HTTPS and **Import via URL** (URL must end in `.img.gz`)
- optional, **not** a MISL host dependency: if `qemu-img` is already on
  the machine, `qemu-img convert -O qcow2 -c misl-0.3-do.img misl-0.3-do.qcow2`
  gives a picker-friendly smaller file. Do not add qemu to `misl doctor`.

### Host qemu smoke test

The Droplet and the recovery console are KVM + serial. If that screen
is blank, the kernel probably never mounted root. There is no initramfs;
virtio must be built into `vmlinuz-7.1.8-misl`. `defconfig` leaves virtio
as modules, so a current image can hang on virtio and still boot on IDE.

If `qemu-system-x86_64` is already on the Fedora host:

```
./misl img test                  # virtio, same as DigitalOcean. Ctrl-a x quits
./misl img test --ide            # ATA, often works on a defconfig kernel
```

- virtio hangs / “waiting for root”, IDE prints a login: rebuild linux
  (`MISL_FORCE=1 ./misl build 10-boot/linux` then pack again). 0.3 now
  sets virtio + 8250 serial built-in.
- live USB/ISO needs `CONFIG_SQUASHFS=y` (plus overlay + iso9660).
  `10-boot/linux` enables that after defconfig. Cloud virtio/8250 comes
  from `overlays/cloud/kernel.list` when the cloud overlay is applied.
  After rebuild: `grep ^CONFIG_SQUASHFS /mnt/misl/boot/config-7.1.8-misl`
- `misl enter` bind-mounts this checkout over `$LFS/usr/src/misl/mislinux`.
  `chroot prep` only rsyncs a snapshot. If those inodes differ, the
  chroot builds stale recipes. `enter` remounts when they differ.
- both hang at GRUB: `grub-install --target=i386-pc` failed during pack.
- kernel runs but no prompt: need `serial-getty@ttyS0` (cloud apply now
  enables it). SSH still needs the key DigitalOcean injects via cloud-init;
  password SSH is off.

## Integrate a package added to the mirror

`misl sources fetch` keeps existing tarballs. It now refreshes
`wget-list` + `md5sums` first, so a later `fetch` will pull files that
showed up on `https://makeitsolinux.org/downloads/misl-1.0-systemd`
after the first snapshot.

An in-progress build that already staged sources needs the named path:

1. Add **one** row to `config/packages.manifest` (08-system / 09-config /
   10-boot). Two `openssh` rows are refused.
2. Add `stages/<stage>/<name>.sh`.
3. Upload the tarball so the remote `wget-list` and `md5sums` list it.
4. On the **Fedora host** (not inside `(misl chroot)`; wget is a host tool):

```
./misl sources integrate openssh
./misl enter
./misl build 08-system/openssh
```

Integrate only:

- replaces snapshot `wget-list` + `md5sums` from `$MISL_MIRROR`
- fetches only `openssh-10.5p1.tar.gz` (and any patches on the row)
- hardlinks it into `$LFS/usr/src/misl/SOURCES`
- writes `$LFS/var/lib/misl/integrated/openssh`
- prints the enter + build lines; it does not compile

A second integrate of the same name dies. Changing the version (new
tarball on the row and on the mirror):

```
./misl sources integrate --reintegrate openssh
./misl enter
MISL_FORCE=1 ./misl build 08-system/openssh
```

`--force` and `-R` are the same flag on integrate. There is never a
second integrated `openssh`; the record file is replaced.

`./misl integrate` is an alias. `./misl sources refresh` only updates
the catalog.
