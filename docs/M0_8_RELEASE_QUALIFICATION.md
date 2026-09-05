# M0.8 release qualification

M0.8 adds a release-only verification gate for published GHCR images.

For every `v*` tag, `.github/workflows/release-qualification.yml` waits for the corresponding published image and then requires:

- a semantic-version image tag derived from the Git tag;
- `linux/amd64` and `linux/arm64` manifests;
- Buildx attestation manifests from the configured provenance/SBOM build;
- the full-version, major/minor, major, and `latest` tags to resolve to the same OCI index digest;
- the published native image to retain the expected upstream version and revision labels;
- `org.opencontainers.image.source` to point at this repository.

The workflow also runs `bash -n` against the qualification script on pull requests so syntax regressions are caught before release tagging.

This gate complements the existing runtime, WeeChat relay, browser, and TLS/WSS qualification. It verifies the release publication contract rather than replacing those runtime tests.
