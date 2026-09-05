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

platform_rows="$workdir/platforms.tsv"
jq -r '.manifests[]
  | select(.platform.os == "linux")
  | select(.platform.architecture == "amd64" or .platform.architecture == "arm64")
  | [.platform.architecture, .digest] | @tsv' "$index_json" > "$platform_rows"

for arch in amd64 arm64; do
  if ! awk -F '\t' -v a="$arch" '$1 == a {found=1} END {exit !found}' "$platform_rows"; then
    echo "$primary is missing linux/$arch" >&2
    exit 1
  fi
done

# BuildKit stores the subject linkage on the attestation descriptor in the OCI
# index. The descriptor binds each attestation manifest to its exact platform
# digest; Buildx exposes decoded provenance/SBOM payloads from the parent
# multi-platform release reference.
attestation_rows="$workdir/attestations.tsv"
jq -r '.manifests[]
  | select(.platform.os == "unknown" and .platform.architecture == "unknown")
  | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest")
  | select((.annotations["vnd.docker.reference.digest"] // "") | test("^sha256:[0-9a-f]{64}$"))
  | [.digest, .annotations["vnd.docker.reference.digest"]] | @tsv' \
  "$index_json" > "$attestation_rows"

if [[ ! -s "$attestation_rows" ]]; then
  echo "$primary has no valid BuildKit attestation descriptors" >&2
  exit 1
fi

while IFS=$'\t' read -r arch platform_digest; do
  attestation_digest="$(awk -F '\t' -v d="$platform_digest" '$2 == d {print $1; exit}' "$attestation_rows")"
  if [[ -z "$attestation_digest" ]]; then
    echo "missing attestation manifest for linux/$arch digest $platform_digest" >&2
    exit 1
  fi

  manifest_json="$workdir/${attestation_digest#sha256:}.manifest.json"
  docker buildx imagetools inspect --raw "$IMAGE@$attestation_digest" > "$manifest_json"

  jq -e '[.layers[] | select(.mediaType == "application/vnd.in-toto+json") | select(.size > 0) | .digest | select(test("^sha256:[0-9a-f]{64}$"))] | length >= 2' \
    "$manifest_json" >/dev/null || {
      echo "attestation $attestation_digest does not contain at least two valid in-toto layers" >&2
      exit 1
    }
done < "$platform_rows"

provenance_json="$workdir/provenance.json"
sbom_json="$workdir/sbom.json"

docker buildx imagetools inspect \
  --format '{{ json .Provenance }}' \
  "$primary" > "$provenance_json"
docker buildx imagetools inspect \
  --format '{{ json .SBOM }}' \
  "$primary" > "$sbom_json"

for arch in amd64 arm64; do
  jq -e --arg platform "linux/$arch" '
    .[$platform].SLSA
    | type == "object"
      and (.buildDefinition | type == "object")
      and (.buildDefinition.buildType | type == "string" and length > 0)
      and (.runDetails | type == "object")
      and (.runDetails.builder.id | type == "string" and length > 0)
  ' "$provenance_json" >/dev/null || {
    echo "$primary is missing readable SLSA provenance content for linux/$arch" >&2
    cat "$provenance_json" >&2 || true
    exit 1
  }
done

jq -e '
  . != null and
  ([.. | objects | .spdxVersion? // empty] | any(startswith("SPDX-")))
' "$sbom_json" >/dev/null || {
  echo "$primary is missing readable SPDX SBOM content" >&2
  cat "$sbom_json" >&2 || true
  exit 1
}

while IFS=$'\t' read -r arch platform_digest; do
  attestation_digest="$(awk -F '\t' -v d="$platform_digest" '$2 == d {print $1; exit}' "$attestation_rows")"
  echo "Qualified attestation linkage for linux/$arch $platform_digest via $attestation_digest"
done < "$platform_rows"

echo "Qualified decoded SLSA provenance and SPDX SBOM payloads for $primary"
echo "M0.9 attestation verification passed for $primary"
