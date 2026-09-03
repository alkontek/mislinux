<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Disk safety

`misl disk apply` is **policy A in 0.2**: it checks the gates, prints the
plan, and **does not** call `parted`, `mkfs`, or `mount`. That is the spec,
not a missing feature. Real formatting is 0.3.

`MISL_DISK` is a required parameter (config or environment). It is never
defaulted. Persistent by-id paths are valid and preferred:

```
MISL_DISK=/dev/disk/by-id/scsi-0DO_Volume_misl
LFS=/mnt/misl
```

Partition nodes derived from that path:

| Device style          | Partition N                 |
|-----------------------|-----------------------------|
| `/dev/disk/by-id/FOO` | `/dev/disk/by-id/FOO-partN` |
| `/dev/nvme0n1`        | `/dev/nvme0n1pN`            |
| `/dev/sda`            | `/dev/sdaN`                 |

Layout follows **target** firmware (`MISL_FIRMWARE`, default `efi`), not the
host droplet. No swap. Boot size is `${MISL_BOOT_MIB:-1024}` MiB.

- **efi** (default): p1 1 GiB FAT32 ESP (`MISL_PART_BOOT` → `$LFS/boot/efi`).
  Later bootloader work puts `EFI/misl/` on that ESP, same shape as
  `EFI/fedora` / `EFI/Microsoft`. p2 rest `$MISL_FSTYPE` root (`$LFS`).
  `/boot` itself is a directory on root; it is not a second ext4 partition.
- **bios**: p1 1 MiB `bios_grub` (not mounted), p2 1 GiB ext4 `/boot`,
  p3 rest root. Use only if the machine that will boot this disk is BIOS.
- **auto**: look at host `/sys/firmware/efi`. Do not use this on the VPS
  if the finished disk is meant for an EFI PC.

Gates (all required even to print the apply-time plan):

- running as root
- `MISL_DISK` is set
- `MISL_CONFIRM=YES-DESTROY-DISK`
- `MISL_DRY_RUN=0`
- `LFS` is set
- `MISL_DISK` is not the disk behind `/` (compared after `readlink -f`), unless `MISL_ALLOW_HOST_DISK=1`

`misl disk plan` only prints. It never writes.

Partition and mount by hand from the plan, then continue with
`misl sources stage` and `misl prep`.
