<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Plan — MIS Linux 0.4

**Status:** current, in-development  
**Dev-branch:**: `origin/0.4-dev`  
**Operator manual:** [`docs/operator-0.4.md`](operator-0.4.md)  
**Version Goal:**

1. Machine-kind and guest images
2. Expanding overlays
3. Integrating more system libraries and developer tools,
   terminal and terminal UI software.

## Scope

- Exact overlay undo: apply records every owned file; undo deletes
  only those. Children before parents (`undo cloud` while `do` is on
  prints the command, or does it).
- Drop `cloud.wanted`. Kernel extras = overlay stamps + `kernel.list`.
  `MISL_CLOUD=1` may remain as a one-rebuild override.
- Vendor cloud-init Python wheels under `incoming/`, or write recipes.
  No PyPI from the chroot.
- OpenSSH: PAM, or delete `UsePAM`. Drop systemd
  `20-systemd-userdb.conf`. Replace the `useradd` wrapper.
- `%wheel NOPASSWD` stays off `cloud` unless we ship passwords.
- `img pack` stays BIOS GPT. qcow2/EFI pack is optional and not
  `doctor`.
- After `misl bump`, `misl config apply` so os-release matches VERSION.

## Done when

- ...
