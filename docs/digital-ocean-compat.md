<!-- SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

DigitalOcean lets you upload your own disk image and create Droplets from it.
The feature is called **Custom Images**.

It is **not** "boot from an installer ISO" the way some other providers work.
You upload a prepared virtual disk, then start Droplets from that image.

### What you can upload
- **OS:** Unix-like only (Linux, FreeBSD-style, etc.). Windows is **not** supported.
- **Formats:** raw (`.img` with MBR or GPT), qcow2, VHDX, VDI, VMDK
- Compression with gzip or bzip2 is allowed
- Max size: **100 GB uncompressed**
- Filesystem: **ext3 or ext4**
- Must boot via **BIOS** (UEFI is not supported)
- Must include working **cloud-init** (0.7.7+) or an equivalent such as
- cloudbase-init, coreos-cloudinit, ignition, or bsd-cloudinit
- Must have **sshd** enabled on boot

ISO files are not accepted directly.
* Convert the installation into one of the disk formats above first.

### How to upload
1. Control panel → **Backups & Snapshots** → **Custom Images**
2. Upload a file, or import via HTTP/HTTPS/FTP URL
3. Pick a name, distribution label, and region

You can also import via the API or `doctl`.
For large files, upload to Spaces (or another public URL) and import from that URL;
browser uploads are limited.

After the image is processed, create a Droplet and choose it under **Custom Images**.
You can later copy the image to other regions.

Official docs: [How to Upload Custom Images](https://docs.digitalocean.com/products/custom-images/how-to/upload/) and [Custom Images limits](https://docs.digitalocean.com/products/custom-images/details/limits/).
