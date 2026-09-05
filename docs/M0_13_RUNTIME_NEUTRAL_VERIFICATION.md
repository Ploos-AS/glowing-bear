# M0.13 runtime-neutral verified deployment

M0.13 removes Docker Buildx from the consumer trust path introduced in M0.11 and M0.12.

## Trust path

`scripts/verify-release.sh` now uses:

1. Skopeo to resolve `ghcr.io/ploos-as/glowing-bear:<version>` to the top-level immutable OCI digest.
2. Cosign to verify that exact digest against:
   - certificate identity `https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/v<VERSION>`
   - OIDC issuer `https://token.actions.githubusercontent.com`
3. Docker or Podman only after signature verification when `PULL=1` is requested.

The immutable image reference is the only stdout output. Diagnostics go to stderr so callers can safely use command substitution.

## Runtime selection

`RUNTIME` accepts:

- `auto` (default): Docker when available, otherwise Podman.
- `docker`: require Docker for the post-verification pull.
- `podman`: require Podman for the post-verification pull.

Verification without a pull does not require either container runtime.

Examples:

```bash
VERSION=0.2.3 bash scripts/verify-release.sh
VERSION=0.2.3 PULL=1 RUNTIME=docker bash scripts/verify-release.sh
VERSION=0.2.3 PULL=1 RUNTIME=podman bash scripts/verify-release.sh
```

## Deployment integration

The verified Docker Compose path still uses Docker intentionally, but consumes the runtime-neutral verifier before pulling and starting the immutable image.

The verified Quadlet renderer now requires only Skopeo and Cosign. It can therefore render a digest-pinned Podman Quadlet on a Podman-only host without Docker or Buildx installed.

## CI qualification

`Runtime-neutral verification` qualifies the signed `v0.2.3` release and requires:

- clean immutable-ref stdout;
- successful Docker pull after verification;
- successful Podman pull after verification;
- rejection of a deliberately incorrect OIDC issuer.

The existing deployment-verification and deployment-enforcement workflows also use Skopeo rather than Buildx for digest resolution.

## Acceptance criteria

M0.13 is complete when:

- signature verification no longer depends on Docker or Buildx;
- Docker and Podman can each pull the exact verified digest;
- Quadlet rendering works without Docker;
- incorrect signer trust data fails closed;
- all existing container, relay, TLS/WSS, attestation, signature, deployment and release gates remain green.
