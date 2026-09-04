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

### M0.2 relay qualification

CI starts an ephemeral WeeChat instance with a password-protected WebSocket relay and exercises the same `/weechat` transport and relay protocol expected by the pinned Glowing Bear client. The qualification performs the WeeChat handshake, authenticates using the negotiated plain-password method on the isolated CI loopback relay, requests WeeChat version information, and requires a valid binary relay response.

This complements the container smoke test: the smoke test proves that the hardened static web container runs correctly, while M0.2 proves that a real WeeChat WebSocket relay is reachable and speaks the protocol Glowing Bear expects.

The test relay is bound only for the lifetime of the GitHub Actions runner and is not a deployment example. Production remote relays should use TLS.

### M0.3 browser relay qualification

CI also launches the built Glowing Bear container in hardened mode, starts a real password-protected WeeChat relay, and drives the Glowing Bear connection form in headless Chromium with Playwright. The gate requires the browser to open `ws://127.0.0.1:19001/weechat`, complete authentication through Glowing Bear itself, and enter Glowing Bear's connected UI state without displaying a connection error.

M0.3 therefore covers the browser JavaScript path that M0.2 intentionally does not: static container -> real browser -> Glowing Bear connection code -> real WeeChat WebSocket relay.

### M0.4 TLS reverse proxy deployments

Production-oriented reference deployments are provided under `deploy/caddy/` and `deploy/nginx/`. Both expose Glowing Bear and the WeeChat WebSocket relay on the same public origin, with `/weechat` forwarded to the relay and all other requests forwarded to the Glowing Bear container.

The Caddy example is the recommended starting point because it can obtain and renew public TLS certificates automatically. Set `SITE_ADDRESS` to the public hostname and `WEECHAT_RELAY_UPSTREAM` to the WeeChat relay address, then run:

```bash
cd deploy/caddy
SITE_ADDRESS=chat.example.com \
WEECHAT_RELAY_UPSTREAM=host.docker.internal:9001 \
docker compose up -d
```

The nginx example expects an existing certificate and private key at `deploy/nginx/certs/fullchain.pem` and `deploy/nginx/certs/privkey.pem`:

```bash
cd deploy/nginx
docker compose up -d
```

With either deployment, configure Glowing Bear to use the public hostname, port `443`, path `weechat`, and encryption enabled. The browser then connects to `wss://chat.example.com/weechat`; the raw WeeChat relay port does not need to be exposed publicly.

CI syntax-validates both Compose files, validates the Caddyfile with Caddy itself, and runs `nginx -t` against the nginx configuration with an ephemeral test certificate.

### M0.5 reproducible build inputs

`upstream.env` is the canonical inventory of release build inputs: the expected Glowing Bear version, the exact upstream source commit, and the Node/nginx base-image references used by the Dockerfile.

CI runs `scripts/qualify_build_inputs.py` on every pull request and push to `main`. The gate fails if the Dockerfile or container workflow drifts from the canonical upstream version/revision, if the base-image defaults drift from the inventory, or if the Glowing Bear source reference stops being a full 40-character commit SHA.

This makes upstream updates deliberate and reviewable: change `upstream.env`, update the corresponding Dockerfile/CI values together, then let the existing multi-architecture, relay, browser, runtime, SBOM and provenance gates qualify the new build.

### M0.6 TLS/WSS end-to-end qualification

CI now exercises the production-style encrypted path, not only proxy syntax. It builds the Glowing Bear image, starts the hardened container behind the repository's Caddy reference configuration, starts a real password-protected WeeChat relay, and opens Glowing Bear over local HTTPS in headless Chromium.

The browser is required to request `wss://localhost:18443/weechat`, complete Glowing Bear authentication through Caddy's TLS-terminating WebSocket reverse proxy, enter the connected UI state, and avoid displaying a connection error. Caddy uses its local development CA for the isolated CI endpoint; Playwright is configured to accept that CI-only certificate.

M0.6 therefore qualifies the complete path represented by the recommended deployment reference: browser -> HTTPS Glowing Bear -> WSS -> Caddy -> private WeeChat relay.

## Upstream pin

Release builds are intentionally pinned to an exact Glowing Bear source revision rather than the moving `master` branch.

Current pin for the first container release:

- Glowing Bear version: `0.10.0`
- Upstream revision: `b53e42f584bd8165287cee5f680e23ffa05198b7`
- Upstream commit date: 2026-08-06

The build verifies that the pinned source still reports the expected upstream version before installing dependencies.

## Build

The defaults are reproducible for the current release candidate:

```bash
docker build -t glowing-bear:local .
```

A deliberate upstream override remains possible for development/testing:

```bash
docker build \
  --build-arg GLOWING_BEAR_VERSION=0.10.0 \
  --build-arg GLOWING_BEAR_REF=b53e42f584bd8165287cee5f680e23ffa05198b7 \
  -t glowing-bear:local .
```

Do not publish a release from a floating branch name. Update the version and revision together, qualify the resulting image, and only then create a release tag.

## CI / GHCR

GitHub Actions builds `linux/amd64` and `linux/arm64` with Buildx and publishes to GHCR on pushes to `main` and version tags. The workflow also requests provenance and SBOM attestations.

Version tags publish the full semantic version, major/minor alias, major alias, and `latest`; for example `v0.1.0` publishes `0.1.0`, `0.1`, `0`, and `latest`.

The runtime qualification gate pulls the published image and verifies hardened startup with a read-only root filesystem, dropped capabilities, `no-new-privileges`, the `/healthz` endpoint, the Glowing Bear front page, non-root execution, and a real WeeChat WebSocket relay protocol exchange.

## Upstream and licensing

Glowing Bear is developed at <https://github.com/glowing-bear/glowing-bear> and is licensed under GPLv3. This repository packages the upstream application as an OCI image; it does not claim to be the upstream Glowing Bear project.
