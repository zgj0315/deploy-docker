#!/usr/bin/env bash

set -euo pipefail

PURGE_DATA=0
if [[ ${1:-} == "--purge-data" ]]; then
  PURGE_DATA=1
fi

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

main() {
  require_root

  systemctl disable --now docker.service docker.socket 2>/dev/null || true
  systemctl disable --now containerd.service 2>/dev/null || true

  apt-get remove -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin containerd.io 2>/dev/null || true
  apt-get autoremove -y 2>/dev/null || true

  rm -f /etc/docker/daemon.json
  rm -f /etc/systemd/system/docker.service.d/override.conf
  rmdir /etc/systemd/system/docker.service.d 2>/dev/null || true
  rmdir /etc/docker 2>/dev/null || true

  systemctl daemon-reload

  if [[ ${PURGE_DATA} -eq 1 ]]; then
    rm -rf /var/lib/docker /var/lib/containerd
    log "docker data directories removed"
  else
    log "docker binaries removed, data directories preserved"
    log "to purge data later, run: bash scripts/uninstall.sh --purge-data"
  fi
}

main "$@"
