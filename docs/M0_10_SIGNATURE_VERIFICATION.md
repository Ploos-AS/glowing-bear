# M0.10 — Keyless release signing and identity verification

M0.10 adds cryptographic signing of published Glowing Bear OCI release images with Sigstore Cosign and GitHub Actions OIDC.

## Release signing

`.github/workflows/sign-release.yml` runs for `v*` tags. It waits for the corresponding GHCR image to be published, resolves the immutable OCI digest, and signs that digest with `cosign sign --yes`.

The workflow has `id-token: write`, allowing GitHub Actions to obtain a short-lived OIDC identity token. Cosign uses that identity with Sigstore/Fulcio and records the signature in the Sigstore transparency infrastructure.

No long-lived private signing key is stored in the repository or GitHub secrets.

The expected signer identity for tag `vX.Y.Z` is:

```text
https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/vX.Y.Z
```

The expected OIDC issuer is:

```text
https://token.actions.githubusercontent.com
```

## Verification

`scripts/qualify_signature.sh` verifies the immutable image digest with `cosign verify` and requires both the expected workflow identity and GitHub Actions OIDC issuer.

The script is race-safe: it waits for the release image and then waits for a valid Sigstore signature, defaulting to 60 attempts at 5-second intervals for each phase.

`.github/workflows/signature-verification.yml` performs:

- shell syntax validation on pull requests;
- full signature and signer-identity verification on release tags;
- manual verification of a selected release via `workflow_dispatch`.

## Acceptance criteria

A fresh release is M0.10-qualified only when:

1. the OCI release image is published successfully;
2. the release signing workflow successfully signs the exact release digest;
3. signature verification succeeds against the exact digest;
4. the certificate identity matches the repository's `sign-release.yml` workflow at that release tag;
5. the OIDC issuer matches GitHub Actions;
6. existing release, attestation, runtime, browser relay, and TLS/WSS qualification remain green.

M0.10 therefore upgrades the supply-chain claim from "published provenance/SBOM attestations are structurally and semantically verified" to "the release OCI digest is cryptographically signed and the signing workflow identity is verified."
