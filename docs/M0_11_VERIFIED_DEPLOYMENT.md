# M0.11 verified deployment policy

M0.10 proves that release images are signed keylessly with Sigstore/Cosign using GitHub Actions OIDC. M0.11 applies that trust decision on the consumer side: a release must be verified before it is pulled for deployment.

## Trust policy

The verifier accepts only a signature for the immutable image digest whose certificate identity is exactly:

```text
https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/v<VERSION>
```

and whose OIDC issuer is exactly:

```text
https://token.actions.githubusercontent.com
```

The verifier first resolves the requested semantic-version tag to its immutable `sha256:` digest. Cosign verification is then performed against `ghcr.io/ploos-as/glowing-bear@sha256:...`, not against the mutable tag.

## Consumer command

Requirements:

- Docker with Buildx
- Cosign

Verify only:

```bash
VERSION=0.2.3 bash scripts/verify-release.sh
```

Verify and pull only after verification succeeds:

```bash
VERSION=0.2.3 PULL=1 bash scripts/verify-release.sh
```

The script exits non-zero if the tag cannot be resolved to an immutable digest, if the release is unsigned, or if signer identity or issuer do not match the policy. With `PULL=1`, `docker pull` is not executed until Cosign verification has passed.

## CI qualification

`.github/workflows/deployment-verification.yml` qualifies the policy against the already signed `v0.2.3` release. The workflow:

1. validates the consumer script syntax;
2. installs Cosign;
3. resolves the signed release to an immutable digest;
4. verifies the exact GitHub workflow certificate identity and GitHub Actions OIDC issuer;
5. pulls that immutable digest only after verification succeeds.

Pull requests intentionally qualify the known signed `v0.2.3` release rather than the pull-request build itself, because pull-request images are not release-signed.

## Acceptance criteria

M0.11 is complete when:

- the consumer verifier is present and documented;
- verification is performed against an immutable digest;
- signer identity and issuer are exact, not wildcarded;
- the pull path is gated behind successful verification;
- the deployment-verification workflow passes against the signed `v0.2.3` release.
