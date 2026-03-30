#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUNDLE_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
PKG_DIR="${BUNDLE_ROOT}/packages"
CFG_DIR="${BUNDLE_ROOT}/config"
MNF_DIR="${BUNDLE_ROOT}/manifest"
VERIFY_SCRIPT="${SCRIPT_DIR}/verify.sh"
DAEMON_DIR="/etc/docker"
SYSTEMD_DROPIN_DIR="/etc/systemd/system/docker.service.d"

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die "please run as root"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

check_platform() {
  [[ -r /etc/os-release ]] || die "cannot detect operating system"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "target host must be Ubuntu"
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "target host must be Ubuntu 24.04"

  local arch
  arch=$(dpkg --print-architecture)
  [[ "${arch}" == "amd64" || "${arch}" == "arm64" ]] || die "unsupported architecture: ${arch}"
}

verify_bundle() {
  [[ -d "${PKG_DIR}" ]] || die "missing packages directory: ${PKG_DIR}"
  compgen -G "${PKG_DIR}/*.deb" >/dev/null || die "no deb packages found in ${PKG_DIR}"

  if [[ -f "${MNF_DIR}/sha256sum.txt" ]]; then
    log "verifying file checksums"
    (
      cd "${BUNDLE_ROOT}"
      sha256sum -c manifest/sha256sum.txt
    )
  else
    log "manifest/sha256sum.txt not found, skipping checksum verification"
  fi
}

install_packages() {
  local debs=("${PKG_DIR}"/*.deb)
  log "installing ${#debs[@]} packages"

  if ! apt-get install -y "${debs[@]}"; then
    log "apt-get local install failed, retrying with dpkg"
    dpkg -i "${debs[@]}" || die "package installation failed, ensure the bundle contains a complete dependency closure"
  fi
}

install_config() {
  mkdir -p "${DAEMON_DIR}" "${SYSTEMD_DROPIN_DIR}"

  if [[ -f "${CFG_DIR}/daemon.json" ]]; then
    install -m 0644 "${CFG_DIR}/daemon.json" "${DAEMON_DIR}/daemon.json"
  fi

  if [[ -f "${CFG_DIR}/docker.service.d/override.conf" ]]; then
    install -m 0644 "${CFG_DIR}/docker.service.d/override.conf" "${SYSTEMD_DROPIN_DIR}/override.conf"
  fi
}

start_services() {
  log "reloading systemd units"
  systemctl daemon-reload

  if systemctl list-unit-files | grep -q '^containerd\.service'; then
    systemctl enable --now containerd
  fi

  systemctl enable docker
  systemctl restart docker
}

show_post_install_notes() {
  cat <<'EOF'
[INFO] installation finished
[INFO] if you plan to use a non-root account, add it to the docker group:
[INFO]   usermod -aG docker <user>
[INFO] then re-login to refresh the group membership
EOF
}

main() {
  require_root
  require_cmd apt-get
  require_cmd dpkg
  require_cmd systemctl
  require_cmd sha256sum

  check_platform
  verify_bundle
  install_packages
  install_config
  start_services

  if [[ -x "${VERIFY_SCRIPT}" ]]; then
    "${VERIFY_SCRIPT}"
  fi

  show_post_install_notes
}

main "$@"
