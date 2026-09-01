# Runner-fleet registry pull-through mirror (spec)

Owner: Jared (host side). Status: spec 2026-08-16, from the event-manager
timing analysis — every job runs on a fresh ephemeral dind sidecar
(deliberate, Principle 5), so image pulls repeat on every job, portfolio-wide.
Measured cost: ~3m25s "Initialize containers" on tier-2 jobs, plus pull
time inside every compose-based test stack, on every run.

## Host side (one service per aj78 host)

Run a registry:2 pull-through cache proxying Docker Hub:

```sh
docker run -d --name registry-mirror --restart=always \
  -p 5000:5000 \
  -v /var/lib/registry-mirror:/var/lib/registry \
  -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
  registry:2
```

- Optional but recommended: set REGISTRY_PROXY_USERNAME/PASSWORD to a
  Docker Hub account — raises the anonymous pull rate limit every runner
  currently shares per-IP.
- Cached blobs default to a 168h TTL; add a weekly
  `registry garbage-collect /etc/docker/registry/config.yml` cron (or
  size-cap the volume) so /var/lib/registry-mirror doesn't grow unbounded.
- The dind sidecars reach the host over the default bridge gateway
  (172.17.0.1). Verify from any runner:
  `curl http://172.17.0.1:5000/v2/` → `{}`.

## Controller side (one-line dockerd change)

The dind sidecar's dockerd is launched in
`internal/runner/docker.go` (`dindCmd`, ~line 256). Append:

```
--registry-mirror=http://172.17.0.1:5000 --insecure-registry=172.17.0.1:5000
```

Cleanest as a new config option (`runners.registry_mirror`) appended to
dindCmd when set — happy to make that change as a PR. `--insecure-registry`
is required because the mirror speaks plain HTTP on the LAN.

## Verification

- `docker info` inside any dind shows the mirror under "Registry Mirrors".
- "Initialize containers" on event-manager tier-2 jobs drops from ~3m25s
  to seconds on warm cache; second pull of any Hub image portfolio-wide is
  LAN-speed.

## Known limits (phase 2 if wanted)

`--registry-mirror` applies to docker.io ONLY. ghcr.io (tier-2 builder
image, prod base) and quay.io images still pull direct. Covering them
means either switching the dind daemons to the containerd image store
with per-registry `hosts.toml` mirror config, or a caching proxy that
rewrites image names (workflow-visible — avoid). docker.io alone covers
mariadb, node/alpine bases, docker:dind itself, and most compose stacks.
