<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Recipe format

A recipe is a bash file under `stages/` that sets `pkg_*` and optional hooks,
then gets sourced by `misl build`. `recipe_main` unpacks, patches, builds,
installs, logs a TSV line under `$LFS/var/lib/misl/pkglog/`, and stamps
`$LFS/var/lib/misl/stamps/<stage>-<name>-<pass>.done`.

| Field                                   | Future RPM tag    |
|-----------------------------------------|-------------------|
| pkg_name                                | Name              |
| pkg_version                             | Version           |
| pkg_tarball                             | Source0           |
| pkg_patches                             | Patch0..N         |
| pkg_configure / pkg_build / pkg_install | %build / %install |

## Stage numbers

`NN-name` follows **LFS chapter numbers**, not systemd targets or runlevels.

| Directory                | Book                       | CLI                                                         |
|--------------------------|----------------------------|-------------------------------------------------------------|
| `01-variant/`            | reserved                   | future distro/init choice (systemd is the only 0.2 variant) |
| `02-host/`               | §2.2 host requirements     | `misl doctor`                                               |
| `02-disk/`               | §2.4–2.5 partition / mount | `misl disk plan`                                            |
| `03-sources/`            | ch. 3                      | `misl sources`                                              |
| `04-prep/`               | ch. 4                      | `misl prep`                                                 |
| `05-cross` ... `10-boot` | ch. 5–10                   | `misl build` / `build-stage`                                |

`02-host` and `02-disk` share `02` because LFS chapter 2 covers both. They are not one `build-stage`. `01` is empty on purpose.

Chapter 5–6 recipes refuse to run as root.

Preflight checks only the recipe tarball (md5 if listed). Other distfiles
may be missing. The libstdc++ stub file is `stages/05-cross/libstdcxx.sh`.

Pkglog columns: name, version, tarball, md5, stage, pass, timestamp.
