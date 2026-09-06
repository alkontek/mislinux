<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Operator notes — MIS Linux 0.4

## Scope

- `cloud/aws` and `cloud/gcp` on the same pattern as `cloud/do`.
  `status=stub` does not apply.
- Overlay apply records every file it owns. Undo is exact, not
  best-effort. Children undo before parents (`undo cloud` while `do` is
  on must print the command, or do it).
- Drop `cloud.wanted`. Kernel extras read overlay stamps + `kernel.list`
  only. `MISL_CLOUD=1` can stay as an override for one rebuild.
- OpenSSH: PAM, or delete `UsePAM` from the recipe. Stop shipping
  systemd `20-systemd-userdb.conf`. Replace the `useradd` wrapper
  (shadow `!` vs pubkey without PAM).
- Decide `%wheel NOPASSWD` — keep it off `cloud`, or wait for passwords.
- Vendor cloud-init Python wheels under `incoming/`, or real recipes.
  pip + chroot DNS is a 0.3 hole.
- `img pack` stays BIOS GPT. qcow2/EFI are optional and not `doctor`.
- No droplet-agent unless it builds from our mirror.
- After `misl bump`, run `misl config apply` so `/etc/os-release`
  matches VERSION.

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
3. Install cloud-init without hitting PyPI (`incoming/` wheels or
   recipes).
4. `./misl img pack` a BIOS GPT image; `./misl img test` reaches a
   serial getty on virtio.
5. `./misl overlay undo do cloud` (or `./misl cloud undo`) and get the
   base tree back. Owned files gone, stamps gone, `MISL_OVERLAYS` is
   `terminal`.

Until those six hold, stay on 0.3.
