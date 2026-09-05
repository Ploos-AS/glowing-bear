#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.2.3}"

expect_fail() {
  local name="$1"
  shift
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    echo "negative test unexpectedly succeeded: $name" >&2
    cat "$stdout_file" >&2 || true
    cat "$stderr_file" >&2 || true
    rm -f "$stdout_file" "$stderr_file"
    exit 1
  fi

  if grep -Eq '^ghcr\.io/ploos-as/glowing-bear@sha256:[0-9a-f]{64}$' "$stdout_file"; then
    echo "negative test leaked an accepted immutable ref on stdout: $name" >&2
    cat "$stdout_file" >&2 || true
    rm -f "$stdout_file" "$stderr_file"
    exit 1
  fi

  echo "PASS (rejected): $name"
  rm -f "$stdout_file" "$stderr_file"
}

expect_fail "wrong OIDC issuer" \
  env VERSION="$VERSION" OIDC_ISSUER=https://example.invalid PULL=0 \
  bash scripts/verify-release.sh

expect_fail "wrong signer identity" \
  env VERSION="$VERSION" EXPECTED_IDENTITY=https://github.com/Ploos-AS/glowing-bear/.github/workflows/not-the-signer.yml@refs/tags/v$VERSION PULL=0 \
  bash scripts/verify-release.sh

expect_fail "unsigned foreign image" \
  env IMAGE=docker.io/library/alpine VERSION=3.20 PULL=0 \
  bash scripts/verify-release.sh

expect_fail "nonexistent release tag" \
  env VERSION=99.99.99 PULL=0 \
  bash scripts/verify-release.sh

expect_fail "invalid runtime selector" \
  env VERSION="$VERSION" RUNTIME=containerd PULL=0 \
  bash scripts/verify-release.sh

expect_fail "invalid pull selector" \
  env VERSION="$VERSION" PULL=yes \
  bash scripts/verify-release.sh

expect_fail "missing VERSION" \
  env -u VERSION bash scripts/verify-release.sh

echo "All negative verification cases rejected as expected."
