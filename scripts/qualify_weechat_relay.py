#!/usr/bin/env python3
"""Qualify a WeeChat websocket relay using the protocol Glowing Bear expects."""

import argparse
import asyncio
import sys

import websockets


async def qualify(url: str, password: str) -> None:
    ws = await websockets.connect(url, open_timeout=10, close_timeout=1)
    qualified = False
    try:
        await ws.send("(handshake) handshake password_hash_algo=plain,compression=off\n")
        handshake = await asyncio.wait_for(ws.recv(), timeout=10)
        if not isinstance(handshake, bytes):
            raise RuntimeError("WeeChat handshake response was not binary")
        if b"handshake" not in handshake or b"plain" not in handshake:
            raise RuntimeError("WeeChat handshake response did not negotiate plain authentication")

        # Classic WeeChat relay protocol expects the raw password value here.
        # The `plain:<password>` form belongs to the newer Relay HTTP API.
        await ws.send(f"(init) init password={password}\n")
        await ws.send("(version) info version\n")
        version = await asyncio.wait_for(ws.recv(), timeout=10)
        if not isinstance(version, bytes):
            raise RuntimeError("WeeChat version response was not binary")
        if b"version" not in version:
            raise RuntimeError("WeeChat relay did not return the requested version info")

        qualified = True
    finally:
        if qualified:
            # WeeChat 4.1.x may not complete the RFC 6455 close handshake.
            # Once handshake/auth/version are proven, terminate the transport
            # directly so that this server shutdown quirk can't turn a valid
            # qualification into a false negative.
            ws.transport.abort()
        else:
            # Preserve normal close behavior when qualification itself failed.
            # Any resulting transport error is secondary to the real failure.
            try:
                await ws.close()
            except Exception:
                pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:19001/weechat")
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    try:
        asyncio.run(qualify(args.url, args.password))
    except Exception as exc:  # qualification utility: concise diagnostic is intentional
        print(f"relay qualification failed: {exc}", file=sys.stderr)
        return 1

    print(f"relay qualification passed: {args.url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
