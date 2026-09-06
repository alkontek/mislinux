<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Overlays

One source graph. Machine-kind is an overlay, except **terminal**: that
*is* the base install (console, shell, chapter 8). Cloud is opt-in.

## Nested model

Overlays nest by folder. Any directory under `overlays/` that holds an
`overlay.conf` is an overlay; its **qualified name** (qname) is its path
relative to `overlays/`:

```
overlays/
  terminal/                    terminal        (default, the base)
    tui/                       terminal/tui
  desktop/                     desktop
    asus/                      grouping dir (no overlay.conf)
      rog-strix-x570/          desktop/asus/rog-strix-x570
  cloud/                       cloud
    do/                        cloud/do
    aws/                       cloud/aws
    gcp/                       cloud/gcp
```

Rules:

- **Parent = nearest ancestor overlay.** A directory without
  `overlay.conf` is a pure grouping dir (vendor, family). It is never
  listed, applied or stamped. `desktop/asus/rog-strix-x570`'s parent is
  `desktop`. Grouping dirs keep vendor trees tidy without stub overlays
  for every vendor.
- **`parent=` is optional.** When set it must name the folder-implied
  parent (qname or its leaf); a mismatch is an error. `name=`, when set,
  must equal the folder name.
- **Names on the command line** are qnames. A leaf (`do`) is accepted
  when exactly one overlay has it; an ambiguous leaf is an error that
  lists the candidates.
- **Apply** pulls missing ancestors first (root first), then
  `requires=`, then the overlay. An ancestor that is `stub` refuses the
  apply and names it. Already-applied overlays are skipped. `terminal`
  (`default=1`) is the base and never stamped.
- **Undo** refuses an overlay while any of its children (any depth) or
  any overlay that `requires=` it is applied. Undo children first.
  `undo terminal` is refused. A one-way overlay (`cloud` and its
  children) is never undone; use `misl reset` (see Reset).

## Listing

`overlay list` prints a header and qnames, ordered by `priority`.
Status and class come from each `overlay.conf`.

```
NAME                         STATUS  ON       CLASS  TITLE
terminal                     alpha   default  local  Text console and shell and terminal apps
terminal/tui                 stub    off      local  Text console and terminal user interface
desktop                      alpha   off      local  Local physical machine (console, wired+wireless networkd)
desktop/asus/rog-strix-x570  alpha   off      local  ASUS ROG Strix X570 (I211, RTL8125, AX200, ALC1220A)
cloud                        alpha   off      cloud  Cloud guest (virtio, serial, cloud-init) [one-way]
cloud/do                     alpha   off      cloud  DigitalOcean Custom Image [one-way]
cloud/aws                    stub    off      cloud  Amazon EC2 [one-way]
cloud/gcp                    stub    off      cloud  Google Compute Engine [one-way]
```

`ON=default` means default, not stamped. `apply cloud` does not turn
terminal off.

```
./misl overlay list
./misl overlay apply cloud/do        # pulls cloud first
./misl overlay undo desktop          # file-only overlays undo exactly
./misl reset                         # one-way cloud: back to the base
```

`./misl cloud apply` is `overlay apply cloud/do`. `./misl cloud undo`
refuses, like `overlay undo cloud`. One-way overlays carry
`[one-way]` after the title in `overlay list`.

`./misl overlay status` (needs `LFS`) lists the applied overlays with
their stamp (one-way ones say so), the firmware summary, and whether a
reset snapshot exists.

## overlay.conf

`key=value` lines, `#` comments; quotes around a value are stripped.
Unknown keys are ignored.

| key        | meaning                                                                            |
|------------|------------------------------------------------------------------------------------|
| `name`     | optional; must equal the folder name                                               |
| `title`    | one line for `overlay list`                                                        |
| `class`    | `local` or `cloud` (shown in `overlay list`)                                       |
| `parent`   | optional; must match the folder-implied parent (qname or leaf)                     |
| `requires` | space-separated overlays applied before this one (besides ancestors)               |
| `priority` | `overlay list` order (default 100)                                                 |
| `status`   | `stub`, `alpha`, `beta`, `rc`, `stable`; only stub refuses apply                   |
| `kernel`   | `1`: 10-boot/linux applies the `kernel.list` files of applied overlays (see below) |
| `default`  | `1`: the base (`terminal`); never stamped or undone                                |
| `packages` | package groups this overlay needs, comma list (see Package groups)                 |
| `oneway`   | `1`: edits files in place; undo refuses (also for children), use `misl reset`      |

## Files

```
overlays/<qname>/overlay.conf     required (see above)
overlays/<qname>/kernel.list      optional; kernel options
overlays/<qname>/initramfs.list   optional; initramfs modules
overlays/<qname>/firmware.list    optional; files from linux-firmware
overlays/<qname>/apply.sh         optional; sourced on the host, LFS set
overlays/<qname>/undo.sh          optional; sourced on undo (not for one-way)
overlays/<qname>/files/           optional; installed by apply.sh
                                  calling misl_overlay_install_files
```

Shipped today: `desktop` and `desktop/asus/rog-strix-x570` have
apply.sh/undo.sh; `cloud` and `cloud/do` have apply.sh only (one-way,
`oneway=1` on `cloud`); `cloud` and the
ROG board have `kernel.list` (both `kernel=1`); the ROG board has
`firmware.list` (docs/hardware/rog-strix-x570.md); `desktop` and the
ROG board have `files/`. No overlay ships `initramfs.list` yet. stub
overlays are conf-only.

**Apply** of one overlay: firmware.list first (all checked before
anything is written), then `apply.sh` with `MISL_OVERLAY_APPLYING` set,
then the stamp. An overlay already stamped is skipped.

**Undo** of one overlay: the paths in its `owned` ledger are removed
(files and symlinks, then the directories it created if empty, deepest
first), then its firmware, then `undo.sh`, then the stamp. undo.sh only
needs to handle what apply.sh did *not* record.

`misl_overlay_install_files` (from `apply.sh`) copies `files/` into
`$LFS`, recording every file and newly created directory (trailing `/`)
in `owned`. It checks first and refuses to overwrite a path the overlay
does not own unless `MISL_FORCE=1`. `misl_overlay_own <path>` records
anything else apply.sh creates.

The repo holds **no symlinks**, `files/` included
(`git ls-files -s | awk '$1==120000'` must be empty). A link the target
needs (e.g. a `*.wants/` unit link) is made by `apply.sh` and recorded
with `misl_overlay_own`, so undo removes exactly it. Example:
`overlays/desktop/apply.sh` enables `fstrim.timer` with
`systemctl --root="$LFS" enable` (falls back to `ln -s`), and leaves a
link that already existed alone (not recorded, not removed).

Stamp: `$LFS/var/lib/misl/overlays/<qname>/applied` (`name=`, `when=`),
ledger beside it in `owned`, firmware paths in `firmware.files`. The
active qnames (applied plus default) are written to `MISL_OVERLAYS=` in
the target's os-release on every apply and undo (`misl version` prints
them).

`MISL_CLOUD=1` turns on the kernel.list step for one build even when no
applied overlay has `kernel=1`. There is no `cloud.wanted`: kernel
extras come from the stamps and `kernel.list` only.

## One-way cloud

`cloud` (`oneway=1`) and its children cannot be undone. Before it is
applied, `overlay apply` (and `cloud apply`) prints what it edits in
place:

| path                                       | edit                                                                                       |
|--------------------------------------------|--------------------------------------------------------------------------------------------|
| `/etc/passwd`, `/etc/shadow`, `/etc/group` | `wheel` group added; root `!` becomes `*`; an old 0.3 `misl` user and `/home/misl` removed |
| `/etc/ssh/sshd_config`                     | `Include sshd_config.d`, `UsePAM no`                                                       |
| `/etc/ssh/sshd_config.d`                   | `99-misl-cloud.conf` added; `20-systemd-userdb.conf` removed                               |
| `/etc/sudoers.d/wheel`                     | `%wheel ALL=(ALL) NOPASSWD:ALL`                                                            |
| `/etc/resolv.conf`                         | link to systemd-resolved, if missing or already a link                                     |
| `/etc/cloud`, `/etc/systemd/network`       | cloud-init config, DHCP on `en*`/`eth*`                                                    |
| `/etc/systemd/system/*.wants`              | sshd, networkd, resolved, cloud-init, `serial-getty@ttyS0` enabled                         |
| `/root/.ssh`                               | created, mode 0700                                                                         |
| `/usr/lib/misl` (`cloud/do`)               | `do-ssh-keys` and `misl-do-sshkeys.service`                                                |

The notice does not stop the apply (no prompt; non-interactive builds
keep working). `overlay undo cloud`, `overlay undo cloud/do` and
`cloud undo` refuse with the reason and point to `misl reset` or a
rebuild.

## Reset

`./misl reset` puts `$LFS` back to the base tree as it was before the
first overlay was applied. Host only, like `overlay apply`; it does not
reset a running system.

**Snapshot.** The first `overlay apply` of a non-default overlay on a
tree with no overlay stamp saves, before anything is written,
`$LFS/var/lib/misl/reset/pre-overlay.tar.gz` (dir mode 0700; numeric owners, modes,
xattrs and ACLs when tar has them) and `manifest` (`misl_version=`,
`when=`, `lfs=`, one `path=` per saved path, `absent=` for paths that
did not exist). Saved paths: `/etc`, `/root`, `/var/lib/cloud`,
`/var/lib/misl/overlays`, `/var/lib/misl/firmware`,
`/var/lib/misl/cloud.report`, `/usr/lib/misl`. A tree that already has
stamps from before gets no snapshot (apply warns); rebuild it.
`img pack` leaves `var/lib/misl/reset/` out of the image.

**Reset** prints what it will do and needs `yes` typed in a terminal
or `MISL_FORCE=1` (without either it refuses). Then:

1. for each applied overlay, children first: remove its `owned` paths
   and its firmware (`firmware.files`), as undo does;
2. delete every saved path (and every `absent=` path) and unpack the
   snapshot, so files added under them since are gone;
3. rewrite `MISL_OVERLAYS` in os-release from the (now empty) stamps.

The snapshot is kept, so reset can be run again. With no snapshot reset
refuses and suggests a rebuild. `./misl reset --info` (or `reset
status`) shows whether a snapshot exists, when it was taken, its size,
the paths it restores and the overlays whose files it removes.

Reset does **not**:

- rebuild or remove packages: package-group builds (hw, wifi,
  bluetooth) and cloud-init from `cloud install` stay in `/usr`;
- change the compiled kernel: `kernel.list` extras stay until
  `MISL_FORCE=1 ./misl build 10-boot/linux`;
- touch `/home` or anything else outside the saved paths;
- keep changes other commands made under the saved paths after the
  snapshot (for example `config apply` in `/etc`): those go back too;
- remove the cloud-init tarball and wheels `cloud fetch` staged in
  `$LFS/usr/src/misl/SOURCES`.

## kernel.list

One option per line. `#` starts a comment (outside a quoted string),
blank lines are ignored, whitespace is trimmed, `CONFIG_` is optional.

```
CONFIG_VIRTIO          # built in (same as =y)
VIRTIO_NET=y           # built in
CONFIG_DRM_AMDGPU=m    # module
CONFIG_DRM_NOUVEAU=n   # off: "# CONFIG_X is not set" or absent
CONFIG_CMDLINE="console=ttyS0,115200"
CONFIG_LOG_BUF_SHIFT=17
CONFIG_PHYSICAL_START=0x1000000
```

Anything else (unknown value, empty value, missing quote, junk after
the string) stops the build with `kernel.list <file>:<line>`.

The step runs when an applied overlay has `kernel=1` (or
`MISL_CLOUD=1`). `10-boot/linux` then gathers the lists of every applied
overlay, at any
depth, in qname order, so ancestors come before children
(`misl_kernel_list_requests`, `lib/overlay.sh`). When two lists set
the same option, the later overlay wins and a warning names both. Values
go in through `scripts/config` (`--enable`, `--module`, `--disable`,
`--set-str`, `--set-val`), then `make olddefconfig`.

After that last `olddefconfig`, every requested value is checked
against `.config` (`misl_kernel_list_verify`). An option that did not
stick (a missing dependency, a renamed or removed symbol) fails the
build, naming the option, the wanted value, what `.config` has and the
overlay and `file:line` that asked for it. `MISL_KERNEL_LIST_LAX=1`
turns those failures into warnings for one build.

Test: `docs/fixtures/kernel-list-smoke.sh`.

| Overlay                       | Owns                                                                                                        |
|-------------------------------|-------------------------------------------------------------------------------------------------------------|
| `terminal`                    | the base (default=1). No apply hook. Undo refused.                                                          |
| `terminal/tui`                | stub                                                                                                        |
| `desktop`                     | wireless networkd file, wpa_supplicant template, fstrim.timer; `packages=hw,wifi,bluetooth`                 |
| `desktop/asus/rog-strix-x570` | board `kernel.list`, `firmware.list`, networkd/modprobe files; see docs/hardware/rog-strix-x570.md          |
| `cloud`                       | incoming cloud-init, virtio+8250 (`kernel.list`), networkd DHCP, sshd pubkey, root `*` shadow, serial-getty |
| `cloud/do`                    | ConfigDrive + DigitalOcean datasource, metadata keys on root                                                |
| `cloud/aws`                   | stub                                                                                                        |
| `cloud/gcp`                   | stub                                                                                                        |

## initramfs.list

Optional `overlays/<qname>/initramfs.list`: kernel modules this overlay
needs in the installed system's initramfs (`./misl initramfs build`,
also run by 10-boot/linux and 10-boot/grub). One module name per line,
`#` comments, `-` and `_` are equal. A bad name stops the build with
`file:line`. Only lists of **applied** overlays count.

```
# overlays/desktop/asus/rog-strix-x570/initramfs.list (example)
r8169      # onboard 2.5GbE
igc
```

The base list (NVMe, AHCI, sd/sr, USB storage + xHCI/EHCI/OHCI, virtio,
ext4, vfat + nls) is always in; `MISL_INITRAMFS_MODULES="a b"` adds more
for one run. Dependencies come from the target's `modules.dep`; names in
`modules.builtin` are skipped; names the kernel did not build are
recorded as `missing` (see `./misl initramfs list`). Firmware a module
declares (`firmware=` tags) is copied only from the staged
`/usr/share/misl/linux-firmware`; absent blobs are warned about, never
fetched. A module the initramfs needs at boot must also be enabled in
`kernel.list` (as `=m` or `=y`); NVMe, AHCI, ext4 and virtio are forced
`=y` by 10-boot/linux so the "(no initramfs)" GRUB entry still boots.

## firmware.list

Optional `overlays/<qname>/firmware.list`: firmware to install into
`/usr/lib/firmware` (= `/lib/firmware`, merged-usr) when the overlay is
applied. Nothing else from linux-firmware lands there. Same syntax as
`kernel.list` / `initramfs.list`: `#` comments, blank lines, errors name
`file:line`. Entries are paths relative to the staged tree
`/usr/share/misl/linux-firmware` (10-boot/linux-firmware, version in
`.misl-version`); no leading `/`, no `..`.

```
# overlays/desktop/asus/rog-strix-x570/firmware.list
rtl_nic/rtl8125b-2.fw
iwlwifi-cc-a0-*.ucode
intel/ibt-20-1-3.*
```

- Globs (`*`, `?`, `[...]`) and directories (`intel/` = everything below).
- An entry with no match is retried as `.xz` and `.zst` (if staged
  compressed).
- Symlinks in the staged tree (WHENCE `Link:` lines, made by
  copy-firmware.sh) stay symlinks; their targets are installed too.
- No match: apply fails with `file:line` before writing anything.
  `MISL_FIRMWARE_LAX=1` warns and installs the rest. Never fetched.
- Applying an overlay with a firmware.list before linux-firmware is
  staged fails (nothing written, not stamped). Build 10-boot first, then
  apply. Overlays without firmware.list are unaffected.
- A file already in `/usr/lib/firmware` that no overlay installed is
  never overwritten (`MISL_FORCE=1` overwrites it and the overlay then
  owns it: undo deletes it).
- Two overlays may name the same file: ownership is per overlay
  (`var/lib/misl/firmware/owners`), and a file or created directory goes
  only when its last owner is undone. Each overlay's paths are in
  `var/lib/misl/overlays/<qname>/firmware.files`.

`./misl firmware status` (also at the end of `misl overlay status`)
shows the staged version and per-overlay counts; `./misl firmware list
<overlay>` shows each resolved path as `installed`, `staged` (not
installed yet) or `present-unowned`.

The initramfs takes firmware only from the staged tree, for
the modules it contains (their `firmware=` tags). For firmware at early
boot (e.g. amdgpu KMS) add the module to the overlay's `initramfs.list`;
its declared blobs come along. No separate opt-in.

## Package groups

Every row in `config/packages.manifest` (all stages, including
09-config and rows with tarball `-`) has **exactly one** `group=<name>`
in its notes column. One group per package. Errors, reported as
`file:line` before anything is fetched, staged or built:

- no `group=` on a row;
- a comma list (`group=hw,wifi`) or a second `group=`;
- a name not in the declared list.

| group     | meaning                                                                                                                                | selected | rows |
|-----------|----------------------------------------------------------------------------------------------------------------------------------------|----------|------|
| base      | toolchain + core system every image needs (05/06/07, glib, systemd, python and its build deps, grub, linux, linux-firmware, 09-config) | always   | 126  |
| hw        | physical hardware userland: hwdata, pciutils, libusb, usbutils, ethtool, alsa-lib, alsa-ucm-conf, alsa-utils, lm-sensors               | optional | 9    |
| wifi      | Wi-Fi userland: libnl, wpa_supplicant, iw, wireless-regdb                                                                              | optional | 4    |
| bluetooth | Bluetooth userland: bluez (glib is base)                                                                                               | optional | 1    |
| lisp      | sbcl (+ incoming `sbcl-2.6.10-x86-64-linux-binary.tar.bz2` bootstrap, `config/incoming.manifest`)                                      | optional | 1    |
| cloud     | no rows; incoming cloud-init tarball and its 13 Python wheels (`config/incoming.manifest`)                                             | optional | 0    |

The list is declared in `lib/groups.sh` (`MISL_GROUPS_DEFINED`) and in
the manifest header. No base row needs an optional row to build or run.

Selected = base, plus:

    MISL_GROUPS (env or misl.conf, comma/space list; all = every group)
    + packages= of every target overlay (and its parents/requires)
    + $LFS/var/lib/misl/groups (only if both above are empty)

Target overlays are `MISL_TARGET_OVERLAYS` (qname or leaf name list) or,
if unset, the overlays applied on `$LFS`. `misl sources stage` records
the optional selection in `$LFS/var/lib/misl/groups`, so `build-stage`
inside the chroot (where the overlays are not applied yet) sees the same
set. An explicit `misl build 08-system/<pkg>` of a non-selected row
warns and builds anyway. `./misl groups` lists every group with its
meaning, rows and whether it is selected.

Overlay `packages=` (a list is fine here; one group per *package*):

| overlay                               | packages=            | image gets                |
|---------------------------------------|----------------------|---------------------------|
| terminal, terminal/tui                | (empty)              | base                      |
| cloud, cloud/do, cloud/aws, cloud/gcp | `cloud` (on `cloud`) | base, cloud               |
| desktop                               | `hw,wifi,bluetooth`  | base, hw, wifi, bluetooth |
| desktop/asus/rog-strix-x570           | `hw,wifi,bluetooth`  | base, hw, wifi, bluetooth |

lisp is never pulled by an overlay: `MISL_GROUPS=lisp`.

## Incoming files

`config/incoming.manifest` lists every file misl takes from the
mirror's `incoming/`: external build and install inputs that are not
built as distro packages. Columns: `group name version file md5
notes`; notes carry `kind=wheel|tarball|binary` and an optional
`md5env=VAR`. `file` is a path under `incoming/`: the wheels are in
`incoming/wheels/` on the mirror and stay under `wheels/` in the
snapshot and in `SOURCES`. md5 order: the mirror `md5sums`, then `$VAR`, then the
md5 column; `-` means not known yet and only warns.

| group | file                                                            | kind    | used by                          |
|-------|-----------------------------------------------------------------|---------|----------------------------------|
| lisp  | `sbcl-2.6.10-x86-64-linux-binary.tar.bz2`                       | binary  | 08-system/sbcl bootstrap         |
| cloud | `cloud-init-26.2.tar.gz`                                        | tarball | `cloud install` (meson)          |
| cloud | `wheels/`: PyYAML, requests, urllib3, idna, charset-normalizer, | wheel   | `cloud install` (pip --no-index) |
|       | certifi, configobj, jsonpatch, jsonpointer,                     |         |                                  |
|       | jsonschema 4.17.3, attrs, pyrsistent, oauthlib                  |         |                                  |

Wheels are `cp314` manylinux x86_64 where the package ships compiled
code (PyYAML, charset-normalizer), else `py3-none-any`; pyrsistent has
no `cp314` build and runs as pure Python. jsonschema stays below 4.18
so it needs no rpds-py (Rust). Jinja2 and MarkupSafe are base
packages, not wheels.

`sources fetch|check|stage` handle the incoming rows of the selected
groups; `misl cloud fetch` handles the `cloud` rows regardless of the
selection and stages them into `$LFS/usr/src/misl/SOURCES`. Staging
refuses a file whose md5 does not match. `cloud install` (chroot) runs
`python3 -m pip install --no-index --find-links /usr/src/misl/SOURCES/wheels`
on exactly the listed wheel files and stops naming any that are
missing. No step talks to PyPI.

Test: `docs/fixtures/incoming-smoke.sh` (fake files under `/tmp`, no
network).

## Flat 0.3 stamps

A stamp at `<state>/<leaf>/applied` (the flat 0.3 layout, e.g.
`overlays/do/applied`) counts as the nested overlay with that leaf
(`do` → `cloud/do`) when no top-level overlay has that name.
`overlay status` marks it `0.3 stamp`. The next apply or undo of that
overlay moves the stamp dir and its `owned` ledger to
`<state>/<qname>/`.

Test: `docs/fixtures/overlay-nested-smoke.sh` (fake tree and fake LFS
under `/tmp`, no root).
