<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# Plan — MIS Linux 0.4

**Status:** current, in-development  
**Dev-branch:** `origin/0.4-dev`  
**Operator manual:** [`docs/operator-0.4.md`](operator-0.4.md)  
**Version Goal:**

1. Integrate the new mirror structure (`docs/` path) and the new
   0.4 packages: recipes build, `misl status` is honest.
2. Optional docs: `config/docs.manifest` and `misl docs`.
3. Nested overlays: `desktop/asus/rog-strix-x570` works on real
   hardware.
4. Machine-kind and guest images: initramfs, firmware, `kernel.list`.
5. Exact undo (and reset for one-way overlays); no PyPI.

Freeze unchanged: LFS/BLFS **13.1-systemd**, kernel **7.1.8**,
`wget-list` only. Policy A on `disk apply`.

## Mirror

<https://makeitsolinux.org/downloads/misl-1.0-systemd/> — named 1.0,
holds 0.3 content, grows toward 1.0.

- `sources/` new for 0.4: cmake-4.4.3, curl-8.22.0, htop-3.5.3,
  jq-1.8.2, lsof-4.99.6, rsync-3.5.0, strace-7.2, tmux-3.7c,
  wget-1.25.0, libnl-3.12.0, wpa_supplicant-2.12,
  linux-firmware-20261019.
- `docs/` (new path): python-3.14.7-docs-html.tar.bz2,
  sqlite-doc-3530400.zip, tcl8.6.18-html.tar.gz.
- Each has a `packages.manifest` row (`implemented=0.4`) and a recipe.
  wpa_supplicant over iwd: wider hardware.

There is no `artifacts/` directory.

## Known bugs (fix first)

- `./misl help` dies `LFS: unbound variable` when `LFS` is unset.

## Work, in order

1. **Repo structure + packages + docs.**
   - `lib/sources.sh` knows the mirror `docs/` path (stage, check).
   - Recipes for the 12 new packages; manifest rows corrected.
   - `config/docs.manifest`: `name version tarball package path`
     (e.g. `/usr/share/doc/python-3.14.7`). Not in the package graph.
   - `misl docs list|install|remove <name>` on a finished system or
     `$LFS`. `MISL_DOCS=` in `misl.conf` (empty default) picks docs
     at install time. Install records every file; remove is exact.
   - `misl sources check` verifies docs against `md5sums`; fetching
     docs is optional. Docs are not an overlay.
2. **Nested overlays.** `overlays/desktop/asus/rog-strix-x570/`.
   Qualified names are the path; parent is implied by the folder.
   Undo children before parents. Stamps follow the qualified name.
3. **`kernel.list` rework.** One shared helper in `lib/overlay.sh`;
   remove the duplicate loop in `stages/10-boot/linux.sh`. Syntax:
   `CONFIG_X` (=y), `CONFIG_X=y`, `=m`, `=n`, `="str"`. After the last
   `olddefconfig`, check every requested value stuck; fail loudly if not.
4. **Initramfs for the installed system.** Start from the `iso pack`
   initramfs (no dracut). Early AMD/Intel microcode. NVMe, AHCI and
   virtio stay built in as a fallback. Serves cloud and desktop.
5. **Firmware staging.** `linux-firmware` tarball from the mirror.
   Per-overlay `firmware.list` installs only the files it names,
   recorded for undo. Firmware is staged, never taken from the host.
6. **Desktop + `desktop/asus/rog-strix-x570`.** `desktop` stub → alpha.
   Board overlay: `class=local`, `parent=desktop`, `kernel=1`, alpha
   when functional. Igal's board, Intel AX200 Wi-Fi:
   - I211 — `igb`.
   - RTL8125 — mainline `r8169` + `rtl_nic` firmware. Vendor `r8125`
     only as a documented fallback (no stable upstream URL).
   - AX200 — `iwlwifi`/`iwlmvm` + firmware.
   - Bluetooth — `btusb`/`btintel` + `ibt` firmware.
   - ALC1220A — `snd-hda-intel` + Realtek codec.
   - wpa_supplicant + libnl, networkd `.network`, `modprobe.d` notes.
   Self-contained; the reference for future board overlays.
7. **Undo and reset.** Undo stays exact for overlays that only add
   tracked files (`files/`, `firmware.list`, owned links). `cloud` and
   its children are one-way (`oneway=1`): they edit shadow, group,
   `sshd_config`, `resolv.conf` and sudoers in place, so `overlay undo`
   and `cloud undo` refuse and print why. Apply prints what cloud edits
   first. The way back is `misl reset`: the first overlay apply on a
   base tree saves a snapshot of `/etc`, `/root` and the overlay state
   under `$LFS/var/lib/misl/reset/`; reset removes the overlay-owned
   files and firmware and restores those paths exactly. No
   `cloud.wanted`; kernel extras = overlay stamps + `kernel.list`,
   `MISL_CLOUD=1` as a one-rebuild override.
8. **No PyPI.** cloud-init's Python deps are 13 pinned wheels in the
   mirror's `incoming/wheels/`, listed with their md5 in
   `config/incoming.manifest` (group `cloud`, next to the cloud-init
   tarball and the SBCL bootstrap). `misl cloud fetch` and
   `sources fetch|check|stage` take them from `incoming/` only;
   `cloud install` runs `pip install --no-index` on exactly those
   files (pip comes from ensurepip in 08-system python). No
   `misl cloud wheels`, no pip download, no `python3-pip` on the host.
9. **Docs.** `overlays.md` (nested model, `kernel.list` syntax,
   `firmware.list`), `operator-0.4.md` (fix the "five vs six" count,
   add desktop items), `patches.md` (numbering),
   `plan.md` dead `plan-0.5`…`0.9` links.

Still in scope:

- OpenSSH: PAM, or delete `UsePAM`. Drop systemd
  `20-systemd-userdb.conf`. Replace the `useradd` wrapper.
- `%wheel NOPASSWD` only on `cloud`, unless we ship passwords.
- `img pack` stays BIOS GPT. qcow2/EFI pack is optional and not
  `doctor`.
- `misl reset --all`: wipe `$LFS` and build state for a clean build;
  keep downloads and built images.

## Hardware userland + package groups

Recipes for the hardware userland (glib, hwdata, pciutils, libusb,
usbutils, ethtool, wireless-regdb, iw, alsa-lib, alsa-ucm-conf,
alsa-utils, bluez, lm-sensors) and sbcl. Every manifest row has exactly
one `group=` (base, hw, wifi, bluetooth, lisp); overlays select optional groups
with `packages=`. See `overlays.md` "Package groups".

## Done when

- [ ] `./misl help` works with `LFS` unset.
- [ ] `sources check` passes for `sources/`, `patches/` and `docs/`
      against `md5sums`.
- [ ] All 12 new packages have recipes, build in a full run, and
      `misl status` shows them `done` (no `ready` without a recipe).
- [ ] `misl docs list|install|remove` works on `$LFS` and a booted
      system; `remove` leaves no file behind; `MISL_DOCS=` installs the
      chosen docs.
- [ ] `misl overlay list` shows `desktop/asus/rog-strix-x570`;
      apply pulls `desktop`, undo refuses parents while children are on.
- [ ] Every `kernel.list` value is in the final `.config`, or the
      build fails naming it.
- [ ] The installed system boots through its own initramfs with
      microcode; cloud images still boot.
- [ ] Only `firmware.list` files land in `/lib/firmware`; undo removes them.
- [ ] On the ROG Strix X570: I211 and RTL8125 link, AX200 joins Wi-Fi
      via wpa_supplicant, Bluetooth pairs, ALC1220A plays.
- [ ] Apply then undo of any overlay leaves the tree byte-identical.
- [ ] No PyPI access anywhere; cloud-init installs from the pinned
      `incoming/` wheels.
- [ ] `overlays.md`, `operator-0.4.md`, `patches.md`, `plan.md` are
      current.
