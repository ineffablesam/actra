#!/usr/bin/env python3
"""
Start ngrok with two tunnels (FastAPI HTTP + WebSocket), write public URLs into .env,
and print Flutter --dart-define lines.

Requires: `ngrok` on PATH, backend listening on localhost (see HTTP_PORT / WS_PORT in .env).

The script merges your **saved** ngrok config (where `ngrok config add-authtoken` stores the token)
with the generated tunnel file. Using only the generated file would omit the authtoken (4018).

Usage (from actra-backend directory):
  python scripts/ngrok_dev.py

  # Do not modify .env; only print URLs and flutter args
  python scripts/ngrok_dev.py --print-only
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

try:
    import httpx
except ImportError:
    print("Install dependencies: pip install httpx", file=sys.stderr)
    sys.exit(1)

try:
    from dotenv import dotenv_values
except ImportError:
    dotenv_values = None  # type: ignore[assignment]

BACKEND_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ENV = BACKEND_ROOT / ".env"
GENERATED_CONFIG = BACKEND_ROOT / ".ngrok.generated.yml"

NGROK_API = "http://127.0.0.1:4040/api/tunnels"

MARKER_START = "# <actra ngrok>"
MARKER_END = "# </actra ngrok>"


def _load_ports(env_path: Path) -> tuple[int, int]:
    http_port, ws_port = 8000, 8765
    if dotenv_values is None:
        return http_port, ws_port
    data = dotenv_values(env_path)
    if not data:
        return http_port, ws_port
    try:
        if data.get("HTTP_PORT"):
            http_port = int(str(data["HTTP_PORT"]).strip())
    except ValueError:
        pass
    try:
        if data.get("WS_PORT"):
            ws_port = int(str(data["WS_PORT"]).strip())
    except ValueError:
        pass
    return http_port, ws_port


def _discover_user_ngrok_configs() -> list[Path]:
    """Paths where `ngrok config add-authtoken` usually stores credentials."""
    found: list[Path] = []
    override = os.environ.get("NGROK_CONFIG")
    if override:
        p = Path(override).expanduser().resolve()
        if p.is_file():
            found.append(p)
    for p in (
        Path.home() / ".ngrok2" / "ngrok.yml",
        Path.home() / ".config" / "ngrok" / "ngrok.yml",
        # macOS default when using `ngrok config add-authtoken` (ngrok v3 agent)
        Path.home() / "Library" / "Application Support" / "ngrok" / "ngrok.yml",
    ):
        if p.is_file() and p.resolve() not in found:
            found.append(p.resolve())
    return found


def _load_ngrok_authtoken_fallback(env_path: Path) -> str | None:
    """Token from env or .env when no user ngrok.yml is merged (optional)."""
    t = os.environ.get("NGROK_AUTHTOKEN", "").strip()
    if t:
        return t
    if dotenv_values is None:
        return None
    data = dotenv_values(env_path)
    if not data:
        return None
    v = data.get("NGROK_AUTHTOKEN")
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def _write_ngrok_config(
    path: Path,
    http_port: int,
    ws_port: int,
    *,
    authtoken: str | None = None,
) -> None:
    # v2 agent config; works with common ngrok 3.x agents in "v2 compatibility" mode.
    lines = [
        'version: "2"',
    ]
    if authtoken:
        lines.append(f"authtoken: {authtoken}")
    lines.extend(
        [
            "tunnels:",
            "  actra_http:",
            "    proto: http",
            f"    addr: {http_port}",
            "  actra_ws:",
            "    proto: http",
            f"    addr: {ws_port}",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _https_to_wss(url: str) -> str:
    if url.startswith("https://"):
        return "wss://" + url[len("https://") :]
    if url.startswith("http://"):
        return "ws://" + url[len("http://") :]
    return url


def _wait_for_tunnels(
    *,
    want_names: set[str],
    timeout_s: float = 45.0,
    interval_s: float = 0.4,
) -> dict[str, str]:
    deadline = time.monotonic() + timeout_s
    last_err: str | None = None
    while time.monotonic() < deadline:
        try:
            r = httpx.get(NGROK_API, timeout=2.0)
            r.raise_for_status()
            data = r.json()
            tunnels = data.get("tunnels") or []
            by_name: dict[str, str] = {}
            for t in tunnels:
                if not isinstance(t, dict):
                    continue
                name = str(t.get("name") or "")
                pub = str(t.get("public_url") or "")
                if name and pub:
                    by_name[name] = pub
            if want_names <= by_name.keys():
                return by_name
        except Exception as e:
            last_err = str(e)
        time.sleep(interval_s)
    msg = "Timed out waiting for ngrok tunnels."
    if last_err:
        msg += f" Last error: {last_err}"
    raise RuntimeError(msg)


def _patch_env_file(
    env_path: Path,
    *,
    http_url: str,
    ws_url: str,
) -> None:
    block = (
        f"{MARKER_START}\n"
        f"# Managed by scripts/ngrok_dev.py — safe to delete this block\n"
        f"NGROK_HTTP_PUBLIC_URL={http_url}\n"
        f"NGROK_WS_PUBLIC_URL={ws_url}\n"
        f"{MARKER_END}\n"
    )
    if not env_path.is_file():
        env_path.write_text(block, encoding="utf-8")
        return
    raw = env_path.read_text(encoding="utf-8")
    pattern = re.compile(
        re.escape(MARKER_START) + r"[\s\S]*?" + re.escape(MARKER_END) + r"\n?",
        re.MULTILINE,
    )
    if pattern.search(raw):
        new_raw = pattern.sub(block.rstrip() + "\n", raw)
    else:
        sep = "\n" if raw and not raw.endswith("\n") else ""
        new_raw = raw + sep + block
    env_path.write_text(new_raw, encoding="utf-8")


def _print_flutter_dart_defines(http_url: str, ws_url: str) -> None:
    # Flutter app reads WS_URL and MEMORY_API_BASE_URL (see lib/core/env.dart).
    print()
    print("— Flutter (copy-paste) —")
    print(
        "flutter run \\\n"
        f'  --dart-define=WS_URL={ws_url} \\\n'
        f"  --dart-define=MEMORY_API_BASE_URL={http_url}"
    )
    print()
    print("— Values —")
    print(f"  WS_URL              = {ws_url}")
    print(f"  MEMORY_API_BASE_URL = {http_url}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run ngrok for Actra HTTP + WebSocket and sync .env.")
    parser.add_argument(
        "--env-file",
        type=Path,
        default=DEFAULT_ENV,
        help=f"Path to .env (default: {DEFAULT_ENV})",
    )
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Do not write .env; only start ngrok and print URLs (still updates nothing on disk).",
    )
    parser.add_argument(
        "--config-out",
        type=Path,
        default=GENERATED_CONFIG,
        help=f"Where to write generated ngrok YAML (default: {GENERATED_CONFIG})",
    )
    args = parser.parse_args()

    if shutil.which("ngrok") is None:
        print(
            "ngrok not found on PATH. Install: https://ngrok.com/download",
            file=sys.stderr,
        )
        sys.exit(1)

    env_path = args.env_file.resolve()
    http_port, ws_port = _load_ports(env_path)

    # Passing only our generated --config replaces the default config and drops authtoken
    # (ERR_NGROK_4018). Merge user config(s) first, then tunnels-only file.
    user_cfgs = _discover_user_ngrok_configs()
    token_fallback = _load_ngrok_authtoken_fallback(env_path)
    if user_cfgs:
        _write_ngrok_config(args.config_out, http_port, ws_port)
    elif token_fallback:
        _write_ngrok_config(
            args.config_out, http_port, ws_port, authtoken=token_fallback
        )
    else:
        _write_ngrok_config(args.config_out, http_port, ws_port)

    cmd: list[str] = ["ngrok", "start", "--all"]
    for p in user_cfgs:
        cmd.extend(["--config", str(p)])
    cmd.extend(["--config", str(args.config_out)])

    print(f"Starting ngrok: HTTP → localhost:{http_port}, WebSocket → localhost:{ws_port}")
    if user_cfgs:
        print("Merging ngrok authtoken from:", ", ".join(str(p) for p in user_cfgs))
    elif token_fallback:
        print("Using NGROK_AUTHTOKEN from environment / .env (no user ngrok.yml found).")
    else:
        print(
            "Warning: no ngrok user config found (e.g. ~/Library/Application Support/ngrok/ngrok.yml on macOS) and no NGROK_AUTHTOKEN.",
            file=sys.stderr,
        )
        print(
            "  Run: ngrok config add-authtoken <token>   or set NGROK_AUTHTOKEN in .env",
            file=sys.stderr,
        )
    print(f"Tunnels config: {args.config_out}")
    proc = subprocess.Popen(
        cmd,
        cwd=str(BACKEND_ROOT),
        stdout=subprocess.DEVNULL,
        stderr=None,
    )

    def _stop(*_: object) -> None:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    try:
        want = {"actra_http", "actra_ws"}
        by_name = _wait_for_tunnels(want_names=want)
        http_public = by_name["actra_http"]
        ws_public_https = by_name["actra_ws"]
        ws_url = _https_to_wss(ws_public_https)

        if not args.print_only:
            _patch_env_file(env_path, http_url=http_public, ws_url=ws_url)
            print(f"Updated {env_path} ({MARKER_START} … {MARKER_END})")
        else:
            print("(print-only: .env not modified)")

        _print_flutter_dart_defines(http_public, ws_url)

        print("ngrok running. Ctrl+C to stop.")
        proc.wait()
    except Exception as e:
        _stop()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if proc.poll() is None:
            proc.terminate()


if __name__ == "__main__":
    main()
