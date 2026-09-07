<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Overlays

One source graph. Machine-kind is an overlay, except **terminal**: that
*is* the base install (console, shell, chapter 8). Cloud is opt-in.

`overlay list` prints a header and qualified names (`parent/name` when
`parent=` is set). Cloud children are `cloud/do`, `cloud/aws`,
`cloud/gcp` in that order. Status and class come from each
`overlay.conf`.

```
NAME          STATUS  ON       CLASS  TITLE
terminal      alpha   default  local  Text console and shell and terminal apps
terminal/tui  stub    off      local  Text console and terminal user interface
desktop       stub    off      local  Local graphical workstation
cloud         alpha   off      cloud  Cloud guest (virtio, serial, cloud-init)
cloud/do      alpha   off      cloud  DigitalOcean Custom Image
cloud/aws     stub    off      cloud  Amazon EC2
cloud/gcp     stub    off      cloud  Google Compute Engine
```

`ON=default` means default, not stamped. `apply cloud` does not turn
terminal off. `undo terminal` is refused.

```
./misl overlay list
./misl overlay apply cloud do
./misl overlay undo do cloud
```

`./misl cloud apply` is `overlay apply cloud do`.
`./misl cloud undo` is `overlay undo do cloud` (child first).

```
overlays/<name>/overlay.conf   name title class requires parent
                               priority status kernel default
overlays/<name>/kernel.list    optional; 10-boot/linux when kernel=1
overlays/<name>/apply.sh       optional; host-side, LFS set
overlays/<name>/undo.sh        optional; plus overlays/<name>/owned ledger
```

Only `cloud` and `do` ship apply/undo today. Only `cloud` ships
`kernel.list`. stub overlays are conf-only.

`status`: stub → alpha → beta → rc → stable. stub does not apply
(`overlay apply aws` dies).

Stamp: `$LFS/var/lib/misl/overlays/<name>/applied`.
Active qnames (qualified names) also go into `MISL_OVERLAYS` on os-release
(`misl version` prints them). Default overlays appear there
without a stamp.

`10-boot/linux` reads overlay stamps + `kernel.list` only.
`MISL_CLOUD=1` remains a one-rebuild override.

| Overlay        | Owns                                                                                                        |
|----------------|-------------------------------------------------------------------------------------------------------------|
| `terminal`     | the base (default=1). No apply hook. Undo refused.                                                          |
| `terminal/tui` | stub                                                                                                        |
| `desktop`      | stub                                                                                                        |
| `cloud`        | incoming cloud-init, virtio+8250 (`kernel.list`), networkd DHCP, sshd pubkey, root `*` shadow, serial-getty |
| `cloud/do`     | ConfigDrive + DigitalOcean datasource, metadata keys on root                                                |
| `cloud/aws`    | stub                                                                                                        |
| `cloud/gcp`    | stub                                                                                                        |
