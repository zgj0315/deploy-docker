#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
OUT_ROOT=${OUT_ROOT:-"${PROJECT_ROOT}/dist"}
BUNDLE_NAME=${BUNDLE_NAME:-"docker-offline-bundle"}
BUNDLE_DIR="${OUT_ROOT}/${BUNDLE_NAME}"
PKG_DIR="${BUNDLE_DIR}/packages"
CFG_DIR="${BUNDLE_DIR}/config"
DOC_DIR="${BUNDLE_DIR}/docs"
MNF_DIR="${BUNDLE_DIR}/manifest"
SCRIPT_OUT_DIR="${BUNDLE_DIR}/scripts"
VERSION_FILE="${PROJECT_ROOT}/manifest/VERSION"
PACKAGE_LIST_FILE="${PROJECT_ROOT}/manifest/packages.txt"
ARCH=${ARCH:-$(dpkg --print-architecture)}

CORE_PACKAGES=(
  containerd.io
  docker-ce
  docker-ce-cli
  docker-buildx-plugin
  docker-compose-plugin
)

EXTRA_PACKAGES=(
  pigz
  iptables
  iproute2
  xz-utils
  uidmap
  ca-certificates
)

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_build_host() {
  [[ -r /etc/os-release ]] || die "cannot detect operating system"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "build host must be Ubuntu"
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "build host must be Ubuntu 24.04"
  [[ "${ARCH}" == "amd64" || "${ARCH}" == "arm64" ]] || die "unsupported architecture: ${ARCH}"
}

prepare_bundle_tree() {
  rm -rf "${BUNDLE_DIR}"
  mkdir -p "${PKG_DIR}" "${CFG_DIR}" "${DOC_DIR}" "${MNF_DIR}" "${SCRIPT_OUT_DIR}"
  cp -R "${PROJECT_ROOT}/config/." "${CFG_DIR}/"
  cp -R "${PROJECT_ROOT}/docs/." "${DOC_DIR}/"
  cp -R "${PROJECT_ROOT}/scripts/." "${SCRIPT_OUT_DIR}/"
  cp "${VERSION_FILE}" "${MNF_DIR}/VERSION"
}

collect_package_names() {
  local names=("${CORE_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}")
  if command -v apt-rdepends >/dev/null 2>&1; then
    log "collecting package closure via apt-rdepends"
    mapfile -t names < <(
      apt-rdepends "${CORE_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}" 2>/dev/null \
      | awk '/^[A-Za-z0-9][A-Za-z0-9+.-]*$/{print $1}' \
      | sort -u
    )
  else
    warn "apt-rdepends not found, using curated package list only"
  fi

  printf '%s\n' "${names[@]}" | awk 'NF' | sort -u
}

download_packages() {
  local packages=()
  mapfile -t packages < <(collect_package_names)
  [[ ${#packages[@]} -gt 0 ]] || die "package list is empty"

  log "downloading ${#packages[@]} packages"
  (
    cd "${PKG_DIR}"
    apt-get download "${packages[@]}"
  )

  : > "${PACKAGE_LIST_FILE}"
  local pkg_file
  for pkg_file in "${PKG_DIR}"/*.deb; do
    [[ -e "${pkg_file}" ]] || die "no deb files were downloaded"
    dpkg-deb -f "${pkg_file}" Package Version Architecture >> "${PACKAGE_LIST_FILE}"
  done

  sort -u "${PACKAGE_LIST_FILE}" -o "${PACKAGE_LIST_FILE}"
  cp "${PACKAGE_LIST_FILE}" "${MNF_DIR}/packages.txt"
}

generate_checksums() {
  (
    cd "${BUNDLE_DIR}"
    find . -type f ! -path './manifest/sha256sum.txt' -print0 \
      | sort -z \
      | xargs -0 sha256sum > manifest/sha256sum.txt
  )
}

package_bundle() {
  mkdir -p "${OUT_ROOT}"
  tar -C "${OUT_ROOT}" -czf "${OUT_ROOT}/${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"
}

main() {
  require_cmd apt-get
  require_cmd dpkg
  require_cmd dpkg-deb
  require_cmd sha256sum
  require_cmd tar

  ensure_build_host
  prepare_bundle_tree
  download_packages
  generate_checksums
  package_bundle

  log "bundle created: ${OUT_ROOT}/${BUNDLE_NAME}.tar.gz"
}

main "$@"
