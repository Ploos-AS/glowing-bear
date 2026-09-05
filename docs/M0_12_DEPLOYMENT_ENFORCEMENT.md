# M0.12 deployment enforcement

M0.11 added consumer-side Sigstore/Cosign verification. M0.12 turns that verification into the supported secure deployment path for Docker Compose and Podman Quadlet.

## Policy

The secure deployment path is fail-closed:

1. A semantic release version is supplied by the operator.
2. `scripts/verify-release.sh` resolves the release tag to an immutable OCI digest.
3. Cosign verifies that exact digest against the expected GitHub Actions certificate identity and the GitHub Actions OIDC issuer.
4. Only the verified `ghcr.io/ploos-as/glowing-bear@sha256:...` reference is handed to the deployment mechanism.
5. Any resolution, signature, identity, issuer, or immutable-reference failure stops deployment.

This is an application/operator deployment policy. It is not a Docker daemon, Podman engine, or host-wide admission controller.

## Docker Compose

Use:

```bash
VERSION=0.2.3 bash scripts/deploy-verified-compose.sh
```

The script verifies the release, pulls only the verified immutable digest, exports that digest through `GLOWING_BEAR_IMAGE`, validates the Compose model, and starts the service with `--no-build` so a local build cannot replace the verified release image.

`compose.yaml` still has a `:latest` fallback for development and compatibility. That fallback is not the verified deployment path.

## Podman Quadlet

Generate a Quadlet containing the verified immutable digest:

```bash
VERSION=0.2.3 \
OUTPUT="$HOME/.config/containers/systemd/glowing-bear.container" \
bash scripts/render-verified-quadlet.sh

systemctl --user daemon-reload
systemctl --user restart glowing-bear.service
```

The renderer refuses to produce the deployment file unless verification succeeds and the resulting `Image=` value is an immutable `sha256` reference.

## CI qualification

`.github/workflows/deployment-enforcement.yml` qualifies M0.12 against the signed `v0.2.3` release. The gate:

- syntax-checks both enforcement scripts;
- executes the verified Compose deployment path;
- verifies the running container was created from an immutable digest reference;
- requires `/healthz` to become reachable;
- renders a verified Quadlet;
- requires its `Image=` field to contain an immutable digest and rejects `:latest`.

## Acceptance criteria

M0.12 is complete when:

- the verified Compose path deploys only after successful signature verification;
- the Compose runtime image reference is immutable;
- local build substitution is disabled in the verified path;
- the verified Quadlet path emits only an immutable image reference;
- CI proves both paths against a real signed release;
- failures in verification prevent deployment output or startup.
