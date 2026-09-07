<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Make it so. Linux

![Make it so.](marketing/make-it-so-jean-luc-picard.gif)

**MIS Linux (or MISL)** — A hand-picked, professional, LFS/BLFS source-first
distribution for servers, desktop workstations, and science applications.

Slogan: ***Born from LFS, headed for the Delta Quadrant.***

## Features

- From-source install on a Fedora host onto a real disk
- GPT + EFI (`EFI/misl` and removable `BOOTX64.EFI`), no swap
- Chapter-order recipes (`misl build` / `build-stage`)
- OpenSSH 10.5p1 and nano 9.2 in the base system
- Overlays on a clean base (`terminal` is the default; `cloud/do` is opt-in)
- BIOS GPT images (`img pack` / `img test`) and live ISO/USB (`iso pack` / `iso usb`)
- Mid-build `sources integrate`; session-only chroot DNS (`misl net`)
- Road to rpm/dnf and a local SRPMS repo
- Will always stay source first.

**And we also have cool Star Trek features for fans:**
```
$ stardate 2026-09-03 16:20:00 UTC
Input Time : 2026-09-03 16:20:00 UTC
Kelvin Era : 2026.67310
TNG Era    : 43673.09741
```

## Major versions

Minor names are not ours to assign. The community votes those.
But we wrote [options](marketing/version_names.txt).

| Version | Codename        |                                                                |
|---------|-----------------|----------------------------------------------------------------|
| 1.0     | Farpoint        | WIP: planned for November-December, 2026 release.              |
| 2.0     | Utopia Planitia | SRPM support, H1 2027                                          |
| 3.0     | USS Galaxy      | RPM support, binary variant, H1 2028                           |
| 4.0     | Voyager         | H1 2029                                                        |
| 5.0     | Unimatrix Zero  | H1 2030                                                        |

### Simple command interface, easy to begin

```bash
./misl doctor install
./misl sources fetch
./misl disk plan
./misl prep
su - lfs
./misl build-stage 05-cross
```

The chroot shares the host network but not host DNS. For a session that
needs name lookup (pip, curl):

```bash
./misl net on          # host: bind host resolv.conf into $LFS
./misl enter           # or: ./misl enter --net
# … work …
logout
./misl net off         # host: unbind; not written into the image
```

Overlays sit on the base tree (`./misl overlay list`). Cloud guests:

```bash
./misl overlay apply cloud do
./misl enter
MISL_FORCE=1 ./misl build 10-boot/linux
./misl cloud install
logout
```

**Sanitize and create an image:**
```
./misl cloud sanitize
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-terminal.img
./misl img test -o /var/tmp/misl-0.3-terminal.img
```


`./misl cloud apply` is the same as `overlay apply cloud do`. See
[overlays.md](docs/overlays.md) and [operator-0.3.md](docs/operator-0.3.md).

## Creating and Testing Images

### The `img` command
```
./misl img pack --from-tree --gzip -o /var/tmp/misl-0.3-terminal.img
./misl img pack --from-disk -o /var/tmp/misl-0.3-terminal.img
./misl img test --virtio -i /var/tmp/misl-0.3-terminal.img
./misl img test --ide -i /var/tmp/misl-0.3-terminal.img
```

### The `iso` command

**Creating a BIOS image:**
```
./misl iso pack --bios --live  /var/tmp/misl-0.3-terminal.img /var/tmp/misl-0.3-terminal-bios.iso
./misl iso test --bios /var/tmp/misl-0.3-terminal-bios.iso
```

**Creating a UEFI image:**
```
./misl iso pack --uefi --live  /var/tmp/misl-0.3-terminal.img /var/tmp/misl-0.3-terminal-uefi.iso
./misl iso test --uefi /var/tmp/misl-0.3-terminal-uefi.iso
```

**Write a live USB (wipes the stick):**
```
./misl iso usb --list
MISL_FORCE=1 ./misl iso usb /var/tmp/misl-0.3-terminal-uefi.iso /dev/disk/by-id/usb-…
```

----
## The `misl` command help
```
MIS Linux 0.3 bootstrap
usage: misl <command> [args]

  version              print bootstrap version and os-release identity
  bump minor|major|undo|X.Y rewrite VERSION + misl.conf (+ example)
  env [list|export]    print resolved site pins (export: shell assignments)
  os-release           print the composed /etc/os-release text
  help                 this text
  doctor               host qualification (Fedora 44)
  doctor pkgs          print Fedora 44 dnf install line
  doctor install       dnf install host deps (root, Fedora)
  disk plan            print partition/mount plan (no writes)
  disk apply           gates + plan only (policy A; does not format)
  sources fetch        refresh catalog, create $MISL_SNAPSHOT, wget wget-list files
  sources refresh      replace snapshot wget-list + md5sums from $MISL_MIRROR
  sources integrate [--reintegrate] <name>
                       host only: refresh catalog, fetch one package, stage
                       (prints chroot build next; does not compile)
  sources check        verify wget-list files against md5sums
  sources stage        hardlink verified files into $LFS/usr/src/misl
  sources remote       HEAD-check $MISL_MIRROR wget-list + md5sums (no download)
  integrate            alias for sources integrate
  prep                 chapter 4 layout + lfs user + env + grant $LFS
  prep publish         also copy mislinux/ into ~lfs (not the tarball tree)
  build <recipe>       run a stages/* recipe (stage/name if ambiguous)
  build-stage <stage>  run every packages.manifest row for that stage
  logs [name]          tail recipe log (default: newest under $LFS/var/lib/misl/logs)
  status               package graph + stamps
  config               print last chapter-9 config report
  config apply         re-run 09-config/systemd-config (MISL_FORCE=1)
  chroot prep          ch7 owner + virtfs + files + publish scripts into /mnt/misl
  enter [--net]        chroot into /mnt/misl as root (--net: host DNS for the session)
  net on|off|status    bind host resolv.conf into $LFS (host only, not permanent)
  overlay list|status|apply|undo|install
                       named extras on the base tree (cloud, do, …)
  cloud apply          overlay apply cloud do (compat)
  cloud undo           overlay undo do then cloud
  cloud install        chroot: meson-install cloud-init (cloud overlay)
  cloud status         print $LFS/var/lib/misl/cloud.report
  cloud sanitize       drop machine-id / ssh host keys / cloud-init seed
  cloud wheels         host: pip download deps into incoming/ (needs DNS)
  img pack             host root: pack $LFS into a BIOS GPT .img
  img test             host qemu of that .img (--virtio default, --ide to compare)
  iso pack             host root: live ISO from a packed .img (--uefi default)
  iso test             host qemu of that .iso (--uefi default, --bios for SeaBIOS)
  iso test --inspect   mount ISO, unpack initramfs, list /init + libs (no qemu)
  iso inspect          same as iso test --inspect
  iso usb --list       USB disk nodes under /dev/disk/by-id/usb-* (no -part)
  iso usb ISO DISK     wipe that stick as GPT+ESP and copy a --uefi ISO
                       MISL_FORCE=1 ; example:
                       MISL_FORCE=1 ./misl iso usb FILE.iso /dev/disk/by-id/usb-SanDisk_Cruzer_Blade_...-0:0

Sources: /var/cache/misl/misl-1.0-systemd/wget-list
Snapshot: /var/cache/misl/misl-1.0-systemd
Mirror: https://makeitsolinux.org/downloads/misl-1.0-systemd
```

## Resources

* Version `0.3` operator notes: [operator-0.3.md](docs/operator-0.3.md)
* Version `0.3` Fedora 44 / DigitalOcean image test: [test-0.3-do-vps.md](docs/test-0.3-do-vps.md)
* Version `0.2` operator notes: [operator-0.2.md](docs/operator-0.2.md)
* The [Official Website](https://makeitsolinux.org/)
* Version 1.0 [Repository](https://makeitsolinux.org/downloads/misl-1.0-systemd/).
* [Linux From Scratch](https://www.linuxfromscratch.org/lfs/) (LFS)
* [Beyond Linux From Scratch](https://www.linuxfromscratch.org/blfs/) (BLFS)

## Code of Conduct

* We encourage taking personal responsibility and being nice to the community.