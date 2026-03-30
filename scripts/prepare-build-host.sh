#!/usr/bin/env bash

set -euo pipefail

DOCKER_SOURCE_FILE="/etc/apt/sources.list.d/docker.sources"
DOCKER_KEYRING_DIR="/etc/apt/keyrings"
DOCKER_KEYRING_FILE="${DOCKER_KEYRING_DIR}/docker.asc"
APT_LOCK_TIMEOUT=${APT_LOCK_TIMEOUT:-300}
DOCKER_APT_BASE_URL=${DOCKER_APT_BASE_URL:-"https://download.docker.com/linux/ubuntu"}
DOCKER_APT_GPG_URL=${DOCKER_APT_GPG_URL:-"${DOCKER_APT_BASE_URL}/gpg"}

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

find_lock_pids() {
  python3 - <<'PY'
import os

targets = {
    "/var/lib/dpkg/lock-frontend",
    "/var/lib/dpkg/lock",
    "/var/lib/apt/lists/lock",
    "/var/cache/apt/archives/lock",
}

pids = set()
for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            path = os.path.join(fd_dir, fd)
            try:
                target = os.readlink(path)
            except OSError:
                continue
            if target in targets:
                pids.add(pid)
                break
    except OSError:
        continue

print(" ".join(sorted(pids)))
PY
}

wait_for_apt_locks() {
  local waited=0
  local lock_pids

  while true; do
    lock_pids=$(find_lock_pids)
    [[ -z "${lock_pids}" ]] && break

    if (( waited >= APT_LOCK_TIMEOUT )); then
      die "timed out waiting for apt/dpkg locks held by process(es): ${lock_pids}"
    fi

    log "waiting for apt/dpkg locks to be released by process(es): ${lock_pids}"
    sleep 5
    waited=$((waited + 5))
  done
}

check_platform() {
  [[ -r /etc/os-release ]] || die "cannot detect operating system"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "build host must be Ubuntu"
  [[ "${VERSION_ID:-}" == "24.04" ]] || die "build host must be Ubuntu 24.04"
}

install_prerequisites() {
  log "installing build prerequisites"
  wait_for_apt_locks
  apt-get update
  wait_for_apt_locks
  apt-get install -y ca-certificates curl apt-rdepends
}

configure_docker_repo() {
  log "configuring Docker APT repository: ${DOCKER_APT_BASE_URL}"
  install -m 0755 -d "${DOCKER_KEYRING_DIR}"
  curl -fsSL "${DOCKER_APT_GPG_URL}" -o "${DOCKER_KEYRING_FILE}"
  chmod a+r "${DOCKER_KEYRING_FILE}"

  cat > "${DOCKER_SOURCE_FILE}" <<EOF
Types: deb
URIs: ${DOCKER_APT_BASE_URL}
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

refresh_apt_index() {
  log "refreshing apt metadata"
  wait_for_apt_locks
  apt-get update
}

verify_repo() {
  local pkg
  local candidate

  for pkg in containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; do
    candidate=$(apt-cache policy "${pkg}" | awk '/Candidate:/ {print $2}')
    [[ -n "${candidate}" && "${candidate}" != "(none)" ]] || die "package ${pkg} has no install candidate after repository setup"
  done
}

main() {
  require_root
  require_cmd apt-get
  require_cmd curl
  require_cmd apt-cache
  require_cmd python3

  check_platform
  install_prerequisites
  configure_docker_repo
  refresh_apt_index
  verify_repo

  log "build host is ready"
}

main "$@"
