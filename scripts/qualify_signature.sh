#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-60}"
WAIT_SECONDS="${WAIT_SECONDS:-5}"
OIDC_ISSUER="${OIDC_ISSUER:-https://token.actions.githubusercontent.com}"

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

for command in skopeo cosign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

primary="$IMAGE:$VERSION"
identity="https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/$TAG"

image_digest=""
for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
  image_digest="$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$primary" 2>/dev/null || true)"
  if [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Found $primary at $image_digest (attempt $attempt/$WAIT_ATTEMPTS)"
    break
  fi
  echo "Waiting for $primary to be published (attempt $attempt/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SECONDS"
done

if [[ ! "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "timed out waiting for $primary" >&2
  exit 1
fi

signed_ref="$IMAGE@$image_digest"
for attempt in $(seq 1 "$WAIT_ATTEMPTS"); do
  if output="$(cosign verify \
      --certificate-identity "$identity" \
      --certificate-oidc-issuer "$OIDC_ISSUER" \
      "$signed_ref" 2>&1)"; then
    printf '%s\n' "$output"
    echo "M0.10 signature verification passed for $signed_ref"
    echo "Verified signer identity: $identity"
    exit 0
  fi

  echo "Waiting for Sigstore signature on $signed_ref (attempt $attempt/$WAIT_ATTEMPTS)"
  if [[ "$attempt" -eq "$WAIT_ATTEMPTS" ]]; then
    printf '%s\n' "$output" >&2
    break
  fi
  sleep "$WAIT_SECONDS"
done

echo "timed out waiting for a valid Sigstore signature for $signed_ref" >&2
exit 1
