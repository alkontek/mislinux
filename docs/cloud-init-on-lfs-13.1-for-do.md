# Cloud-init on an existing LFS 13.1 (systemd) image for DigitalOcean

DigitalOcean Custom Images need **cloud-init ≥ 0.7.7**, **sshd on boot**, **BIOS boot**, **ext3/ext4**, and **ConfigDrive before NoCloud**.

Work **on the running LFS system** (or in chroot) as root.

---

## 0. Image must already satisfy DO hardware rules

Before cloud-init:

- Partition table **MBR or GPT**, bootloader **GRUB BIOS** (`i386-pc`). **UEFI is rejected.**
- Root filesystem **ext4** (or ext3).
- Kernel has **virtio-blk, virtio-net, virtio-pci, ext4, iso9660, vfat, serial console**.
- Serial on the kernel command line, e.g. `console=ttyS0,115200n8 console=tty0`.
- `sshd` enabled: `systemctl enable sshd`.
- No static IP left in `/etc/systemd/network/*.network` that will fight DHCP.

---

## 1. Python runtime deps

LFS already has Python 3 and setuptools. Install these modules (BLFS-style `pip3`, or from BLFS):

```text
jinja2  MarkupSafe
configobj
PyYAML
requests  urllib3  certifi  charset-normalizer  idna
oauthlib
jsonpatch  jsonpointer
jsonschema
```

Pin **jsonschema ≤ 4.17.x**. Newer jsonschema pulls `rpds-py` (Rust). Do **not** `pip install cloud-init` from PyPI; upstream is not meant to be used that way.

Also useful (optional but recommended):

- `iproute2` (LFS) + **systemd-networkd**
- `e2fsprogs` (`resize2fs`)
- `util-linux` (`sfdisk`) so the growpart module can expand the partition

---

## 2. Build and install cloud-init from source

LFS 13.1 already has **meson** and **ninja**. Use a current stable tag (anything ≥ 0.7.7; 24.x / 25.x is fine).

```bash
# example: tarball or git tag
cd /sources
tar xf cloud-init-25.2.tar.gz
cd cloud-init-25.2

meson setup build -Dinit_system=systemd
meson compile -C build
meson install -C build
```

Confirm:

```bash
cloud-init --version
```

Units should land under `/usr/lib/systemd/system/` (`cloud-init-local.service`, `cloud-init.service` or `cloud-init-main.service` / `cloud-init-network.service` depending on version, `cloud-config.service`, `cloud-final.service`) plus a generator in `/usr/lib/systemd/system-generators/`.

Enable the stack (names vary slightly by version; enable what was installed):

```bash
systemctl daemon-reload
systemctl enable cloud-init-local.service \
                 cloud-init.service \
                 cloud-config.service \
                 cloud-final.service
# if present instead of cloud-init.service:
# systemctl enable cloud-init-main.service cloud-init-network.service
```

---

## 3. Configure for DigitalOcean (this is the important part)

DO applies metadata via **ConfigDrive**. If **NoCloud is listed first**, the Droplet comes up with a broken network and no SSH key.

Create `/etc/cloud/cloud.cfg.d/99-digitalocean.cfg`:

```yaml
# Datasource order: ConfigDrive MUST be before NoCloud.
datasource_list: [ ConfigDrive, DigitalOcean, None, NoCloud ]

disable_root: false
ssh_pwauth: false
ssh_deletekeys: true
ssh_genkeytypes: [rsa, ecdsa, ed25519]

users:
  - default

# LFS has no apt/yum. Keep only modules that work without a package manager.
cloud_init_modules:
  - seed_random
  - bootcmd
  - write_files
  - growpart
  - resizefs
  - disk_setup
  - mounts
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - users_groups
  - ssh

cloud_config_modules:
  - set_passwords
  - timezone
  - runcmd

cloud_final_modules:
  - scripts_user
  - ssh_authkey_fingerprints
  - keys_to_console
  - final_message

system_info:
  distro: debian          # generic Linux class; package modules unused
  default_user:
    name: lfs
    lock_passwd: true
    gecos: LFS
    groups: [wheel]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  network:
    renderers: [networkd]
    activators: [networkd]
  ssh_svcname: sshd
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
```

If a packaged `/etc/cloud/cloud.cfg` already has `datasource_list`, either delete that line there or keep this drop-in last (`99-`).

Create the default user group if needed (`groupadd -f wheel`) and allow passwordless sudo for `wheel` if you want the default user to work.

---

## 4. Networking

Use **systemd-networkd** only. Remove leftover LFS static configs.

`/etc/systemd/network/20-dhcp.network` as a fallback (cloud-init will rewrite this on first boot from ConfigDrive):

```ini
[Match]
Name=en* eth*

[Network]
DHCP=yes
```

```bash
systemctl enable systemd-networkd systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
# or /run/systemd/resolve/resolv.conf if you prefer
```

Do **not** enable a second DHCP client that fights networkd.

---

## 5. SSH

`/etc/ssh/sshd_config` (minimum):

```text
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
```

```bash
systemctl enable sshd
```

DO will not let you reset the root password from the panel on custom images. You **must** attach an SSH key when creating the Droplet. Cloud-init writes that key to `root` and/or the default user.

---

## 6. Disk grow on first boot

Droplet disk is often larger than the uploaded image. Keep `growpart` and `resizefs` enabled (already in the cfg above).

`/etc/fstab` should use **UUID or LABEL**, not a raw `/dev/vda1` that might shift. Root should be allowed to grow (`resize2fs` works on ext4).

---

## 7. Sanitize before you image (do this last)

```bash
systemctl stop sshd || true
cloud-init clean --logs --seed --machine-id

rm -rf /var/lib/cloud/*
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# drop host-specific state
rm -f /etc/hostname
echo localhost > /etc/hostname
rm -rf /root/.ssh /home/*/.ssh
journalctl --rotate; journalctl --vacuum-time=1s
history -c; rm -f /root/.bash_history
```

`cloud-init clean` is required so the first Droplet boot is treated as a new instance.

Power off. Do not boot this disk again except as a Droplet / test VM.

---

## 8. Export and upload

From the host that holds the raw disk:

```bash
# raw is accepted; qcow2 is smaller to upload
qemu-img convert -O qcow2 -c lfs.img lfs-do.qcow2
# or gzip the raw image
```

Accepted: raw `.img` (MBR/GPT), qcow2, VHDX, VDI, VMDK; gzip/bzip2 OK; ≤ 100 GB uncompressed. ISO is **not** accepted.

Control panel → **Backups & Snapshots** → **Custom Images** → upload or import from URL → create a Droplet from that image → **attach an SSH key**.

---

## 9. First-boot check

```bash
cloud-init status --wait
cat /run/cloud-init/status.json
cloud-init query ds
# expect ConfigDrive (or DigitalOcean on older cloud-init)
ss -lntp | grep sshd
```

If networking is dead: datasource order is wrong, or NoCloud leftover seed files exist under `/var/lib/cloud`. Fix, `cloud-init clean --logs --seed`, recapture the image.

---

### What you can ignore on LFS

Package modules (`package_update`, `packages`, apt/yum) will not work. User-data `runcmd` / `write_files` / SSH keys / hostname / growpart **will**. That is enough for DigitalOcean.
