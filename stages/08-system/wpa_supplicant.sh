# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# wpa_supplicant-2.12: Wi-Fi client; nl80211 via libnl-3, OpenSSL, D-Bus.

pkg_name=wpa_supplicant
pkg_version=2.12
pkg_tarball=wpa_supplicant-2.12.tar.gz
pkg_patches=
pkg_stage=08-system
pkg_pass=1
pkg_builddir=in-tree
pkg_requires="libnl openssl dbus readline"

pkg_pre_configure() {
  [[ -f /usr/include/libnl3/netlink/netlink.h \
     || -f ${LFS}/usr/include/libnl3/netlink/netlink.h ]] || \
    die "wpa_supplicant needs libnl-3 headers (08-system/libnl)"
}

pkg_configure() {
  # Plain-file config + ctrl_iface for wpa_cli; D-Bus for later
  # desktop tools. DBUS_INTRO needs no libxml2: 2.12 builds the
  # introspection XML itself (dbus/dbus_new_introspect.c, wpabuf) and
  # only links pkg-config dbus-1.
  cat > wpa_supplicant/.config <<'CFG'
CONFIG_BACKEND=file
CONFIG_CTRL_IFACE=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_CTRL_IFACE_DBUS_INTRO=y
CONFIG_DEBUG_FILE=y
CONFIG_DEBUG_SYSLOG=y
CONFIG_DEBUG_SYSLOG_FACILITY=LOG_DAEMON
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_DRIVER_WIRED=y
CONFIG_EAP_GTC=y
CONFIG_EAP_LEAP=y
CONFIG_EAP_MD5=y
CONFIG_EAP_MSCHAPV2=y
CONFIG_EAP_OTP=y
CONFIG_EAP_PEAP=y
CONFIG_EAP_TLS=y
CONFIG_EAP_TTLS=y
CONFIG_IEEE8021X_EAPOL=y
CONFIG_IPV6=y
CONFIG_LIBNL32=y
CONFIG_PKCS12=y
CONFIG_READLINE=y
CONFIG_SAE=y
CONFIG_TLS=openssl
CONFIG_WPS=y
CFLAGS += -I/usr/include/libnl3
CFG
}

pkg_build() {
  make -C wpa_supplicant ${MISL_MAKEFLAGS:-} BINDIR=/usr/sbin LIBDIR=/usr/lib
}

pkg_install() {
  local dest
  dest=$(misl_dest)
  cd wpa_supplicant || die "no wpa_supplicant/ in source tree"
  install -v -d -m755 "${dest}/usr/sbin" "${dest}/usr/share/man/man5" \
    "${dest}/usr/share/man/man8" "${dest}/usr/lib/systemd/system" \
    "${dest}/usr/share/dbus-1/system-services" "${dest}/etc/dbus-1/system.d" \
    "${dest}/etc/wpa_supplicant"
  install -v -m755 wpa_cli wpa_passphrase wpa_supplicant "${dest}/usr/sbin/"
  install -v -m644 doc/docbook/wpa_supplicant.conf.5 "${dest}/usr/share/man/man5/"
  install -v -m644 doc/docbook/wpa_cli.8 doc/docbook/wpa_passphrase.8 \
    doc/docbook/wpa_supplicant.8 "${dest}/usr/share/man/man8/"
  # wpa_supplicant@IFACE / -nl80211@ / -wired@ templates. Not enabled:
  # the desktop overlay picks the interface.
  install -v -m644 systemd/*.service "${dest}/usr/lib/systemd/system/"
  install -v -m644 dbus/fi.w1.wpa_supplicant1.service \
    "${dest}/usr/share/dbus-1/system-services/"
  install -v -m644 dbus/dbus-wpa_supplicant.conf \
    "${dest}/etc/dbus-1/system.d/wpa_supplicant.conf"
  [[ -x ${dest}/usr/sbin/wpa_supplicant ]] || die "wpa_supplicant missing after install"
}

# D-Bus must be compiled in and linked. readelf reads NEEDED without
# running the binary, so it works for DESTDIR installs too.
pkg_check() {
  local dest bin dyn
  dest=$(misl_dest)
  bin=${dest}/usr/sbin/wpa_supplicant
  # Read once: `readelf | grep -q` can SIGPIPE readelf and fail under pipefail.
  dyn=$(readelf -d "$bin") || die "readelf -d failed on $bin"
  grep -q 'NEEDED.*libdbus-1\.so' <<<"$dyn" || die "wpa_supplicant not linked to libdbus-1"
  grep -q 'NEEDED.*libnl-3\.so' <<<"$dyn" || die "wpa_supplicant not linked to libnl-3"
  if grep -q 'NEEDED.*libxml2' <<<"$dyn"; then die "wpa_supplicant unexpectedly links libxml2"; fi
  grep -q 'fi\.w1\.wpa_supplicant1' "$bin" || die "no D-Bus interface name in binary"
  [[ -f ${dest}/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service ]] || die "D-Bus service file missing"
  [[ -f ${dest}/etc/dbus-1/system.d/wpa_supplicant.conf ]] || die "D-Bus policy missing"
  for u in wpa_supplicant@ wpa_supplicant-nl80211@ wpa_supplicant-wired@; do
    [[ -f ${dest}/usr/lib/systemd/system/${u}.service ]] || die "missing ${u}.service"
  done
  misl_check_run /usr/sbin/wpa_supplicant -v
}
