#!/usr/bin/env python3
"""Qualify Glowing Bear in a real browser against a WeeChat websocket relay."""

import argparse
import asyncio
import sys

from playwright.async_api import Error as PlaywrightError
from playwright.async_api import async_playwright


async def goto_with_network_retry(page, base_url: str) -> None:
    for attempt in range(3):
        try:
            await page.goto(base_url, wait_until="networkidle", timeout=30_000)
            return
        except PlaywrightError as exc:
            if "ERR_NETWORK_CHANGED" not in str(exc) or attempt == 2:
                raise
            await asyncio.sleep(1)


async def qualify(
    base_url: str,
    relay_host: str,
    relay_port: int,
    password: str,
    tls_enabled: bool,
    ignore_https_errors: bool,
) -> None:
    websocket_urls: list[str] = []

    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        context = await browser.new_context(ignore_https_errors=ignore_https_errors)
        page = await context.new_page()

        page.on("websocket", lambda ws: websocket_urls.append(ws.url))

        try:
            await goto_with_network_retry(page, base_url)
            await page.locator("#host").fill(relay_host)
            await page.locator("#port").fill(str(relay_port))
            await page.locator("#password").fill(password)

            tls = page.locator("#tls")
            if tls_enabled and not await tls.is_checked():
                await tls.check()
            elif not tls_enabled and await tls.is_checked():
                await tls.uncheck()

            await page.locator('button[ng-click="connect()"]:visible').click()

            websocket_scheme = "wss" if tls_enabled else "ws"
            expected_ws = f"{websocket_scheme}://{relay_host}:{relay_port}/weechat"
            for _ in range(100):
                if expected_ws in websocket_urls:
                    break
                await asyncio.sleep(0.1)
            else:
                raise RuntimeError(
                    f"Glowing Bear did not open expected websocket {expected_ws}; saw {websocket_urls!r}"
                )

            await page.wait_for_function(
                "document.body.classList.contains('no-overflow')",
                timeout=15_000,
            )

            if await page.locator(".alert.alert-danger:visible").count():
                texts = await page.locator(".alert.alert-danger:visible").all_inner_texts()
                raise RuntimeError(f"Glowing Bear displayed an error after connecting: {texts!r}")
        finally:
            await context.close()
            await browser.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:18080/")
    parser.add_argument("--relay-host", default="127.0.0.1")
    parser.add_argument("--relay-port", type=int, default=19001)
    parser.add_argument("--password", required=True)
    parser.add_argument("--tls", action="store_true")
    parser.add_argument("--ignore-https-errors", action="store_true")
    args = parser.parse_args()

    try:
        asyncio.run(
            qualify(
                args.base_url,
                args.relay_host,
                args.relay_port,
                args.password,
                args.tls,
                args.ignore_https_errors,
            )
        )
    except Exception as exc:
        print(f"browser relay qualification failed: {exc}", file=sys.stderr)
        return 1

    websocket_scheme = "wss" if args.tls else "ws"
    print(
        "browser relay qualification passed: "
        f"{args.base_url} -> {websocket_scheme}://{args.relay_host}:{args.relay_port}/weechat"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
