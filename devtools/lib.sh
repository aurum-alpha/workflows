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

# The devkit renders dev/ when this product declares it as a package (#819):
# @aurum-alpha/devkit, a devDependency in the package.json at the root or in
# one directory below it. The installed binary renders when it is there.
# Without an install, npx fetches the version the package.json pins, so a
# fresh clone comes up without one. A product that still commits dev/
# declares none, and nothing here touches its tree.
dx_render_devkit() {
  for bin in "$DX_ROOT/node_modules/.bin/aurum-devkit" "$DX_ROOT"/*/node_modules/.bin/aurum-devkit; do
    [ -x "$bin" ] || continue
    "$bin" render --target "$DX_ROOT"
    return
  done
  for manifest in "$DX_ROOT/package.json" "$DX_ROOT"/*/package.json; do
    [ -f "$manifest" ] || continue
    grep -q '"@aurum-alpha/devkit"' "$manifest" || continue
    if ! command -v npx >/dev/null 2>&1; then
      echo "rendering dev/ needs Node: install it, or pnpm install beside $manifest" >&2
      exit 1
    fi
    version="$(node -p "require(process.argv[1]).devDependencies['@aurum-alpha/devkit']" "$manifest")"
    npx --yes --package="@aurum-alpha/devkit@$version" aurum-devkit render --target "$DX_ROOT"
    return
  done
}
