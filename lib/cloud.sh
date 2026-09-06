# SPDX-FileCopyrightText: 2026 ALKONTEK <git@alkontek.com>
# SPDX-License-Identifier: BSD-2-Clause

# shellcheck shell=bash
# Cloud overlay helpers. cloud-init is incoming/, not packages.manifest.

_misl_cloud_version() { printf '%s\n' "${MISL_CLOUD_INIT_VERSION:-26.2}"; }
_misl_cloud_tarball() { printf 'cloud-init-%s.tar.gz\n' "$(_misl_cloud_version)"; }
_misl_cloud_user() { printf '%s\n' "${MISL_CLOUD_USER:-root}"; }

misl_cloud_incoming_dir() {
  printf '%s/incoming\n' "${MISL_SNAPSHOT:?}"
}

misl_cloud_report_path() {
  require_lfs_set
  printf '%s/var/lib/misl/cloud.report\n' "${LFS%/}"
}

misl_cloud_dest() {
  require_lfs_set
  if [[ ${LFS:-} == / ]]; then
    printf '\n'
  else
    printf '%s\n' "${LFS%/}"
  fi
}

# Host only. Every cloud row of config/incoming.manifest (cloud-init
# tarball and its wheels) from $MISL_MIRROR/incoming/, md5-checked,
# staged into SOURCES and $LFS/usr/src/misl/SOURCES.
misl_cloud_fetch() {
  [[ ${MISL_FETCH:-1} == 1 ]] || die "fetch disabled (MISL_FETCH=0); agent sessions must leave fetch off"
  if [[ ${LFS:-} == / ]]; then
    die "cloud fetch runs on the Fedora host (needs wget). exit the chroot first"
  fi
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  if [[ ${1:-0} == 1 ]]; then
    rm -f "$(misl_cloud_incoming_dir)/$(_misl_cloud_tarball)"
  fi
  misl_incoming_fetch cloud
  misl_incoming_check cloud || die "cloud incoming files missing or wrong md5 (see above)"
  misl_incoming_stage "${MISL_SOURCES:?}" cloud
  misl_incoming_stage "$LFS/usr/src/misl/SOURCES" cloud
  info "cloud incoming staged in $LFS/usr/src/misl/SOURCES"
}

misl_cloud_write_base_cfg() {
  local dest=$1 cfg
  mkdir -p "${dest}/etc/cloud/cloud.cfg.d" \
           "${dest}/etc/cloud/templates" \
           "${dest}/var/lib/cloud"
  cfg=${dest}/etc/cloud/cloud.cfg.d/90-misl-cloud.cfg
  cat >"$cfg" <<EOF
# Generic cloud overlay. Provider overlays add their own drop-in after this.
datasource_list: [ ConfigDrive, NoCloud, None ]

disable_root: false
ssh_pwauth: false
ssh_deletekeys: true
ssh_genkeytypes: [rsa, ecdsa, ed25519]

users:
  - default

# OpenSSH has no PAM. "!" in shadow blocks pubkey.
lock_passwd: false

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
  distro: debian
  default_user:
    name: root
    lock_passwd: false
    gecos: root
    shell: /bin/bash
  network:
    renderers: [networkd]
    activators: [networkd]
  ssh_svcname: sshd
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
EOF
  printf '%s\n' "$cfg"
}

misl_cloud_write_do_cfg() {
  local dest=$1 cfg
  mkdir -p "${dest}/etc/cloud/cloud.cfg.d" \
           "${dest}/etc/cloud/templates" \
           "${dest}/var/lib/cloud" \
           "${dest}/etc/sudoers.d" \
           "${dest}/etc/systemd/network" \
           "${dest}/etc/ssh" \
           "${dest}/usr/lib/systemd/system"
  cfg=${dest}/etc/cloud/cloud.cfg.d/99-digitalocean.cfg
  cat >"$cfg" <<EOF
# Datasource order: ConfigDrive MUST be before NoCloud (DigitalOcean).
datasource_list: [ ConfigDrive, DigitalOcean, None, NoCloud ]

disable_root: false
ssh_pwauth: false
ssh_deletekeys: true
ssh_genkeytypes: [rsa, ecdsa, ed25519]

users:
  - default

lock_passwd: false

# No apt/dnf. Keep modules that work on a source-built MISL.
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
  distro: debian
  default_user:
    name: root
    lock_passwd: false
    gecos: root
    shell: /bin/bash
  network:
    renderers: [networkd]
    activators: [networkd]
  ssh_svcname: sshd
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
EOF
  printf '%s\n' "$cfg"
}

misl_cloud_write_network() {
  local dest=$1 f=${1}/etc/systemd/network/20-dhcp.network
  mkdir -p "$(dirname "$f")"
  cat >"$f" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
UseDomains=true
EOF
  printf '%s\n' "$f"
}

misl_cloud_tune_sshd() {
  local dest=$1 main=${1}/etc/ssh/sshd_config
  local f=${1}/etc/ssh/sshd_config.d/99-misl-cloud.conf
  mkdir -p "$(dirname "$f")"
  if [[ -f $main ]] && ! grep -q 'sshd_config\.d' "$main"; then
    printf '%s\n' 'Include /etc/ssh/sshd_config.d/*.conf' >>"$main"
  fi
  printf '%s\n' \
    'PermitRootLogin prohibit-password' \
    'PasswordAuthentication no' \
    'KbdInteractiveAuthentication no' \
    'PubkeyAuthentication yes' \
    'AuthorizedKeysFile .ssh/authorized_keys' \
    'UsePAM no' >"$f"
  # systemd ships this; userdbctl hides /etc/passwd users. Removed
  # (one-way; misl reset restores it from the snapshot).
  rm -f "${dest}/etc/ssh/sshd_config.d/20-systemd-userdb.conf"
  if [[ -f $main ]]; then
    sed -i -E 's/^[[:space:]]*UsePAM.*/UsePAM no/' "$main"
    grep -q '^UsePAM' "$main" || printf '%s\n' 'UsePAM no' >>"$main"
  fi
  printf '%s\n' "$f"
}

# No PAM: "!" in shadow refuses pubkey. "*" is "no password".
# Do not wrap useradd; cloud-init lock_passwd:false plus root * is enough.
misl_cloud_star_locked() {
  local dest=$1 shadow=${1}/etc/shadow
  [[ -f $shadow ]] || return 0
  if grep -q '^root:!' "$shadow"; then
    sed -i 's/^root:!:/root:*:/' "$shadow"
  fi
}

misl_cloud_write_sudoers() {
  local dest=$1 f=${1}/etc/sudoers.d/wheel
  mkdir -p "$(dirname "$f")"
  printf '%s\n' '%wheel ALL=(ALL) NOPASSWD:ALL' >"$f"
  chmod 0440 "$f"
  printf '%s\n' "$f"
}

misl_cloud_ensure_user_group() {
  local dest=$1
  mkdir -p "${dest}/etc" "${dest}/root/.ssh"
  chmod 0700 "${dest}/root/.ssh"
  if [[ -f ${dest}/etc/group ]] && ! grep -q '^wheel:' "${dest}/etc/group"; then
    printf '%s\n' 'wheel:x:97:' >>"${dest}/etc/group"
  fi
  # Drop the stock cloud user from earlier 0.3 images (uid 1000, gecos MIS Linux).
  if [[ -f ${dest}/etc/passwd ]] && grep -q '^misl:x:1000:1000:MIS Linux:' "${dest}/etc/passwd"; then
    sed -i '/^misl:/d' "${dest}/etc/passwd"
    [[ -f ${dest}/etc/shadow ]] && sed -i '/^misl:/d' "${dest}/etc/shadow"
    [[ -f ${dest}/etc/group ]] && sed -i '/^misl:/d' "${dest}/etc/group"
    if [[ -f ${dest}/etc/group ]]; then
      sed -i '/^wheel:/s/,misl,/,/g; /^wheel:/s/,misl$//; /^wheel:/s/:misl,/:/; /^wheel:/s/:misl$/:/' "${dest}/etc/group"
    fi
    rm -rf "${dest}/home/misl"
  fi
}

misl_cloud_write_do_sshkeys() {
  local dest=$1 script unit wants
  script=${dest}/usr/lib/misl/do-ssh-keys
  unit=${dest}/usr/lib/systemd/system/misl-do-sshkeys.service
  mkdir -p "${dest}/usr/lib/misl" "${dest}/usr/lib/systemd/system"
  cat >"$script" <<'EOF'
#!/usr/bin/python3
"""Copy DigitalOcean metadata SSH keys to root."""
import os
import urllib.request

URL = "http://169.254.169.254/metadata/v1/public-keys"
HOMES = ["/root"]

def fetch():
    try:
        with urllib.request.urlopen(URL, timeout=8) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception:
        return []
    return [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.startswith("#")]

def merge(path, keys):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    have = set()
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            have = {ln.strip() for ln in f if ln.strip()}
    new = [k for k in keys if k not in have]
    if not new:
        return
    with open(path, "a", encoding="utf-8") as f:
        for k in new:
            f.write(k + "\n")
    os.chmod(path, 0o600)

keys = fetch()
if not keys:
    raise SystemExit(0)
for h in HOMES:
    merge(os.path.join(h, ".ssh", "authorized_keys"), keys)
    try:
        st = os.stat(h)
        sshd = os.path.join(h, ".ssh")
        os.chown(sshd, st.st_uid, st.st_gid)
        ak = os.path.join(sshd, "authorized_keys")
        if os.path.isfile(ak):
            os.chown(ak, st.st_uid, st.st_gid)
    except OSError:
        pass
EOF
  chmod 0755 "$script"
  cat >"$unit" <<'EOF'
[Unit]
Description=Install SSH keys from DigitalOcean metadata
After=network-online.target
Wants=network-online.target
Before=sshd.service

[Service]
Type=oneshot
ExecStart=/usr/lib/misl/do-ssh-keys
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  wants=${dest}/etc/systemd/system/multi-user.target.wants
  mkdir -p "$wants"
  ln -sfn /usr/lib/systemd/system/misl-do-sshkeys.service \
    "$wants/misl-do-sshkeys.service"
  printf '%s\n' "$script"
}

misl_cloud_enable_units() {
  local dest=$1 wants unit
  wants=${dest}/etc/systemd/system/multi-user.target.wants
  mkdir -p "$wants" \
            "${dest}/etc/systemd/system/sysinit.target.wants" \
            "${dest}/etc/systemd/system/cloud-init.target.wants"
  for unit in cloud-init-local.service cloud-init-network.service \
              cloud-init.service cloud-init-main.service \
              cloud-config.service cloud-final.service \
              sshd.service systemd-networkd.service systemd-resolved.service \
              systemd-networkd-wait-online.service; do
    if [[ -f ${dest}/usr/lib/systemd/system/$unit ]]; then
      ln -sfn "/usr/lib/systemd/system/$unit" "$wants/$unit"
      case $unit in
        cloud-*) _misl_cloud_list "$dest" "$wants/$unit" ;;
      esac
    fi
  done
  if [[ -d ${dest}/etc/systemd/system/multi-user.target.wants ]]; then
    ln -sfn /usr/lib/systemd/system/systemd-networkd.service \
      "$wants/systemd-networkd.service" 2>/dev/null || true
  fi
  # DigitalOcean recovery console is serial.
  mkdir -p "${dest}/etc/systemd/system/getty.target.wants"
  if [[ -f ${dest}/usr/lib/systemd/system/serial-getty@.service ]]; then
    ln -sfn /usr/lib/systemd/system/serial-getty@.service \
      "${dest}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
    _misl_cloud_list "$dest" \
      "${dest}/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
  fi
}

_misl_cloud_list() {
  local dest=$1 path=$2
  [[ -n ${MISL_CLOUD_REPORT:-} ]] && \
    misl_report_item "$MISL_CLOUD_REPORT" "$(misl_report_relpath "$dest" "$path")"
  misl_overlay_own "$path"
}

# Why cloud is one-way (used by the undo refusal).
misl_cloud_oneway_why() {
  printf '%s' "it edits /etc/passwd, /etc/shadow, /etc/group, /etc/ssh/sshd_config, /etc/resolv.conf and sudoers in place, and misl keeps no exact record of the old contents."
}

# Printed by overlay apply before cloud (or cloud/do) is applied.
misl_cloud_notice() {
  cat >&2 <<'EOF'
==> NOTICE: cloud is a one-way overlay. Applying it edits the tree in place:
      /etc/passwd /etc/shadow /etc/group  wheel group added; root '!' becomes '*'
                                          (key login, no password); an old 0.3
                                          'misl' user and /home/misl are removed
      /etc/ssh/sshd_config                Include sshd_config.d, UsePAM no
      /etc/ssh/sshd_config.d              99-misl-cloud.conf added (no password
                                          login); 20-systemd-userdb.conf removed
      /etc/sudoers.d/wheel                %wheel ALL=(ALL) NOPASSWD:ALL
      /etc/resolv.conf                    link to systemd-resolved (if missing
                                          or already a link)
      /etc/cloud, /etc/systemd/network    cloud-init config, DHCP on en*/eth*
      /etc/systemd/system/*.wants         sshd, networkd, resolved, cloud-init,
                                          serial-getty@ttyS0 enabled
      /root/.ssh                          created, mode 0700
      cloud/do also adds /usr/lib/misl/do-ssh-keys and misl-do-sshkeys.service.
    These edits cannot be undone: ./misl overlay undo cloud refuses.
    The way back is ./misl reset (restores the snapshot taken before the
    first overlay apply; ./misl reset --info) or a rebuild.
EOF
}

misl_overlay_cloud_apply() {
  require_lfs_set
  local dest report f
  dest=$(misl_cloud_dest)
  report=$(misl_cloud_report_path)
  MISL_CLOUD_REPORT=$report
  export MISL_CLOUD_REPORT
  mkdir -p "$(dirname "$report")"
  if [[ ! -f $report ]]; then
    misl_report_begin "$report" "overlay apply"
    misl_report_kv "$report" when "$(date -u +%FT%TZ)"
    misl_report_kv "$report" LFS "$LFS"
    misl_report_kv "$report" cloud-init "$(_misl_cloud_version)"
    misl_report_section "$report" files
  fi
  f=$(misl_cloud_write_base_cfg "$dest")
  _misl_cloud_list "$dest" "$f"
  f=$(misl_cloud_write_network "$dest")
  _misl_cloud_list "$dest" "$f"
  f=$(misl_cloud_tune_sshd "$dest")
  _misl_cloud_list "$dest" "$f"
  f=$(misl_cloud_write_sudoers "$dest")
  _misl_cloud_list "$dest" "$f"
  misl_cloud_star_locked "$dest"
  misl_cloud_ensure_user_group "$dest"
  misl_cloud_enable_units "$dest"
  mkdir -p "${dest}/var/lib/misl"
  if [[ -L ${dest}/etc/resolv.conf || ! -e ${dest}/etc/resolv.conf ]]; then
    ln -sfn /run/systemd/resolve/resolv.conf "${dest}/etc/resolv.conf"
  fi
}

misl_overlay_do_apply() {
  local dest report f
  dest=$(misl_cloud_dest)
  report=$(misl_cloud_report_path)
  MISL_CLOUD_REPORT=$report
  export MISL_CLOUD_REPORT
  f=$(misl_cloud_write_do_cfg "$dest")
  _misl_cloud_list "$dest" "$f"
  f=$(misl_cloud_write_do_sshkeys "$dest")
  _misl_cloud_list "$dest" "$f"
  _misl_cloud_list "$dest" "${dest}/usr/lib/systemd/system/misl-do-sshkeys.service"
  _misl_cloud_list "$dest" \
    "${dest}/etc/systemd/system/multi-user.target.wants/misl-do-sshkeys.service"
}

misl_cloud_configure() {
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  local dest report
  dest=$(misl_cloud_dest)
  report=$(misl_cloud_report_path)
  MISL_CLOUD_REPORT=$report
  export MISL_CLOUD_REPORT
  misl_report_begin "$report" "cloud apply"
  misl_report_kv "$report" when "$(date -u +%FT%TZ)"
  misl_report_kv "$report" LFS "$LFS"
  misl_report_kv "$report" cloud-init "$(_misl_cloud_version)"
  misl_report_kv "$report" user "$(_misl_cloud_user)"
  misl_report_section "$report" files
  misl_overlay_cloud_apply
  misl_overlay_do_apply
  misl_report_section "$report" next
  misl_report_item "$report" "./misl enter"
  misl_report_item "$report" "MISL_FORCE=1 ./misl build 10-boot/linux"
  misl_report_item "$report" "./misl cloud install"
}

# Pinned wheel files (cloud rows, kind=wheel) as paths under incoming/
# (wheels/<name>.whl), one per line.
misl_cloud_wheel_files() {
  misl_incoming_wanted cloud | awk -F'\t' '$5 == "wheel" { print $2 }'
}

# Root pip into /usr from the staged wheel set only: --no-index, the
# exact files config/incoming.manifest names. jsonschema stays <4.18 so
# it does not need rpds-py (Rust). Jinja2/MarkupSafe are base packages.
misl_cloud_pip_deps() {
  require_cmd python3
  local src=${MISL_CLOUD_SOURCES:-/usr/src/misl/SOURCES} dir f files=() missing=()
  dir=$src/wheels
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    if [[ -f $src/$f ]]; then
      files+=("$src/$f")
    else
      missing+=("$(basename "$f")")
    fi
  done <<<"$(misl_cloud_wheel_files)"
  if (( ${#missing[@]} )); then
    die "cloud-init wheels missing in $dir: ${missing[*]}. on the host: ./misl cloud fetch (mirror incoming/)"
  fi
  (( ${#files[@]} )) || die "no kind=wheel cloud rows in $(misl_incoming_manifest)"
  python3 -m pip --version >/dev/null 2>&1 || \
    die "python3 has no pip (08-system python installs it with ensurepip); rebuild 08-system/python"
  info "pip install --no-index --find-links $dir --prefix /usr (${#files[@]} wheels)"
  python3 -m pip install --prefix /usr --no-index --find-links "$dir" \
    --no-cache-dir --root-user-action=ignore "${files[@]}"
}

misl_cloud_install() {
  require_lfs_set
  [[ ${LFS:-} == / ]] || die "cloud install runs inside the chroot (LFS=/). ./misl enter first"
  require_cmd meson ninja python3 tar
  misl_cloud_pip_deps
  local name srcdir build tarball
  name=$(_misl_cloud_tarball)
  tarball=/usr/src/misl/SOURCES/$name
  [[ -f $tarball ]] || die "missing $tarball. on the host: ./misl cloud fetch (cloud apply runs it too)"
  srcdir=/usr/src/misl/build/cloud-init-$(_misl_cloud_version)
  rm -rf "$srcdir"
  mkdir -p "$srcdir"
  tar -xf "$tarball" -C "$srcdir" --strip-components=1
  build=$srcdir/build
  (
    cd "$srcdir"
    meson setup build --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
      -Dinit_system=systemd -Dbash_completion=false
    meson compile -C build
    meson install -C build
  )
  export PATH=/usr/bin:/usr/sbin:/usr/local/bin
  if [[ ! -x /usr/bin/cloud-init && ! -x /usr/local/bin/cloud-init ]]; then
    die "cloud-init missing after meson install"
  fi
  cloud-init --version || /usr/bin/cloud-init --version || true
  misl_cloud_enable_units ""
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    for unit in cloud-init-local.service cloud-init-network.service \
                cloud-init.service cloud-init-main.service \
                cloud-config.service cloud-final.service sshd.service \
                systemd-networkd.service systemd-resolved.service; do
      [[ -f /usr/lib/systemd/system/$unit ]] || continue
      systemctl enable "$unit" || true
    done
  fi
  mkdir -p /var/lib/misl
  misl_report_section /var/lib/misl/cloud.report installed
  misl_report_kv /var/lib/misl/cloud.report version "$(cloud-init --version 2>/dev/null | head -1)"
  info "cloud-init installed"
}

misl_cloud_sanitize() {
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  local dest
  dest=$(misl_cloud_dest)
  if command -v cloud-init >/dev/null 2>&1 && [[ ${LFS:-} == / ]]; then
    cloud-init clean --logs --seed --machine-id || true
  fi
  rm -rf "${dest}/var/lib/cloud/"*
  rm -f "${dest}/etc/ssh/ssh_host_"*
  mkdir -p "${dest}/etc" "${dest}/var/lib/dbus"
  printf 'uninitialized\n' >"${dest}/etc/machine-id"
  rm -f "${dest}/var/lib/dbus/machine-id"
  ln -sfn /etc/machine-id "${dest}/var/lib/dbus/machine-id"
  printf 'localhost\n' >"${dest}/etc/hostname"
  rm -rf "${dest}/root/.ssh" "${dest}/home/"*/.ssh
  rm -f "${dest}/root/.bash_history"
  info "sanitized $dest for imaging (new machine-id, no host keys)"
}

misl_cloud_status() {
  require_lfs_set
  local f
  f=$(misl_cloud_report_path)
  if [[ -f $f ]]; then
    cat "$f"
  else
    die "no cloud report at $f — run: ./misl cloud apply"
  fi
}

misl_cloud_apply() {
  local force=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      --reinstall|--force) force=1; shift ;;
      -h|--help)
        printf '%s\n' "usage: misl cloud apply|undo|install|status|sanitize|fetch"
        printf '%s\n' "  cloud apply is overlay apply cloud do"
        return 0
        ;;
      *) break ;;
    esac
  done
  require_lfs_set
  [[ -d $LFS ]] || die "LFS=$LFS is not a directory"
  if [[ ${LFS:-} == / ]]; then
    die "cloud apply runs on the Fedora host. exit the chroot first"
  fi
  misl_overlay_apply cloud/do
  misl_cloud_status || true
}

misl_cloud() {
  local sub=${1:-status}
  shift || true
  case $sub in
    apply) misl_cloud_apply "$@" ;;
    undo|revert) misl_overlay_oneway_refuse cloud ;;
    fetch) misl_cloud_fetch "${1:-0}" ;;
    install) misl_cloud_install ;;
    sanitize) misl_cloud_sanitize ;;
    status|show|"") misl_cloud_status ;;
    *) die "usage: misl cloud apply|undo|install|status|sanitize|fetch" ;;
  esac
}
