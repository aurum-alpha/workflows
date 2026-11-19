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

# The devkit renders dev/ when this product installs it as a package (#819):
# @aurum-alpha/devkit, a devDependency in the package.json at the root or in
# one directory below it. A product that still commits dev/ installs none,
# and nothing here touches its tree.
dx_render_devkit() {
  for bin in "$DX_ROOT/node_modules/.bin/aurum-devkit" "$DX_ROOT"/*/node_modules/.bin/aurum-devkit; do
    [ -x "$bin" ] || continue
    "$bin" render --target "$DX_ROOT"
    return
  done
}
