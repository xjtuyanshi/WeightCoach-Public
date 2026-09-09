import importlib.util
import io
import json
import pathlib
import sys
import unittest
from contextlib import redirect_stderr
from unittest import mock


BRIDGE_DIR = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_serve_port", BRIDGE_DIR / "check_serve_port.py"
)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


HOST_PORT = "bridge.example.test:8443"
EXPECTED_TARGET = "http://127.0.0.1:8765"


def exact_route() -> dict:
    return {
        "TCP": {"8443": {"HTTPS": True}},
        "Web": {
            HOST_PORT: {
                "Handlers": {"/": {"Proxy": EXPECTED_TARGET}},
            }
        },
    }


class InstallScriptRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = (
            BRIDGE_DIR / "install.sh"
        ).read_text(encoding="utf-8")

    def test_uses_dedicated_https_port(self) -> None:
        self.assertIn(
            'TAILSCALE_HTTPS_PORT="${WEIGHTCOACH_TAILSCALE_HTTPS_PORT:-8443}"',
            self.script,
        )
        self.assertIn('--https="$TAILSCALE_HTTPS_PORT"', self.script)
        self.assertIn('"$EXPECTED_SERVE_TARGET"', self.script)

    def test_health_check_and_printed_url_include_dedicated_port(self) -> None:
        self.assertIn(
            'BRIDGE_BASE_URL="https://$DNS_NAME:$TAILSCALE_HTTPS_PORT"',
            self.script,
        )
        self.assertIn('"$BRIDGE_BASE_URL/health"', self.script)

    def test_never_resets_or_reclaims_default_serve_route(self) -> None:
        self.assertNotIn("serve reset", self.script)
        self.assertNotIn('serve --yes --bg 8765', self.script)

    def test_fails_closed_when_dedicated_port_is_occupied(self) -> None:
        self.assertIn('"$SOURCE_DIR/check_serve_port.py"', self.script)
        self.assertIn("未通过安全检查", self.script)

    def test_first_preflight_runs_before_tests_and_all_writes(self) -> None:
        preflight = self.script.index("if ! check_serve_port_safely")
        for later_operation in (
            "/usr/bin/python3 -m unittest",
            "/usr/bin/install -d",
            "/usr/bin/sed",
            "/bin/launchctl",
            '"$TAILSCALE" serve --yes',
        ):
            self.assertLess(preflight, self.script.index(later_operation))
        self.assertIn("set -euo pipefail", self.script)

    def test_rechecks_immediately_before_serve(self) -> None:
        preflight_call = "if ! check_serve_port_safely"
        self.assertEqual(self.script.count(preflight_call), 2)
        final_preflight = self.script.rindex(preflight_call)
        serve = self.script.index('"$TAILSCALE" serve --yes')
        self.assertLess(final_preflight, serve)
        between = self.script[final_preflight:serve]
        for mutating_operation in (
            "/usr/bin/install",
            "/usr/bin/sed",
            "/bin/launchctl",
            "/usr/bin/curl",
        ):
            self.assertNotIn(mutating_operation, between)
        self.assertIn("配置发生变化", between)


class ServePortCheckerTests(unittest.TestCase):
    def assert_safe(self, config, expected_message: str) -> None:
        safe, message = CHECKER.check_config(
            config, HOST_PORT, EXPECTED_TARGET
        )
        self.assertTrue(safe, message)
        self.assertEqual(message, expected_message)

    def assert_rejected(self, config) -> None:
        safe, message = CHECKER.check_config(
            config, HOST_PORT, EXPECTED_TARGET
        )
        self.assertFalse(safe, message)

    def test_empty_or_null_config_is_free(self) -> None:
        for config in ({}, None):
            with self.subTest(config=config):
                self.assert_safe(config, "free")

    def test_exact_existing_route_is_idempotent(self) -> None:
        self.assert_safe(exact_route(), "existing")

    def test_other_port_does_not_conflict(self) -> None:
        self.assert_safe(
            {
                "TCP": {"443": {"HTTPS": True}},
                "Web": {
                    "other.example.test:443": {
                        "Handlers": {
                            "/": {"Proxy": "http://127.0.0.1:8788"}
                        }
                    }
                },
            },
            "free",
        )

    def test_rejects_different_proxy(self) -> None:
        config = exact_route()
        config["Web"][HOST_PORT]["Handlers"]["/"]["Proxy"] = (
            "http://127.0.0.1:9999"
        )
        self.assert_rejected(config)

    def test_rejects_non_proxy_root_handlers(self) -> None:
        handlers = (
            {"Path": "/tmp/site"},
            {"Text": "occupied"},
            {"Redirect": "https://example.test"},
        )
        for handler in handlers:
            with self.subTest(handler=handler):
                config = exact_route()
                config["Web"][HOST_PORT]["Handlers"]["/"] = handler
                self.assert_rejected(config)

    def test_rejects_extra_web_handler(self) -> None:
        config = exact_route()
        config["Web"][HOST_PORT]["Handlers"]["/api"] = {
            "Proxy": EXPECTED_TARGET
        }
        self.assert_rejected(config)

    def test_rejects_another_web_host_on_same_port(self) -> None:
        config = exact_route()
        config["Web"]["other.example.test:8443"] = {
            "Handlers": {"/": {"Proxy": EXPECTED_TARGET}}
        }
        self.assert_rejected(config)

    def test_rejects_http_or_tcp_forward(self) -> None:
        for tcp_handler in (
            {"HTTP": True},
            {"TCPForward": "127.0.0.1:9999"},
        ):
            with self.subTest(tcp_handler=tcp_handler):
                config = exact_route()
                config["TCP"]["8443"] = tcp_handler
                self.assert_rejected(config)

    def test_rejects_funnel_even_when_disabled(self) -> None:
        for enabled in (True, False):
            with self.subTest(enabled=enabled):
                config = exact_route()
                config["AllowFunnel"] = {HOST_PORT: enabled}
                self.assert_rejected(config)

    def test_rejects_foreground_claim(self) -> None:
        config = {}
        config["Foreground"] = {"1234": exact_route()}
        self.assert_rejected(config)

    def test_rejects_malformed_known_sections(self) -> None:
        malformed_configs = (
            {"TCP": []},
            {"Web": []},
            {"AllowFunnel": []},
            {"Foreground": []},
            {"Foreground": {"1234": []}},
            {"Foreground": {"1234": {"TCP": []}}},
        )
        for config in malformed_configs:
            with self.subTest(config=config):
                self.assert_rejected(config)

    def test_main_rejects_invalid_json(self) -> None:
        stderr = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            with redirect_stderr(stderr):
                result = CHECKER.main([HOST_PORT, EXPECTED_TARGET])
        self.assertEqual(result, 1)
        self.assertIn("无法验证", stderr.getvalue())

    def test_main_rejects_non_object_json(self) -> None:
        stderr = io.StringIO()
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps([]))):
            with redirect_stderr(stderr):
                result = CHECKER.main([HOST_PORT, EXPECTED_TARGET])
        self.assertEqual(result, 1)
        self.assertIn("不是 JSON 对象", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
