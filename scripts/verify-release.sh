#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/ploos-as/glowing-bear}"
VERSION="${VERSION:?VERSION is required}"
OIDC_ISSUER="${OIDC_ISSUER:-https://token.actions.githubusercontent.com}"
PULL="${PULL:-0}"
RUNTIME="${RUNTIME:-auto}"

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

if [[ "$PULL" != "0" && "$PULL" != "1" ]]; then
  echo "PULL must be 0 or 1" >&2
  exit 1
fi

case "$RUNTIME" in
  auto|docker|podman) ;;
  *)
    echo "RUNTIME must be auto, docker, or podman" >&2
    exit 1
    ;;
esac

for command in skopeo cosign; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "required command not found: $command" >&2
    exit 1
  fi
done

primary="$IMAGE:$VERSION"
identity="https://github.com/Ploos-AS/glowing-bear/.github/workflows/sign-release.yml@refs/tags/$TAG"

image_digest="$(skopeo inspect --no-tags --format '{{.Digest}}' "docker://$primary")"
if [[ ! "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "could not resolve an immutable sha256 digest for $primary" >&2
  exit 1
fi

signed_ref="$IMAGE@$image_digest"

echo "Resolved release: $primary" >&2
echo "Immutable ref:   $signed_ref" >&2
echo "Expected signer: $identity" >&2
echo "Expected issuer: $OIDC_ISSUER" >&2

cosign verify \
  --certificate-identity "$identity" \
  --certificate-oidc-issuer "$OIDC_ISSUER" \
  "$signed_ref" >/dev/null

echo "Signature verification passed for $signed_ref" >&2

if [[ "$PULL" == "1" ]]; then
  selected_runtime="$RUNTIME"
  if [[ "$selected_runtime" == "auto" ]]; then
    if command -v docker >/dev/null 2>&1; then
      selected_runtime="docker"
    elif command -v podman >/dev/null 2>&1; then
      selected_runtime="podman"
    else
      echo "PULL=1 requires docker or podman" >&2
      exit 1
    fi
  fi

  if ! command -v "$selected_runtime" >/dev/null 2>&1; then
    echo "required runtime not found: $selected_runtime" >&2
    exit 1
  fi

  "$selected_runtime" pull "$signed_ref" >&2
  echo "Pulled verified immutable image with $selected_runtime: $signed_ref" >&2
fi

printf '%s\n' "$signed_ref"
