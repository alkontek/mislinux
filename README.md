# MIS Linux (MISL)

![Make it so](marketing/make-it-so-jean-luc-picard.gif)

**Make It So! Linux** — A hand-picked source `x86_64/systemd` distribution.  
Born from LFS, headed for Farpoint.

Our motto is to have fun, but act professional. This distribution is heavily 
focused on servers and workstations. In time, we'll have surprise for desktop
users as well. 

## Features

- From-source install on a Fedora host onto a real disk
- GPT + EFI (`EFI/misl` and removable `BOOTX64.EFI`), no swap
- Chapter-order recipes (`misl build` / `build-stage`)
- OpenSSH in the base system
- Overlay extras under `usr/bin/`, etc.
- Road to rpm/dnf and a local SRPMS repo.
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
| 1.0     | Farpoint        | A source distro for exceptional developers and Star Trek fans. |
| 2.0     | Utopia Planitia | SRPM support                                                   |
| 3.0     | USS Galaxy      | RPM support, Binary variant,                                   |
| 4.0     | Voyager         |                                                                |
| 5.0     | Unimatrix Zero  |                                                                |

### Simple command interface, easy to begin

```
./misl doctor install
./misl sources fetch
./misl disk plan
./misl prep
su - lfs
./misl build-stage 05-cross
```
## Resources

* Version `0.2` operator notes: [operator-0.2.md](docs/operator-0.2.md)
* The [Official Website](https://makeitsolinux.org/)
* Version 1.0 [Repository](https://makeitsolinux.org/downloads/misl-1.0-systemd/).

## Code of Conduct

* We encourage taking personal responsibility and being nice to the community.