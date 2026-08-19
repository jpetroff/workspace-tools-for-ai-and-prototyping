#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    from playwright.sync_api import Error as PlaywrightError
    from playwright.sync_api import sync_playwright
except ModuleNotFoundError:
    PlaywrightError = RuntimeError
    sync_playwright = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch a persistent headed browser on the workspace display."
    )
    parser.add_argument("--url", default="about:blank")
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ":0"))
    parser.add_argument("--cdp-port", type=int, default=9222)
    parser.add_argument(
        "--profile",
        default="~/.local/share/playwright-browser-profile",
    )
    parser.add_argument("--slow-mo", type=float, default=0)
    parser.add_argument(
        "--channel",
        choices=("bundled", "chrome", "chrome-beta", "chrome-dev"),
        default="bundled",
    )
    return parser.parse_args()


def display_size(display: str) -> tuple[int, int]:
    try:
        result = subprocess.run(
            ["xdpyinfo", "-display", display],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(
            f"Cannot query {display}; run 'workspace-desktop start' first."
        ) from exc
    match = re.search(r"dimensions:\s+(\d+)x(\d+)\s+pixels", result.stdout)
    if match is None:
        raise RuntimeError(f"Cannot determine the dimensions of {display}.")
    return int(match.group(1)), int(match.group(2))


def main() -> int:
    args = parse_args()
    if sync_playwright is None:
        print(
            "Playwright is not installed in the active Python environment. "
            "Install the project version and its browser first.",
            file=sys.stderr,
        )
        return 2
    os.environ["DISPLAY"] = args.display
    profile = Path(args.profile).expanduser().resolve()
    profile.mkdir(parents=True, exist_ok=True)

    try:
        width, height = display_size(args.display)
        launch_options: dict[str, object] = {
            "user_data_dir": str(profile),
            "headless": False,
            "no_viewport": True,
            "slow_mo": args.slow_mo,
            "args": [
                "--remote-debugging-address=127.0.0.1",
                f"--remote-debugging-port={args.cdp_port}",
                "--window-position=0,0",
                f"--window-size={width},{height}",
                "--start-maximized",
                "--force-device-scale-factor=1",
                "--no-first-run",
                "--no-default-browser-check",
            ],
        }
        if args.channel != "bundled":
            launch_options["channel"] = args.channel

        with sync_playwright() as playwright:
            context = playwright.chromium.launch_persistent_context(**launch_options)
            page = context.pages[0] if context.pages else context.new_page()
            if args.url != "about:blank":
                page.goto(args.url, wait_until="domcontentloaded")
            try:
                while context.pages:
                    try:
                        context.pages[0].wait_for_timeout(500)
                    except PlaywrightError:
                        pass
            except KeyboardInterrupt:
                context.close()
    except (PlaywrightError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
