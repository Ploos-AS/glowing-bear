#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"
OIDC_ISSUER="${OIDC_ISSUER:-https://token.actions.githubusercontent.com}"
PULL="${PULL:-0}"

if [[ "$VERSION" == v* ]]; then
  TAG="$VERSION"
  VERSION="${VERSION#v}"
else
  TAG="v$VERSION"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "release version is not semver-like: $VERSION" >&2
  exit 1
fi

for command in docker cosign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

primary="$IMAGE:$VERSION"
identity="https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/$TAG"

image_digest="$(docker buildx imagetools inspect "$primary" | awk '/^Digest:/ {print $2; exit}')"
if [[ ! "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "could not resolve an immutable sha256 digest for $primary" >&2
  exit 1
fi

signed_ref="$IMAGE@$image_digest"

echo "Resolved release: $primary"
echo "Immutable ref:   $signed_ref"
echo "Expected signer: $identity"
echo "Expected issuer: $OIDC_ISSUER"

cosign verify \
  --certificate-identity "$identity" \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  "$signed_ref" >/dev/null

echo "Signature verification passed for $signed_ref"

if [[ "$PULL" == "1" ]]; then
  docker pull "$signed_ref"
  echo "Pulled verified immutable image: $signed_ref"
elif [[ "$PULL" != "0" ]]; then
  echo "PULL must be 0 or 1" >&2
  exit 1
fi

printf '%s\n' "$signed_ref"
