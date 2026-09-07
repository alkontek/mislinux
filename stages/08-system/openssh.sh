# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# OpenSSH-10.5p1 (systemd, BLFS).

pkg_name=openssh
pkg_version=10.5p1
pkg_tarball=openssh-10.5p1.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="openssl zlib"

pkg_pre_configure() {
  command -v openssl >/dev/null 2>&1 || die "openssh needs openssl (08-system/openssl)"
  [[ -f /usr/include/openssl/ssl.h || -f ${LFS}/usr/include/openssl/ssl.h ]] || \
    die "openssh needs openssl headers"
  [[ -e /usr/lib/libcrypto.so || -e ${LFS}/usr/lib/libcrypto.so ]] || \
    die "openssh needs libcrypto"
  [[ -f /usr/include/zlib.h || -f ${LFS}/usr/include/zlib.h ]] || \
    die "openssh needs zlib headers"
}

pkg_configure() {
  # Providers, not ENGINE. OpenSSL 4.0.1 has no openssl/engine.h.
  ./configure --prefix=/usr \
              --sysconfdir=/etc/ssh \
              --with-privsep-path=/var/lib/sshd \
              --with-default-path=/usr/bin \
              --with-superuser-path=/usr/sbin:/usr/bin \
              --with-pid-dir=/run \
              --without-ssl-engine
}

pkg_build() { make ${MISL_MAKEFLAGS:-}; }

pkg_install() {
  local dest
  dest=$(misl_dest)
  if [[ -n $dest ]]; then
    make DESTDIR="$dest" install
    install -v -m755 contrib/ssh-copy-id "${dest}/usr/bin"
    install -v -m644 contrib/ssh-copy-id.1 "${dest}/usr/share/man/man1" 2>/dev/null || true
  else
    make install
    install -v -m755 contrib/ssh-copy-id /usr/bin
    install -v -m644 contrib/ssh-copy-id.1 /usr/share/man/man1 2>/dev/null || true
  fi

  install -v -g sys -m700 -d "${dest}/var/lib/sshd"
  install -v -m755 -d "${dest}/usr/share/doc/openssh-10.5p1"
  install -v -m644 INSTALL LICENCE OVERVIEW README* \
    "${dest}/usr/share/doc/openssh-10.5p1" 2>/dev/null || true

  if ! grep -q '^sshd:' "${dest}/etc/passwd" 2>/dev/null; then
    printf '%s\n' "sshd:x:50:50:sshd PrivSep:/var/lib/sshd:/usr/bin/false" \
      >> "${dest}/etc/passwd"
  fi
  if ! grep -q '^sshd:' "${dest}/etc/group" 2>/dev/null; then
    printf '%s\n' "sshd:x:50:" >> "${dest}/etc/group"
  fi

  mkdir -pv "${dest}/etc/ssh" "${dest}/usr/lib/systemd/system"
  if [[ -f ${dest}/etc/ssh/sshd_config ]]; then
    grep -q '^PasswordAuthentication' "${dest}/etc/ssh/sshd_config" || \
      printf '%s\n' 'PasswordAuthentication yes' >> "${dest}/etc/ssh/sshd_config"
    grep -q '^PermitRootLogin' "${dest}/etc/ssh/sshd_config" || \
      printf '%s\n' 'PermitRootLogin yes' >> "${dest}/etc/ssh/sshd_config"
    grep -q '^UsePAM' "${dest}/etc/ssh/sshd_config" || \
      printf '%s\n' 'UsePAM no' >> "${dest}/etc/ssh/sshd_config"
  fi

  cat > "${dest}/usr/lib/systemd/system/sshd.service" <<'EOF'
[Unit]
Description=OpenSSH server daemon
Documentation=man:sshd(8) man:sshd_config(5)
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStart=/usr/sbin/sshd -D -e
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

  if command -v systemctl >/dev/null 2>&1 && misl_in_chroot 2>/dev/null; then
    systemctl enable sshd.service || true
  elif [[ -d ${dest}/etc/systemd/system/multi-user.target.wants ]]; then
    ln -sfn /usr/lib/systemd/system/sshd.service \
      "${dest}/etc/systemd/system/multi-user.target.wants/sshd.service"
  fi

  [[ -x ${dest}/usr/sbin/sshd ]] || die "sshd missing after install"
}
