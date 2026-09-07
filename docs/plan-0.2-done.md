<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Plan — MIS Linux 0.2

**Status:** done. Historical.  
**Operator notes:** [`operator-0.2.md`](operator-0.2.md).

0.2 turned an empty bootstrap tree into a resumable, fail-closed
framework on Fedora 44: host doctor, dry-run disk, wget-list sources,
chapter 4 prep, recipe engine, and **binutils pass 1** as the proof
the engine compiles.

## What 0.2 owned

- `misl` + `config/misl.conf` + `packages.manifest`
- `lib/{common,config,host,disk,sources,env,recipe,chroot,pkglog}.sh`
- `docs/disk-safety.md`, `docs/recipe-format.md`
- `usr/src/misl/{SOURCES,SPECS,SRPMS,RPMS}` reservation (empty SPECS)
- Triplet stays `x86_64-lfs-linux-gnu` until a later identity rebuild
- No rpm, no dnf, no kernel defconfig as a product
