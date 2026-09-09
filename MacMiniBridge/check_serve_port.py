#!/usr/bin/env python3
"""Fail-closed validation for WeightCoach's dedicated Tailscale Serve port."""

from __future__ import annotations

import json
import sys
from typing import Any


def _port_from_host_port(host_port: str) -> str:
    try:
        _, port_text = host_port.rsplit(":", 1)
        port = int(port_text)
    except (TypeError, ValueError) as error:
        raise ValueError("host:port 参数无效") from error

    if not 1 <= port <= 65535:
        raise ValueError("host:port 端口必须在 1 到 65535 之间")
    return str(port)


def _uses_port(key: Any, port: str) -> bool:
    return isinstance(key, str) and key.rsplit(":", 1)[-1] == port


def _claims_port(config: Any, port: str) -> bool:
    """Return whether one ServeConfig claims the node port in any way."""
    if not isinstance(config, dict):
        return False

    tcp = config.get("TCP")
    if isinstance(tcp, dict) and port in tcp:
        return True

    for section_name in ("Web", "AllowFunnel"):
        section = config.get(section_name)
        if isinstance(section, dict) and any(
            _uses_port(key, port) for key in section
        ):
            return True

    foreground = config.get("Foreground")
    if isinstance(foreground, dict):
        return any(_claims_port(child, port) for child in foreground.values())
    return False


def _shape_error(config: dict[str, Any], path: str = "root") -> str | None:
    """Reject malformed known fields instead of treating them as absent."""
    for section_name in ("TCP", "Web", "AllowFunnel", "Foreground"):
        if section_name in config and not isinstance(config[section_name], dict):
            return f"{path}.{section_name} 必须是 JSON 对象"

    foreground = config.get("Foreground", {})
    for name, child in foreground.items():
        if not isinstance(child, dict):
            return f"{path}.Foreground[{name!r}] 必须是 JSON 对象"
        if error := _shape_error(child, f"{path}.Foreground[{name!r}]"):
            return error
    return None


def check_config(
    config: Any, host_port: str, expected_target: str
) -> tuple[bool, str]:
    """Accept only a free port or the exact existing WeightCoach route."""
    port = _port_from_host_port(host_port)

    if config is None:
        config = {}
    if not isinstance(config, dict):
        return False, "Tailscale Serve 状态不是 JSON 对象"
    if error := _shape_error(config):
        return False, f"Tailscale Serve 状态结构无效：{error}"

    foreground = config.get("Foreground")
    if isinstance(foreground, dict) and any(
        _claims_port(child, port) for child in foreground.values()
    ):
        return False, f"HTTPS {port} 已被前台 Serve 配置占用"

    allow_funnel = config.get("AllowFunnel")
    if isinstance(allow_funnel, dict) and any(
        _uses_port(key, port) for key in allow_funnel
    ):
        return False, f"HTTPS {port} 存在 Funnel 配置"

    tcp = config.get("TCP")
    tcp_for_port = tcp.get(port) if isinstance(tcp, dict) else None
    tcp_claimed = isinstance(tcp, dict) and port in tcp

    web = config.get("Web")
    web_for_port = (
        {key: value for key, value in web.items() if _uses_port(key, port)}
        if isinstance(web, dict)
        else {}
    )

    if not tcp_claimed and not web_for_port:
        return True, "free"

    expected_tcp = {"HTTPS": True}
    expected_web = {
        "Handlers": {"/": {"Proxy": expected_target}},
    }
    if tcp_for_port != expected_tcp:
        return False, f"端口 {port} 已存在非 WeightCoach 的 TCP 配置"
    if set(web_for_port) != {host_port}:
        return False, f"端口 {port} 已存在其他主机或 Web 路由"
    if web_for_port.get(host_port) != expected_web:
        return False, f"端口 {port} 已存在不同的 Web 处理器"

    return True, "existing"


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        print(
            "用法: check_serve_port.py <host:port> <expected-target>",
            file=sys.stderr,
        )
        return 2

    try:
        config = json.load(sys.stdin)
        safe, message = check_config(config, args[0], args[1])
    except (json.JSONDecodeError, OSError, ValueError) as error:
        print(f"无法验证 Tailscale Serve 状态：{error}", file=sys.stderr)
        return 1

    if not safe:
        print(f"拒绝修改 Tailscale Serve：{message}", file=sys.stderr)
        return 1

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
