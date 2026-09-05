# M0.14 negative-path hardening

M0.14 proves that the verified deployment path fails closed when trust, image, release, or runtime inputs are wrong.

## Scope

The positive trust path remains unchanged: release tags are resolved with Skopeo, the resulting immutable digest is verified with Cosign against the expected GitHub Actions certificate identity and OIDC issuer, and only then may Docker or Podman pull the image.

M0.14 adds an explicit negative qualification matrix. Each case must fail with a non-zero exit status and must not emit an accepted Glowing Bear immutable image reference on stdout.

## Negative cases

CI rejects all of the following:

- wrong GitHub Actions OIDC issuer;
- wrong certificate identity / signer workflow;
- an unsigned unrelated container image;
- a nonexistent Glowing Bear release tag;
- an unsupported runtime selector;
- an invalid PULL selector;
- a missing VERSION value.

The signed `v0.2.3` release remains the positive qualification target. Existing tags are not moved or rewritten.

## Testability of signer identity

`scripts/verify-release.sh` still defaults to the exact production signer identity:

`https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/v<VERSION>`

`EXPECTED_IDENTITY` exists only as an explicit override so CI and operators can test a stricter or intentionally mismatching identity. It does not weaken the default policy: with no override, the repository's release-signing workflow and exact tag remain mandatory.

## Acceptance criteria

M0.14 is complete when:

1. the normal signed release verification succeeds;
2. Docker and Podman verified pull paths still succeed;
3. every negative case fails;
4. no negative case emits an accepted immutable Glowing Bear ref on stdout;
5. all existing repository workflows remain green.
