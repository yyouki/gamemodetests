#!/usr/bin/env python3
"""Boot the packaged open.mp server and verify the test gamemode loads."""

from __future__ import annotations

import argparse
import signal
import subprocess
import sys
import time
from pathlib import Path

BOOT_MARKER = "[AC-TEST] Gamemode initialized."


def read_available_logs(server_root: Path, stdout_log: Path) -> str:
    chunks: list[str] = []
    for path in (stdout_log, server_root / "gamemodetests.log"):
        try:
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
        except FileNotFoundError:
            continue
        except OSError as error:
            chunks.append(f"\n[log read error: {error}]\n")
    return "\n".join(chunks)


def stop_server(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        process.send_signal(signal.SIGINT)
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-root", required=True, type=Path)
    parser.add_argument("--startup-timeout", type=float, default=25.0)
    parser.add_argument("--post-boot-seconds", type=float, default=2.0)
    args = parser.parse_args()

    server_root = args.server_root.resolve()
    server_binary = server_root / "omp-server"
    gamemode = server_root / "gamemodes" / "ac-test.amx"
    config = server_root / "config.json"
    if not server_binary.is_file():
        print(f"open.mp server executable not found: {server_binary}", file=sys.stderr)
        return 2
    if not gamemode.is_file() or not config.is_file():
        print("test AMX or config.json is missing from the server root", file=sys.stderr)
        return 2

    stdout_log = server_root / "gamemodetests-runtime.stdout.log"
    with stdout_log.open("w", encoding="utf-8", buffering=1) as output:
        try:
            process = subprocess.Popen(
                [str(server_binary)],
                cwd=server_root,
                stdin=subprocess.DEVNULL,
                stdout=output,
                stderr=subprocess.STDOUT,
                text=True,
            )
        except OSError as error:
            print(f"could not start open.mp server: {error}", file=sys.stderr)
            return 2

        try:
            deadline = time.monotonic() + args.startup_timeout
            while time.monotonic() < deadline:
                logs = read_available_logs(server_root, stdout_log)
                if BOOT_MARKER in logs:
                    break
                exit_code = process.poll()
                if exit_code is not None:
                    print(f"open.mp exited before loading the test gamemode (exit {exit_code})", file=sys.stderr)
                    print(logs[-12000:], file=sys.stderr)
                    return 1
                time.sleep(0.25)
            else:
                logs = read_available_logs(server_root, stdout_log)
                print("timed out waiting for the test gamemode boot marker", file=sys.stderr)
                print(logs[-12000:], file=sys.stderr)
                return 1

            time.sleep(max(0.0, args.post_boot_seconds))
            exit_code = process.poll()
            if exit_code is not None:
                logs = read_available_logs(server_root, stdout_log)
                print(f"open.mp exited after loading the test gamemode (exit {exit_code})", file=sys.stderr)
                print(logs[-12000:], file=sys.stderr)
                return 1

            print("PASS: open.mp started and loaded the anti-cheat test gamemode.")
            return 0
        finally:
            stop_server(process)


if __name__ == "__main__":
    raise SystemExit(main())
