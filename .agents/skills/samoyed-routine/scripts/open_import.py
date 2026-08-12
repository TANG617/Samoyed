#!/usr/bin/env python3
"""在 iOS 模拟器中打开 Samoyed 的远程 Routine 导入预览。"""

from __future__ import annotations

import argparse
import http.server
import secrets
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlencode, urlparse


MAXIMUM_BYTES = 512 * 1024


def make_deeplink(remote_url: str, title: str) -> str:
    query = urlencode({"url": remote_url, "title": title})
    return f"samoyed://import-routine?{query}"


def validate_remote_url(remote_url: str) -> None:
    parsed = urlparse(remote_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("远程 URL 必须使用 http 或 https，并包含主机名")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("远程 URL 不能嵌入用户名或密码")
    if parsed.scheme == "http" and parsed.hostname not in {"localhost", "127.0.0.1", "::1"}:
        raise ValueError("不支持公共 HTTP URL，请使用 HTTPS")


def open_simulator_url(device: str, deeplink: str) -> None:
    xcrun = shutil.which("xcrun")
    if xcrun is None:
        raise RuntimeError("未找到 xcrun，请安装 Xcode Command Line Tools")
    result = subprocess.run(
        [xcrun, "simctl", "openurl", device, deeplink],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "simctl openurl failed"
        raise RuntimeError(message)


def serve_once_and_open(yaml_data: bytes, title: str, device: str, timeout: float) -> str:
    token = secrets.token_urlsafe(18)
    expected_path = f"/{token}/routine.yml"

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - inherited API name
            if self.path != expected_path:
                self.send_error(404)
                return
            self.server.served = True  # type: ignore[attr-defined]
            self.send_response(200)
            self.send_header("Content-Type", "application/yaml; charset=utf-8")
            self.send_header("Content-Length", str(len(yaml_data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(yaml_data)

        def log_message(self, _format: str, *args: object) -> None:
            return

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    server.timeout = timeout
    server.served = False  # type: ignore[attr-defined]
    remote_url = f"http://127.0.0.1:{server.server_port}{expected_path}"
    deeplink = make_deeplink(remote_url, title)
    try:
        open_simulator_url(device, deeplink)
        server.handle_request()
        if not server.served:  # type: ignore[attr-defined]
            raise TimeoutError(f"Samoyed 未在 {timeout:g} 秒内请求 YAML")
    finally:
        server.server_close()
    return deeplink


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("yaml", type=Path, help="已生成的 Samoyed YAML")
    parser.add_argument("--title", help="建议的 Routine 名称")
    parser.add_argument("--url", help="已托管的 HTTPS YAML URL")
    parser.add_argument("--device", default="booted", help="模拟器 UDID 或 'booted'")
    parser.add_argument("--timeout", type=float, default=30, help="localhost 请求超时时间")
    parser.add_argument("--print-only", action="store_true", help="只打印已托管 URL 的 deeplink，不打开模拟器")
    args = parser.parse_args()

    try:
        yaml_data = args.yaml.read_bytes()
        if len(yaml_data) > MAXIMUM_BYTES:
            raise ValueError("YAML 超过 Samoyed 的 512 KB 导入限制")
        yaml_data.decode("utf-8")
        title = (args.title or args.yaml.stem.replace("-", " ").replace("_", " ")).strip()
        if not title:
            raise ValueError("Routine 名称不能为空")

        if args.url:
            validate_remote_url(args.url)
            deeplink = make_deeplink(args.url, title)
            if not args.print_only:
                open_simulator_url(args.device, deeplink)
        else:
            if args.print_only:
                raise ValueError("--print-only 必须与 --url 一起使用，因为 localhost 服务器需要持续运行")
            deeplink = serve_once_and_open(yaml_data, title, args.device, args.timeout)
    except (OSError, UnicodeDecodeError, ValueError, RuntimeError, TimeoutError) as error:
        print(f"错误：{error}", file=sys.stderr)
        return 2

    print(deeplink)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
