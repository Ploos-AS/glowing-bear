#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"

if [[ "$VERSION" == v* ]]; then
  VERSION="${VERSION#v}"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "release version is not semver-like: $VERSION" >&2
  exit 1
fi

primary="$IMAGE:$VERSION"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

index_json="$workdir/index.json"
docker buildx imagetools inspect --raw "$primary" > "$index_json"

platform_digests=()
while IFS= read -r digest; do
  [[ -n "$digest" ]] && platform_digests+=("$digest")
done < <(
  jq -r '.manifests[]
    | select(.platform.os == "linux")
    | select(.platform.architecture == "amd64" or .platform.architecture == "arm64")
    | .digest' "$index_json"
)

if [[ "${#platform_digests[@]}" -lt 2 ]]; then
  echo "$primary does not expose both required Linux platform manifests" >&2
  exit 1
fi

attestation_rows="$workdir/attestations.tsv"
jq -r '.manifests[]
  | select(.platform.os == "unknown" and .platform.architecture == "unknown")
  | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest")
  | [.digest, .annotations["vnd.docker.reference.digest"]] | @tsv' \
  "$index_json" > "$attestation_rows"

if [[ ! -s "$attestation_rows" ]]; then
  echo "$primary has no BuildKit attestation manifests" >&2
  exit 1
fi

for platform_digest in "${platform_digests[@]}"; do
  attestation_digest="$(awk -F '\t' -v d="$platform_digest" '$2 == d {print $1; exit}' "$attestation_rows")"
  if [[ -z "$attestation_digest" ]]; then
    echo "missing attestation manifest for platform digest $platform_digest" >&2
    exit 1
  fi

  manifest_json="$workdir/${attestation_digest#sha256:}.json"
  docker buildx imagetools inspect --raw "$IMAGE@$attestation_digest" > "$manifest_json"

  linked_digest="$(jq -r '.annotations["vnd.docker.reference.digest"] // empty' "$manifest_json")"
  reference_type="$(jq -r '.annotations["vnd.docker.reference.type"] // empty' "$manifest_json")"

  if [[ "$linked_digest" != "$platform_digest" ]]; then
    echo "attestation $attestation_digest links to $linked_digest, expected $platform_digest" >&2
    exit 1
  fi
  if [[ "$reference_type" != "attestation-manifest" ]]; then
    echo "unexpected attestation reference type for $attestation_digest: $reference_type" >&2
    exit 1
  fi

  jq -e '[.layers[] | select(.mediaType == "application/vnd.in-toto+json")] | length >= 2' \
    "$manifest_json" >/dev/null || {
      echo "attestation $attestation_digest does not contain the expected in-toto layers" >&2
      exit 1
    }

  jq -e '.layers[]
    | select(.mediaType == "application/vnd.in-toto+json")
    | select(.annotations["in-toto.io/predicate-type"] == "https://slsa.dev/provenance/v0.2")
    | select(.size > 0)
    | .digest | test("^sha256:[0-9a-f]{64}$")' \
    "$manifest_json" >/dev/null || {
      echo "attestation $attestation_digest is missing a valid SLSA provenance descriptor" >&2
      exit 1
    }

  jq -e '.layers[]
    | select(.mediaType == "application/vnd.in-toto+json")
    | select(.annotations["in-toto.io/predicate-type"] == "https://spdx.dev/Document")
    | select(.size > 0)
    | .digest | test("^sha256:[0-9a-f]{64}$")' \
    "$manifest_json" >/dev/null || {
      echo "attestation $attestation_digest is missing a valid SPDX SBOM descriptor" >&2
      exit 1
    }

  echo "Qualified SLSA provenance and SPDX SBOM for $platform_digest via $attestation_digest"
done

echo "M0.9 attestation verification passed for $primary"
