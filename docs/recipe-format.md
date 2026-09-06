<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Recipe format

A recipe is a bash file under `stages/` that sets `pkg_*` and optional hooks,
then gets sourced by `misl build`. `recipe_main` unpacks, patches, builds,
installs, logs a TSV line under `$LFS/var/lib/misl/pkglog/`, and stamps
`$LFS/var/lib/misl/stamps/<stage>-<name>-<pass>.done`.

| Field                                   | Future RPM tag                                     |
|-----------------------------------------|----------------------------------------------------|
| pkg_name                                | Name                                               |
| pkg_version                             | Version                                            |
| pkg_tarball                             | Source0                                            |
| pkg_patches                             | Patch0..N                                          |
| pkg_configure / pkg_build / pkg_install | %build / %install                                  |
| pkg_requires                            | BuildRequires (stamp check; space-separated names) |

## Stage numbers

`NN-name` follows **LFS chapter numbers**, not systemd targets or run-levels.

| Directory                | Book                       | CLI                                                         |
|--------------------------|----------------------------|-------------------------------------------------------------|
| `01-variant/`            | reserved                   | future distro/init choice (systemd is the only 0.2 variant) |
| `02-host/`               | §2.2 host requirements     | `misl doctor`                                               |
| `02-disk/`               | §2.4–2.5 partition / mount | `misl disk plan`                                            |
| `03-sources/`            | ch. 3                      | `misl sources`                                              |
| `04-prep/`               | ch. 4                      | `misl prep`                                                 |
| `05-cross` ... `10-boot` | ch. 5–10                   | `misl build` / `build-stage`                                |

`02-host` and `02-disk` share `02` because LFS chapter 2 covers both.
They are not one `build-stage`. `01` is empty on purpose.

Chapter 5–6 recipes refuse to run as root.

Preflight checks only the recipe tarball (md5 if listed). Other dist-files
may be missing. The libstdc++ stub file is `stages/05-cross/libstdcxx.sh`.

PkgLog columns: name, version, tarball, md5, stage, pass, timestamp.

`misl status` states: `done` (stamp), `integrated`, `ready` (row has
`implemented=` and a non-stub recipe), `norecipe` (`implemented=` but no
recipe file), `blocked` (notes carry `blocked=<dep>`: a dependency not on
the mirror yet), `stub`.

`linux-firmware` (10-boot) only stages the tree under
`/usr/share/misl/linux-firmware`; `/lib/firmware` is filled per overlay
from `firmware.list` (plan-0.4 item 5).

## Mid-build integrate

A package added to the remote snapshot after `misl sources fetch` already
ran is pulled in with:

```
# 1. row in config/packages.manifest (one name in 08-system / 09 / 10)
# 2. recipe stages/<stage>/<name>.sh
# 3. tarball URL on makeitsolinux.org wget-list
misl sources integrate openssh
```

Run it on the **Fedora host** (wget lives there, not in the chroot).
It refreshes snapshot `wget-list` + `md5sums`, fetches only that
tarball (and listed patches), hardlinks into `$LFS/usr/src/misl/SOURCES`,
and prints `misl enter` + `misl build`. It does not compile. A second
integrate of the same name dies. Change the version with `--reintegrate`,
then `MISL_FORCE=1 ./misl build` inside the chroot. One registry file
per name under `$LFS/var/lib/misl/integrated/` — two `openssh` rows
or two integrated versions are refused.

## pkg_check (optional)

Runs after `pkg_install`/`pkg_post_install`, in the build dir, in the
same build context (inside the chroot for 07+). A non-zero return or
`die` fails the recipe: no pkglog line, no stamp. Check files under
`$(misl_dest)` so DESTDIR installs work. Run target binaries through
`misl_check_run cmd ...`, which skips with a warning when installing
into a DESTDIR. `MISL_SKIP_CHECK=1` skips all checks.
