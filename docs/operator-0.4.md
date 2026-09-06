<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Operator notes — MIS Linux 0.4

## Scope

- `cloud/aws` and `cloud/gcp` stay `status=stub`; apply refuses them.
- Overlay apply records every file it owns. Undo is exact for
  file-only overlays. Children undo before parents. `cloud` is
  one-way: undo refuses, `misl reset` goes back to the base.
- Kernel extras read overlay stamps + `kernel.list` only (no
  `cloud.wanted`). `MISL_CLOUD=1` is an override for one rebuild.
- `kernel.list` takes `=y`, `=m`, `=n`, `="str"` and numbers; every
  value is checked after the last `olddefconfig` (see `overlays.md`).
  `MISL_KERNEL_LIST_LAX=1` warns instead of failing.
- OpenSSH: PAM, or delete `UsePAM` from the recipe. Stop shipping
  systemd `20-systemd-userdb.conf`. Replace the `useradd` wrapper
  (shadow `!` vs pubkey without PAM).
- Decide `%wheel NOPASSWD` — keep it off `cloud`, or wait for passwords.
- cloud-init Python deps: pinned wheels in mirror `incoming/`
  (`config/incoming.manifest`), installed with `pip --no-index`. No
  PyPI, no chroot DNS.
- `img pack` stays BIOS GPT. qcow2/EFI are optional and not `doctor`.
- No droplet-agent unless it builds from our mirror.
- `misl reset --all` wipes `$LFS` and build state for a clean
  rebuild; downloads and built images stay.

Build from scratch (terminal, cloud/do, ROG): [build-0.4.md](build-0.4.md).

## Optional docs

Mirror `docs/` archives are listed in `config/docs.manifest`, not in
the package graph, and are never built.

- Fetch is off by default. `MISL_DOCS="python-docs tcl-docs"` fetches,
  checks and stages only those; `MISL_FETCH_DOCS=1` fetches all. They
  land in `$MISL_SNAPSHOT/docs` (`MISL_DOCS_DIR`), never `sources/`.
- `sources check` verifies any doc present against `md5sums`; a doc not
  fetched is `OPTIONAL` unless wanted (then `MISSING`).
- `sources stage` hardlinks wanted docs to `$LFS/usr/src/misl/DOCS`.
  `09-config/systemd-config` installs `MISL_DOCS` at its end, inside
  the chroot. A wanted doc that is not staged fails 09-config.
- `misl docs list|install|remove <name>` works on `$LFS`, or on `/`
  when `LFS` is unset (booted system). Install refuses to overwrite
  files it does not own and records them in
  `var/lib/misl/docs/<name>.files` (+ `.dirs`); remove deletes exactly
  those and the dirs it created. `.zip` uses unzip, bsdtar, else
  python3 `zipfile` (the base has python3, not unzip).
- The python recipe no longer unpacks the HTML docs itself; use
  `python-docs`.

## Initramfs (installed system)

10-boot/linux (after `modules_install`) and 10-boot/grub (before writing
`grub.cfg`) run `misl initramfs build`. It writes, for kernel
`7.1.8-misl`:

- `/boot/microcode.img`: uncompressed early cpio with
  `kernel/x86/microcode/AuthenticAMD.bin` (all staged
  `/usr/share/misl/linux-firmware/amd-ucode/microcode_amd*.bin`) and,
  when staged, `GenuineIntel.bin` from `/usr/share/misl/intel-ucode/`.
  intel-ucode is **not on the mirror** (source: releases of
  https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files).
- `/boot/initramfs-7.1.8-misl.img`: gzip newc cpio with a small `/init`,
  bash + util-linux (mount, blkid, switch_root), kmod, e2fsck, the
  module set (see overlays.md, initramfs.list) and their staged firmware.

Built with python3 + gzip (no cpio or dracut needed on host or target).
Ledger: `/var/lib/misl/initramfs/<kver>.files|.modules`. Files misl did
not write are never overwritten (`MISL_FORCE=1` to override).

```
./misl initramfs build [kver]    # $LFS on the host, / in the chroot
./misl initramfs list [kver]     # modules + cpio listings
./misl initramfs remove [kver]   # delete only ledger files
```

`grub.cfg` (10-boot/grub and `img pack`) gets two entries:

```
menuentry "MIS Linux 0.4" {
        linux /boot/vmlinuz-7.1.8-misl root=UUID=... ro rootfstype=ext4
        initrd /boot/microcode.img /boot/initramfs-7.1.8-misl.img
}
menuentry "MIS Linux 0.4 (no initramfs)" {
        linux /boot/vmlinuz-7.1.8-misl root=PARTUUID=... ro rootfstype=ext4
}
```

Microcode is always listed first. `img pack` uses `/microcode.img`
(separate /boot partition) and `root=PARTUUID=` in both entries.
10-boot/grub writes `root=PARTUUID=` and boots through the initramfs
(a bare `root=UUID=` with no initramfs cannot be resolved by the
kernel: "VFS: Unable to mount root fs").

`MISL_INITRAMFS=0` turns it off: no files written, one GRUB entry with
`root=PARTUUID=`, no initrd. Default is on everywhere, cloud included:
the DO image keeps virtio and ext4 built in, so the fallback entry boots
the same image if the initramfs breaks, and one boot path is tested
for VPS and hardware alike.

`/init` reads `root=UUID=|PARTUUID=|LABEL=|/dev/...`, `rootfstype=`,
`rootflags=`, `ro`/`rw` and `init=` (default
`/sbin/init`, i.e. systemd), waits up to `rd.misl.timeout=` (30 s) for the root,
runs `fsck.<type> -p` when `rd.misl.fsck` is set (exit >= 4 = rescue),
then `switch_root`. Any failure prints the reason, the cmdline,
`/proc/partitions` and `blkid`, and opens a rescue shell; exiting the
shell retries.

### Debug a boot (GRUB `e`, edit the `linux` line)

| Add / change                                         | Effect                                             |
|------------------------------------------------------|----------------------------------------------------|
| `rd.misl.shell`                                      | rescue shell in the initramfs before mounting root |
| `rd.misl.debug`                                      | `set -x` trace of `/init`                          |
| `rd.misl.timeout=90`                                 | wait longer for slow USB/NVMe roots                |
| remove `quiet`, add `ignore_loglevel`                | all kernel messages on screen                      |
| `systemd.log_level=debug systemd.log_target=console` | systemd after switch_root                          |
| `systemd.unit=rescue.target` / `emergency.target`    | stop before most units                             |
| `earlyprintk=efi` / `earlyprintk=vga` (UEFI/BIOS)    | output before the console driver                   |
| `nomodeset`                                          | rule out amdgpu/nvidia KMS black screens           |
| pick "(no initramfs)"                                | boot without initramfs (PARTUUID)                  |

The live ISO's `/init` (iso pack) now also probes partitions and USB /
NVMe disks for `LiveOS/squashfs.img` for 20 s and gives a shell on
failure, so `misl iso usb` sticks (tree on partition 1) boot as well
as whole disks (sr0, vda, sda...).

## Firmware (overlays)

10-boot/linux-firmware stages linux-firmware-20261019 at
`/usr/share/misl/linux-firmware`; the kernel never loads from there.
`overlay apply` copies only what each overlay's `firmware.list` names
into `/usr/lib/firmware`; `overlay undo` removes exactly those files
(shared files stay while another applied overlay owns them). See
overlays.md, firmware.list. Order: build through 10-boot, then apply.

```
./misl firmware status          # staged version, files per overlay
./misl firmware list desktop/asus/rog-strix-x570
MISL_FIRMWARE_LAX=1 ./misl overlay apply ...   # missing entries warn
```

## Desktop and the ROG Strix X570 (alpha)

`desktop` (wireless `.network` for `wl*`, `fstrim.timer`, Wi-Fi notes)
and `desktop/asus/rog-strix-x570` (I211/RTL8125/AX200/ALC1220A
drivers, firmware, `Driver=` networkd matches, commented
`modprobe.d`). No GUI stack. See docs/hardware/rog-strix-x570.md.

```
./misl overlay apply desktop/asus/rog-strix-x570   # applies desktop first
MISL_FORCE=1 ./misl build 10-boot/linux            # kernel=1: board kernel.list
./misl overlay undo desktop/asus/rog-strix-x570 desktop
```

Not yet in MISL: wireless-regdb (world regdomain), bluez, alsa-utils,
lm-sensors.

## Package groups

Every manifest row has exactly one group: base (always), hw, wifi,
bluetooth, lisp, cloud. Terminal images build base only; cloud
images add the `cloud` group (incoming files only, no recipes). For the
desktop or ROG tree, set the target **before** `sources stage`:
`MISL_TARGET_OVERLAYS=rog-strix-x570 ./misl sources stage` (records
`bluetooth hw wifi` in `$LFS/var/lib/misl/groups`; `build-stage
08-system` then builds those rows). Lisp: add `MISL_GROUPS=lisp` (needs the incoming SBCL
binary; md5 501733c5aa52abc4bf468e308c3daff4, set
`MISL_SBCL_BOOTSTRAP_MD5` to enforce). `./misl groups` shows the
selection. A row with no group, two groups or an unknown group stops
misl with `file:line`. Details: docs/overlays.md "Package groups".

## Cloud-init from incoming/

Everything misl takes from the mirror's `incoming/` is listed in
`config/incoming.manifest` with its md5: the cloud-init tarball, its
13 Python wheels in `incoming/wheels/` (group `cloud`) and the SBCL bootstrap (group
`lisp`). Nothing comes from PyPI.

```
./misl cloud fetch           # host: cloud rows from incoming/, md5, stage
./misl enter
./misl cloud install         # chroot: pip --no-index on the pinned wheels, meson cloud-init
```

`MISL_TARGET_OVERLAYS=cloud/do ./misl sources stage` stages the same
files. `./misl sources check` reports `MISSING`, `HASH-MISMATCH` or
`NO-HASH` for each selected incoming file. A missing wheel stops
`cloud install` naming the file. The cloud-init tarball md5 is `-` in
the manifest until it is filled in; set `MISL_CLOUD_INIT_MD5` to check
it meanwhile. Details: docs/overlays.md "Incoming files".

## Image names

`img pack` and `iso pack` write `misl-<version>[-<tag>].img` /
`.iso` in the current directory (`--gzip` adds `.img.gz` next to the
`.img`; `iso pack` takes the `.img` name and ends it in `.iso`).

| Tree                                     | Tag                           | Image                                      |
|------------------------------------------|-------------------------------|--------------------------------------------|
| base (`terminal` only)                   | none                          | `misl-0.4.img`                             |
| `terminal/tui`                           | `terminal-tui`                | `misl-0.4-terminal-tui.img`                |
| `cloud`, `cloud/do`                      | `cloud-do`                    | `misl-0.4-cloud-do.img`                    |
| `desktop`, `desktop/asus/rog-strix-x570` | `desktop-asus-rog-strix-x570` | `misl-0.4-desktop-asus-rog-strix-x570.img` |
| `MISL_IMG_TAG=test1`                     | `test1`                       | `misl-0.4-test1.img`                       |

The tag is every applied leaf overlay (applied, with no applied child
below it), `/` replaced by `-`, sorted and joined with `-`; `terminal`
alone adds nothing. `MISL_IMG_TAG` (env or `misl.conf`) empty = auto,
non-empty = that tag (letters, digits, `.` `_` `+` `-`). `-o FILE`,
`MISL_IMG` and `MISL_ISO` beat both.

## Reset an overlay tree

`cloud` edits `/etc` in place and cannot be undone; apply prints what
it changes. To get the base tree back:

```
./misl reset --info          # snapshot date, size, what it restores
./misl reset                 # type yes (or MISL_FORCE=1 ./misl reset)
MISL_FORCE=1 ./misl build 10-boot/linux   # only if kernel extras must go
```

The snapshot is taken on the first overlay apply on a base tree and
kept. Reset removes overlay files and firmware and restores `/etc`,
`/root` and the overlay state; packages and the built kernel stay. No
snapshot (overlays applied before misl had reset): rebuild. Details:
docs/overlays.md "Reset".

## Clean rebuild

```
./misl reset --all --dry-run      # what it unmounts and deletes, with sizes
./misl reset --all                # type yes (or MISL_FORCE=1)
./misl reset --all --lfs-home     # also ~lfs/mislinux and ~lfs/misl-1.0-systemd
```

Deletes everything inside `$LFS` (tools, stamps, logs, staged sources,
build dirs, the overlay reset snapshot) and the boot partition files.
Keeps `$MISL_SNAPSHOT` (downloads, `incoming/`), the repo,
`config/misl.conf`, the `lfs` user, the `$LFS` and boot mounts, the
partitions, and every built image (`*.img`, `*.img.gz`, `*.iso`).
Refuses `LFS` empty or `/` and unexpected mounts under `$LFS`. Then:
`./misl prep`, `./misl sources stage`, build. Details:
[build-0.4.md](build-0.4.md) section 3.

## Not in 0.4

- `disk apply` growing teeth. Policy A stays.
- `misl strip` / debuginfo (SRPM factory).
- Implementing `terminal/tui`. Stubs are the feature until a provider path exists.

## Done when

An operator on the Fedora 44 host can:

1. `./misl overlay apply cloud do` — idempotent if stamps exist unless
   `MISL_FORCE=1`.
2. Rebuild linux from overlay stamps only (`MISL_FORCE=1 ./misl build
   10-boot/linux`). No `cloud.wanted`.
3. Install cloud-init without hitting PyPI: `./misl cloud fetch` on
   the host, `./misl cloud install` in the chroot (pinned `incoming/`
   wheels, `pip --no-index`).
4. `./misl img pack` a BIOS GPT image; `./misl img test` reaches a
   serial getty on virtio.
5. `./misl reset` and get the base tree back. Owned files gone,
   `/etc` as before the first apply, stamps gone, `MISL_OVERLAYS` is
   `terminal`. `overlay undo cloud` refuses.

Until those six hold, stay on 0.3.
