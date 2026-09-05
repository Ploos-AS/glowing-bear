#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:?UPSTREAM_VERSION is required}"
UPSTREAM_REVISION="${UPSTREAM_REVISION:?UPSTREAM_REVISION is required}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "release version is not semver-like: $VERSION" >&2
  exit 1
fi

major="${VERSION%%.*}"
minor="${VERSION%.*}"
primary="$IMAGE:$VERSION"

for _ in {1..36}; do
  if docker buildx imagetools inspect "$primary" >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

docker buildx imagetools inspect "$primary" >/dev/null

docker buildx imagetools inspect --raw "$primary" > release-index.json

jq -e '
  [.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")] | length >= 1
' release-index.json >/dev/null
jq -e '
  [.manifests[] | select(.platform.os == "linux" and .platform.architecture == "arm64")] | length >= 1
' release-index.json >/dev/null
jq -e '
  [.manifests[] | select(.platform.os == "unknown" and .platform.architecture == "unknown")] | length >= 2
' release-index.json >/dev/null

primary_digest="$(docker buildx imagetools inspect "$primary" | awk '/^Digest:/ {print $2; exit}')"
test -n "$primary_digest"

for tag in "$minor" "$major" latest; do
  alias_digest="$(docker buildx imagetools inspect "$IMAGE:$tag" | awk '/^Digest:/ {print $2; exit}')"
  if [[ "$alias_digest" != "$primary_digest" ]]; then
    echo "$IMAGE:$tag points to $alias_digest, expected $primary_digest" >&2
    exit 1
  fi
done

docker pull "$primary" >/dev/null

version_label="$(docker inspect --format '{{index .Config.Labels "io.github.ploos-as.upstream.version"}}' "$primary")"
revision_label="$(docker inspect --format '{{index .Config.Labels "io.github.ploos-as.upstream.revision"}}' "$primary")"
source_label="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$primary")"

test "$version_label" = "$UPSTREAM_VERSION"
test "$revision_label" = "$UPSTREAM_REVISION"
test "$source_label" = "https://github.com/Ploos-AS/glowing-bear"

echo "M0.8 release qualification passed for $primary ($primary_digest)"
