#!/bin/sh
# Shared by the catalog scripts. ./dx sources it. Running it does nothing.
if [ "${DX_LIB_SOURCE:-}" != 1 ]; then
  echo "run ./dx <command>" >&2
  exit 1
fi

dx_need_docker() {
  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose is not available. Install Docker Desktop or the compose plugin." >&2
    exit 1
  fi
}

dx_compose() {
  profiles=
  if [ -n "${DX_COMPOSE_PROFILES:-}" ]; then
    for profile in $DX_COMPOSE_PROFILES; do
      profiles="$profiles --profile $profile"
    done
  fi
  # shellcheck disable=SC2086
  docker compose $profiles "$@"
}
