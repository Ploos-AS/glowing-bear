# M0.9 attestation verification

M0.8 verifies that a published release exposes Buildx attestation manifests. M0.9 strengthens that contract by validating how those attestations are attached and what predicate types they advertise.

For every required Linux platform manifest (`linux/amd64` and `linux/arm64`), M0.9 requires:

- a BuildKit attestation manifest whose `vnd.docker.reference.digest` points to that exact platform digest;
- `vnd.docker.reference.type=attestation-manifest`;
- in-toto layers using media type `application/vnd.in-toto+json`;
- a non-empty SLSA provenance descriptor with predicate type `https://slsa.dev/provenance/v0.2`;
- a non-empty SPDX SBOM descriptor with predicate type `https://spdx.dev/Document`;
- sha256 layer digests for both descriptors.

This closes the M0.8 gap where merely counting `unknown/unknown` manifests could not distinguish the required provenance/SBOM contract from unrelated attestations.

The workflow runs on release tags and can also be run manually against an existing immutable release. Pull requests verify the currently published `0.2.1` release as a real registry-backed integration test while also syntax-checking the script.

M0.9 does not claim cryptographic signer identity verification. Signature policy and keyless identity verification, if desired, belong in a later milestone rather than being conflated with attestation-content qualification.
