#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def parse_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def require(pattern: str, text: str, expected: str, label: str) -> None:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise SystemExit(f"missing {label}")
    actual = match.group(1)
    if actual != expected:
        raise SystemExit(f"{label}: expected {expected!r}, got {actual!r}")


def main() -> None:
    canonical = parse_env(ROOT / "upstream.env")
    dockerfile = (ROOT / "Dockerfile").read_text()
    workflow = (ROOT / ".github/workflows/container.yml").read_text()

    require(r"^ARG NODE_IMAGE=([^\s]+)$", dockerfile, canonical["NODE_IMAGE"], "Dockerfile NODE_IMAGE")
    require(r"^ARG NGINX_IMAGE=([^\s]+)$", dockerfile, canonical["NGINX_IMAGE"], "Dockerfile NGINX_IMAGE")

    versions = re.findall(r"^ARG GLOWING_BEAR_VERSION=([^\s]+)$", dockerfile, re.MULTILINE)
    revisions = re.findall(r"^ARG GLOWING_BEAR_REF=([^\s]+)$", dockerfile, re.MULTILINE)
    if versions != [canonical["GLOWING_BEAR_VERSION"]] * 2:
        raise SystemExit(f"Dockerfile upstream versions are not canonical: {versions!r}")
    if revisions != [canonical["GLOWING_BEAR_REF"]] * 2:
        raise SystemExit(f"Dockerfile upstream revisions are not canonical: {revisions!r}")

    require(r"^  UPSTREAM_VERSION: '([^']+)'$", workflow, canonical["GLOWING_BEAR_VERSION"], "CI UPSTREAM_VERSION")
    require(r"^  UPSTREAM_REVISION: '([^']+)'$", workflow, canonical["GLOWING_BEAR_REF"], "CI UPSTREAM_REVISION")

    revision = canonical["GLOWING_BEAR_REF"]
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("GLOWING_BEAR_REF must be a full 40-character lowercase commit SHA")

    print("M0.5 build inputs are internally consistent and upstream is commit-pinned")


if __name__ == "__main__":
    main()
