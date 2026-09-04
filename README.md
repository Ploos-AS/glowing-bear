# Glowing Bear container

A small, hardened OCI container for [Glowing Bear](https://github.com/glowing-bear/glowing-bear), the browser-based WeeChat client.

The runtime image contains only the built static Glowing Bear assets and nginx. Node.js and npm are used only in the build stage. Glowing Bear connects from the user's browser directly to a WeeChat relay over WebSocket; WeeChat is intentionally not bundled into this image.

## Image

```text
ghcr.io/ploos-as/glowing-bear:latest
```

Target platforms:

- `linux/amd64`
- `linux/arm64`

The HTTP service listens on container port `8080` and runs as the unprivileged `nginx` user.

## Docker Compose

```bash
docker compose up -d
```

Then open `http://localhost:8080`.

The supplied `compose.yaml` enables a read-only root filesystem, drops all Linux capabilities, sets `no-new-privileges`, provides a small tmpfs for nginx runtime files, and includes a health check.

## Podman Quadlet

An example user Quadlet is provided at `quadlet/glowing-bear.container`.

Typical installation:

```bash
mkdir -p ~/.config/containers/systemd
cp quadlet/glowing-bear.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start glowing-bear.service
```

## WeeChat relay

Glowing Bear requires a reachable WeeChat relay. Upstream currently documents WeeChat 2.9 or newer.

A minimal local relay can be created from WeeChat with:

```text
/relay add weechat 9001
/set relay.network.password YOURPASSWORD
```

That example is unencrypted. Do not expose an unencrypted relay over an untrusted network. Prefer TLS or a TLS-terminating WebSocket reverse proxy for remote access.

The browser, not this container, connects to the relay. Therefore publishing port `9001` on the Glowing Bear container itself is neither necessary nor useful.

## Build

The Dockerfile clones upstream Glowing Bear during the build and accepts an upstream ref as a build argument:

```bash
docker build \
  --build-arg GLOWING_BEAR_REF=master \
  -t glowing-bear:local .
```

For release builds, use a known upstream tag or commit as `GLOWING_BEAR_REF` so the source is reproducible and auditable.

## CI / GHCR

GitHub Actions builds `linux/amd64` and `linux/arm64` with Buildx and publishes to GHCR on pushes to `main` and version tags. The workflow also requests provenance and SBOM attestations.

## Upstream and licensing

Glowing Bear is developed at <https://github.com/glowing-bear/glowing-bear> and is licensed under GPLv3. This repository packages the upstream application as an OCI image; it does not claim to be the upstream Glowing Bear project.
