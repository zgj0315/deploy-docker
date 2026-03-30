#!/usr/bin/env bash

set -euo pipefail

SMOKE_IMAGE=${SMOKE_IMAGE:-}

log() {
  printf '[INFO] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

check_service() {
  systemctl is-active --quiet docker || die "docker service is not active"
}

check_docker_cli() {
  docker version >/dev/null
  docker info >/dev/null
}

run_smoke_test() {
  [[ -n "${SMOKE_IMAGE}" ]] || {
    log "SMOKE_IMAGE not set, skipping container smoke test"
    return 0
  }

  log "running smoke test with ${SMOKE_IMAGE}"
  docker run --rm "${SMOKE_IMAGE}" >/dev/null
}

main() {
  require_cmd systemctl
  require_cmd docker

  check_service
  check_docker_cli
  run_smoke_test

  log "docker verification succeeded"
}

main "$@"
