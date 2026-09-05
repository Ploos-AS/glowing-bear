# M0.15 release/publish qualification

M0.15 qualifies the repository's release path before publishing the next immutable tag.

## Scope

The next release candidate is `v0.2.4`, created from the post-M0.14 `main` state. Existing tags are immutable and must not be moved.

The container workflow remains responsible for publishing the multi-platform OCI image and its provenance/SBOM attestations. The release-signing workflow waits for the versioned image, resolves its OCI digest, and signs that immutable digest with GitHub Actions OIDC and Cosign.

## M0.15 hardening

Release digest resolution now uses Skopeo instead of piping `docker buildx imagetools inspect` into an early-exiting `awk`. This removes the previously identified SIGPIPE/pipefail race from the release-signing and signature-qualification paths and keeps digest resolution consistent with the runtime-neutral verifier.

The `Release publish qualification` workflow runs on pull requests and requires:

- release/signature scripts to pass shell syntax validation;
- `sign-release.yml` to use Skopeo digest resolution and not the old Buildx/awk path;
- `scripts/qualify_signature.sh` to use the same Skopeo path;
- the current verification implementation to successfully verify the known-good signed `v0.2.3` release.

## v0.2.4 acceptance

After this change is merged, create `v0.2.4` at the exact qualified `main` commit. The release is accepted only when the tag-triggered workflows prove all of the following:

1. the `0.2.4` OCI index is published;
2. `linux/amd64` and `linux/arm64` manifests are present;
3. provenance and SBOM attestations are present;
4. the immutable index digest is signed by the exact `sign-release.yml@refs/tags/v0.2.4` GitHub Actions identity;
5. signature verification passes for that exact digest;
6. release qualification confirms semantic aliases and `latest` resolve to the expected release digest;
7. runtime qualification passes on the published image.

Only after these gates are green should a GitHub Release object for `v0.2.4` be published.
