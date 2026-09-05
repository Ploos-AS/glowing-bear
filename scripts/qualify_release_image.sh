#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:?UPSTREAM_VERSION is required}"
UPSTREAM_REVISION="${UPSTREAM_REVISION:?UPSTREAM_REVISION is required}"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-60}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "release version is not semver-like: $VERSION" >&2
  exit 1
fi

major="${VERSION%%.*}"
minor="${VERSION%.*}"
primary="$IMAGE:$VERSION"

inspect_digest() {
  docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/ {print $2; exit}'
}

primary_digest=""
for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
  primary_digest="$(inspect_digest "$primary" || true)"
  if [[ -n "$primary_digest" ]]; then
    echo "Found $primary at $primary_digest (attempt $attempt/$WAIT_ATTEMPTS)"
    break
  fi
  echo "Waiting for $primary to be published (attempt $attempt/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SECONDS"
done

if [[ -z "$primary_digest" ]]; then
  echo "timed out waiting for $primary" >&2
  exit 1
fi

# The semver aliases are published by the same multi-platform build, but registry
# visibility can lag between tags. Wait until every alias resolves to the exact
# same OCI index digest rather than failing on the first transient 404/mismatch.
for tag in "$minor" "$major" latest; do
  alias_ref="$IMAGE:$tag"
  alias_digest=""
  for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
    alias_digest="$(inspect_digest "$alias_ref" || true)"
    if [[ "$alias_digest" == "$primary_digest" ]]; then
      echo "Qualified alias $alias_ref -> $alias_digest"
      break
    fi
    if [[ -z "$alias_digest" ]]; then
      echo "Waiting for alias $alias_ref (attempt $attempt/$WAIT_ATTEMPTS)"
    else
      echo "Waiting for alias $alias_ref to converge: $alias_digest != $primary_digest (attempt $attempt/$WAIT_ATTEMPTS)"
    fi
    sleep "$WAIT_SECONDS"
  done
  if [[ "$alias_digest" != "$primary_digest" ]]; then
    echo "$alias_ref points to ${alias_digest:-<missing>}, expected $primary_digest" >&2
    exit 1
  fi
done

# Re-fetch the index only after publication has converged.
docker buildx imagetools inspect --raw "$primary" > release-index.json

jq -e '
  [.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")] | length >= 1
' release-index.json >/dev/null || {
  echo "$primary is missing a linux/amd64 manifest" >&2
  exit 1
}
jq -e '
  [.manifests[] | select(.platform.os == "linux" and .platform.architecture == "arm64")] | length >= 1
' release-index.json >/dev/null || {
  echo "$primary is missing a linux/arm64 manifest" >&2
  exit 1
}
jq -e '
  [.manifests[] | select(.platform.os == "unknown" and .platform.architecture == "unknown")] | length >= 2
' release-index.json >/dev/null || {
  echo "$primary is missing expected Buildx provenance/SBOM attestation manifests" >&2
  exit 1
}

# Pull an explicit native platform. Pulling a multi-platform OCI index without a
# platform can return exit 255 with recent Docker/Buildx combinations.
docker pull --platform linux/amd64 "$primary" >/dev/null

version_label="$(docker inspect --format '{{index .Config.Labels "io.github.ploos-as.upstream.version"}}' "$primary")"
revision_label="$(docker inspect --format '{{index .Config.Labels "io.github.ploos-as.upstream.revision"}}' "$primary")"
source_label="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$primary")"

if [[ "$version_label" != "$UPSTREAM_VERSION" ]]; then
  echo "unexpected upstream version label: $version_label (expected $UPSTREAM_VERSION)" >&2
  exit 1
fi
if [[ "$revision_label" != "$UPSTREAM_REVISION" ]]; then
  echo "unexpected upstream revision label: $revision_label (expected $UPSTREAM_REVISION)" >&2
  exit 1
fi
if [[ "$source_label" != "https://github.com/Ploos-AS/glowing-bear" ]]; then
  echo "unexpected OCI source label: $source_label" >&2
  exit 1
fi

echo "M0.8 release qualification passed for $primary ($primary_digest)"
