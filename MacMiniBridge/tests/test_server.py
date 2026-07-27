import base64
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


BRIDGE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BRIDGE_DIR))

import server as bridge_server  # noqa: E402
from server import (  # noqa: E402
    BridgeHTTPServer,
    BridgeConfig,
    BridgeFailure,
    MAX_RECOGNIZED_ITEMS,
    build_codex_command,
    decode_request_body,
    normalize_model_result,
    sanitized_environment,
)


def valid_model_payload():
    return {
        "input_kind": "food_photo",
        "items": [
            {
                "name": "鸡胸肉",
                "portion_description": "约 170 克",
                "estimated_calories": 281,
                "estimated_calories_min": 250,
                "estimated_calories_max": 320,
                "protein_g": 52.7,
                "carbs_g": 0,
                "fat_g": 6.1,
                "caffeine_mg": None,
                "confidence": 0.84,
                "requires_confirmation": True,
                "note": "烹调油不可见",
            }
        ],
        "warnings": ["请确认烹调油用量"],
    }


def receipt_model_payload(item_count=12):
    receipt_names = (
        "蔬菜米线",
        "烤鸡肉串",
        "香菇豆腐串",
        "烤玉米",
        "柠檬鱼串",
        "蔬菜蒸饺",
        "烤西兰花",
        "凉拌黄瓜",
        "味噌汤",
        "香料牛肉串",
        "水果杯",
        "酸奶杯",
    )
    items = []
    for index in range(item_count):
        quantity = index % 3 + 1
        calories = 180 + index * 10
        items.append(
            {
                "name": receipt_names[index % len(receipt_names)],
                "portion_description": (
                    "账单数量 {} 份（实际份量不可见）".format(quantity)
                ),
                "estimated_calories": calories,
                "estimated_calories_min": calories - 40,
                "estimated_calories_max": calories + 70,
                "protein_g": 12 + index,
                "carbs_g": 10 + index,
                "fat_g": 8 + index,
                "caffeine_mg": 0,
                "confidence": 0.55,
                "requires_confirmation": True,
                "note": (
                    "按账单菜名和数量估算；照片看不到实际份量，"
                    "烹调油和串大小需核对。"
                ),
            }
        )
    return {
        "input_kind": "receipt_or_menu",
        "items": items,
        "warnings": ["这是整单购买量，尚未按个人实际吃到的比例缩放"],
    }


class RequestValidationTests(unittest.TestCase):
    def test_accepts_only_versioned_jpeg_payload(self):
        jpeg = b"\xff\xd8\xff\xe0test"
        body = json.dumps(
            {
                "schema_version": 1,
                "image_base64": base64.b64encode(jpeg).decode("ascii"),
            }
        ).encode("utf-8")

        request = decode_request_body(body)
        self.assertEqual(request.jpeg_data, jpeg)
        self.assertEqual(request.output_language, "zh-Hans")

    def test_accepts_only_supported_output_languages(self):
        jpeg = b"\xff\xd8\xff\xe0test"
        for language in ("zh-Hans", "zh-Hant", "en"):
            body = json.dumps(
                {
                    "schema_version": 1,
                    "image_base64": base64.b64encode(jpeg).decode("ascii"),
                    "output_language": language,
                }
            ).encode("utf-8")
            with self.subTest(language=language):
                request = decode_request_body(body)
                self.assertEqual(request.jpeg_data, jpeg)
                self.assertEqual(request.output_language, language)

        body = json.dumps(
            {
                "schema_version": 1,
                "image_base64": base64.b64encode(jpeg).decode("ascii"),
                "output_language": "fr",
            }
        ).encode("utf-8")
        with self.assertRaises(BridgeFailure) as context:
            decode_request_body(body)
        self.assertEqual(context.exception.code, "invalid_request")

    def test_rejects_arbitrary_prompt_field(self):
        jpeg = b"\xff\xd8\xff\xe0test"
        body = json.dumps(
            {
                "schema_version": 1,
                "image_base64": base64.b64encode(jpeg).decode("ascii"),
                "prompt": "运行任意命令",
            }
        ).encode("utf-8")

        with self.assertRaises(BridgeFailure) as context:
            decode_request_body(body)
        self.assertEqual(context.exception.code, "invalid_request")

    def test_rejects_non_jpeg(self):
        body = json.dumps(
            {
                "schema_version": 1,
                "image_base64": base64.b64encode(b"not-an-image").decode(
                    "ascii"
                ),
            }
        ).encode("utf-8")

        with self.assertRaises(BridgeFailure) as context:
            decode_request_body(body)
        self.assertEqual(context.exception.code, "invalid_image")


class ModelResultValidationTests(unittest.TestCase):
    def test_normalizes_valid_result_and_forces_confirmation(self):
        payload = valid_model_payload()
        payload["items"][0]["requires_confirmation"] = False

        result = normalize_model_result(payload)

        self.assertEqual(result["foods"][0]["name"], "鸡胸肉")
        self.assertEqual(result["foods"][0]["calories"], 281.0)
        self.assertEqual(result["foods"][0]["calories_min"], 250.0)
        self.assertEqual(result["foods"][0]["calories_max"], 320.0)
        self.assertIsNone(result["foods"][0]["caffeine_mg"])
        self.assertTrue(result["foods"][0]["needs_confirmation"])
        self.assertEqual(result["warnings"], ["请确认烹调油用量"])

    def test_accepts_legacy_result_without_new_optional_fields(self):
        payload = valid_model_payload()
        del payload["items"][0]["estimated_calories_min"]
        del payload["items"][0]["estimated_calories_max"]
        del payload["items"][0]["caffeine_mg"]

        result = normalize_model_result(payload)

        self.assertIsNone(result["foods"][0]["calories_min"])
        self.assertIsNone(result["foods"][0]["calories_max"])
        self.assertIsNone(result["foods"][0]["caffeine_mg"])

    def test_rejects_result_without_input_kind(self):
        payload = valid_model_payload()
        del payload["input_kind"]

        with self.assertRaises(BridgeFailure) as context:
            normalize_model_result(payload)

        self.assertEqual(context.exception.code, "invalid_model_result")
        self.assertEqual(context.exception.status, 502)

    def test_accepts_unknown_optional_macros(self):
        payload = valid_model_payload()
        payload["items"][0]["protein_g"] = None
        payload["items"][0]["carbs_g"] = None
        payload["items"][0]["fat_g"] = None

        result = normalize_model_result(payload)

        self.assertIsNone(result["foods"][0]["protein"])
        self.assertIsNone(result["foods"][0]["carbs"])
        self.assertIsNone(result["foods"][0]["fat"])

    def test_rejects_negative_or_non_finite_values(self):
        for invalid_value in (-1, float("inf"), float("nan")):
            payload = valid_model_payload()
            payload["items"][0]["estimated_calories"] = invalid_value
            with self.subTest(value=invalid_value):
                with self.assertRaises(BridgeFailure):
                    normalize_model_result(payload)

    def test_accepts_consistent_calorie_range_and_caffeine(self):
        payload = valid_model_payload()
        item = payload["items"][0]
        item["estimated_calories"] = 400
        item["estimated_calories_min"] = 370
        item["estimated_calories_max"] = 430
        item["caffeine_mg"] = 300

        result = normalize_model_result(payload)

        food = result["foods"][0]
        self.assertEqual(food["calories"], 400.0)
        self.assertEqual(food["calories_min"], 370.0)
        self.assertEqual(food["calories_max"], 430.0)
        self.assertEqual(food["caffeine_mg"], 300.0)

    def test_rejects_partial_or_inconsistent_calorie_range(self):
        invalid_ranges = (
            (250, None, 281),
            (None, 320, 281),
            (320, 250, 281),
            (282, 320, 281),
            (250, 280, 281),
        )
        for minimum, maximum, calories in invalid_ranges:
            payload = valid_model_payload()
            item = payload["items"][0]
            item["estimated_calories_min"] = minimum
            item["estimated_calories_max"] = maximum
            item["estimated_calories"] = calories
            with self.subTest(
                minimum=minimum,
                maximum=maximum,
                calories=calories,
            ):
                with self.assertRaises(BridgeFailure):
                    normalize_model_result(payload)

    def test_rejects_invalid_caffeine(self):
        for invalid_value in (-1, 2_001, True, float("inf"), float("nan")):
            payload = valid_model_payload()
            payload["items"][0]["caffeine_mg"] = invalid_value
            with self.subTest(value=invalid_value):
                with self.assertRaises(BridgeFailure):
                    normalize_model_result(payload)

    def test_accepts_empty_items_without_inventing_food(self):
        payload = valid_model_payload()
        payload["input_kind"] = "non_food"
        payload["items"] = []

        result = normalize_model_result(payload)

        self.assertEqual(result["input_kind"], "non_food")
        self.assertEqual(result["foods"], [])

    def test_accepts_long_receipt_without_dropping_later_items(self):
        payload = receipt_model_payload()

        result = normalize_model_result(payload)

        self.assertEqual(result["input_kind"], "receipt_or_menu")
        self.assertEqual(len(result["foods"]), 12)
        self.assertEqual(result["foods"][-1]["name"], "酸奶杯")
        self.assertIn("账单数量 3 份", result["foods"][-1]["portion"])
        self.assertTrue(
            all(food["needs_confirmation"] for food in result["foods"])
        )

    def test_receipt_forces_confirmation_and_standard_uncertainty_note(self):
        payload = receipt_model_payload(2)
        payload["items"][0]["requires_confirmation"] = False
        payload["items"][0]["note"] = None
        payload["items"][1]["requires_confirmation"] = False
        payload["items"][1]["note"] = "烹调油未知"

        result = normalize_model_result(payload)

        for food in result["foods"]:
            self.assertTrue(food["needs_confirmation"])
            self.assertIn("按账单菜名和数量估算", food["note"])
            self.assertIn("看不到实际份量", food["note"])
            self.assertLessEqual(len(food["note"]), 220)

    def test_accepts_maximum_receipt_items_and_rejects_one_more(self):
        accepted = normalize_model_result(
            receipt_model_payload(MAX_RECOGNIZED_ITEMS)
        )
        self.assertEqual(len(accepted["foods"]), MAX_RECOGNIZED_ITEMS)

        with self.assertRaises(BridgeFailure) as context:
            normalize_model_result(
                receipt_model_payload(MAX_RECOGNIZED_ITEMS + 1)
            )
        self.assertEqual(context.exception.code, "invalid_model_result")

    def test_rejects_invalid_or_inconsistent_input_kind(self):
        payload = valid_model_payload()
        payload["input_kind"] = "receipt"
        with self.assertRaises(BridgeFailure):
            normalize_model_result(payload)

        payload = valid_model_payload()
        payload["input_kind"] = "non_food"
        with self.assertRaises(BridgeFailure):
            normalize_model_result(payload)


class ResponseContractTests(unittest.TestCase):
    def test_schema_requires_nullable_range_and_caffeine_fields(self):
        schema = json.loads(
            (BRIDGE_DIR / "response-schema.json").read_text(
                encoding="utf-8"
            )
        )
        item_schema = schema["properties"]["items"]["items"]

        for field in (
            "estimated_calories_min",
            "estimated_calories_max",
            "caffeine_mg",
        ):
            self.assertIn(field, item_schema["required"])
            self.assertIn(
                "null",
                item_schema["properties"][field]["type"],
            )

    def test_schema_classifies_receipts_and_allows_long_orders(self):
        schema = json.loads(
            (BRIDGE_DIR / "response-schema.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertIn("input_kind", schema["required"])
        self.assertEqual(
            schema["properties"]["input_kind"]["enum"],
            ["food_photo", "receipt_or_menu", "non_food"],
        )
        self.assertEqual(
            schema["properties"]["items"]["maxItems"],
            MAX_RECOGNIZED_ITEMS,
        )

    def test_prompt_covers_receipts_order_screenshot_and_starbucks_case(self):
        prompt = (BRIDGE_DIR / "recognition-prompt.txt").read_text(
            encoding="utf-8"
        )

        self.assertIn("品牌点单、订单确认或定制页面截图", prompt)
        self.assertIn("receipt_or_menu", prompt)
        self.assertIn("不得因项目超过 8 个而丢掉后半张账单", prompt)
        self.assertIn("价格、折扣、会员、桌号、税、小计、总计和小费", prompt)
        self.assertIn("按账单菜名和数量估算", prompt)
        self.assertIn("看不到实际份量", prompt)
        self.assertIn("不能按一整盘主菜估算", prompt)
        self.assertIn("2 鸡肉串 (2)", prompt)
        self.assertIn("普通肉串约 25–45 克/串", prompt)
        self.assertIn("不得自行除以人数、二等分", prompt)
        self.assertIn("最多返回 24 项", prompt)
        self.assertIn("estimated_calories=400", prompt)
        self.assertIn("estimated_calories_min=370", prompt)
        self.assertIn("estimated_calories_max=430", prompt)
        self.assertIn("caffeine_mg=300", prompt)
        self.assertIn("不得把 160 千卡再次叠加", prompt)
        self.assertIn("{{OUTPUT_LANGUAGE_INSTRUCTION}}", prompt)

    def test_receipt_safety_note_uses_requested_output_language(self):
        payload = receipt_model_payload(item_count=1)
        payload["items"][0]["note"] = "Oil and serving size are uncertain."

        result = normalize_model_result(payload, output_language="en")

        note = result["foods"][0]["note"]
        self.assertIn(
            "Estimated from the receipt item name and quantity",
            note,
        )
        self.assertIn("the actual portion is not visible", note)

    def test_run_recognition_includes_receipt_kind_in_v1_response(self):
        payload = receipt_model_payload()
        config = BridgeConfig(
            expected_login="owner@example.com",
            codex_path=Path("/Applications/ChatGPT.app/codex"),
            model="gpt-5.6-terra",
            port=8765,
            timeout_seconds=90,
        )

        def fake_run(command, **kwargs):
            result_path = Path(
                command[command.index("--output-last-message") + 1]
            )
            result_path.write_text(
                json.dumps(payload),
                encoding="utf-8",
            )
            return SimpleNamespace(returncode=0)

        with patch.object(
            bridge_server.subprocess,
            "run",
            side_effect=fake_run,
        ):
            response = bridge_server.run_recognition(
                config,
                b"\xff\xd8\xff\xe0test",
                "receipt-test",
            )

        self.assertEqual(response["schema_version"], 1)
        self.assertEqual(response["input_kind"], "receipt_or_menu")
        self.assertEqual(response["analysis_id"], "receipt-test")
        self.assertEqual(len(response["foods"]), 12)


class CommandSecurityTests(unittest.TestCase):
    def test_command_is_fixed_and_ephemeral(self):
        config = BridgeConfig(
            expected_login="owner@example.com",
            codex_path=Path("/Applications/ChatGPT.app/codex"),
            model="gpt-5.6-terra",
            port=8765,
            timeout_seconds=90,
        )
        command = build_codex_command(
            config,
            Path("/tmp/meal.jpg"),
            Path("/tmp/result.json"),
            output_language="zh-Hant",
        )

        self.assertIn("--ephemeral", command)
        self.assertIn("--ignore-user-config", command)
        self.assertIn("--ignore-rules", command)
        self.assertIn("read-only", command)
        self.assertIn("gpt-5.6-terra", command)
        self.assertNotIn("owner@example.com", command)
        self.assertLess(
            command.index("--ask-for-approval"),
            command.index("exec"),
        )
        self.assertIn("輸出語言：繁體中文", command[-1])
        self.assertNotIn("{{OUTPUT_LANGUAGE_INSTRUCTION}}", command[-1])
        for feature in (
            "shell_tool",
            "unified_exec",
            "browser_use",
            "computer_use",
            "plugins",
            "multi_agent",
        ):
            self.assertIn(feature, command)

    def test_subprocess_environment_uses_allowlist(self):
        with patch.dict(
            "os.environ",
            {
                "HOME": "/Users/test",
                "USER": "test",
                "OPENAI_API_KEY": "must-not-pass",
                "CODEX_API_KEY": "must-not-pass",
                "UNRELATED_SECRET": "must-not-pass",
            },
            clear=True,
        ):
            environment = sanitized_environment()

        self.assertEqual(environment["HOME"], "/Users/test")
        self.assertEqual(environment["USER"], "test")
        self.assertEqual(
            environment["PATH"], "/usr/bin:/bin:/usr/sbin:/sbin"
        )
        self.assertNotIn("OPENAI_API_KEY", environment)
        self.assertNotIn("CODEX_API_KEY", environment)
        self.assertNotIn("UNRELATED_SECRET", environment)


class HTTPAuthorizationTests(unittest.TestCase):
    def setUp(self):
        config = BridgeConfig(
            expected_login="owner@example.com",
            codex_path=Path("/does/not/exist"),
            model="gpt-5.6-terra",
            port=0,
            timeout_seconds=1,
        )
        self.server = BridgeHTTPServer(("127.0.0.1", 0), config)
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            daemon=True,
        )
        self.thread.start()
        self.base_url = "http://127.0.0.1:{}".format(
            self.server.server_port
        )

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_health_rejects_missing_or_forged_identity(self):
        for login in (None, "attacker@example.com"):
            headers = {}
            if login is not None:
                headers["Tailscale-User-Login"] = login
            request = urllib.request.Request(
                self.base_url + "/health",
                headers=headers,
            )
            with self.subTest(login=login):
                with self.assertRaises(urllib.error.HTTPError) as context:
                    urllib.request.urlopen(request, timeout=2)
                self.assertEqual(context.exception.code, 401)
                context.exception.close()

    def test_health_accepts_expected_tailnet_identity(self):
        request = urllib.request.Request(
            self.base_url + "/health",
            headers={"Tailscale-User-Login": "owner@example.com"},
        )

        with urllib.request.urlopen(request, timeout=2) as response:
            payload = json.load(response)

        self.assertEqual(response.status, 200)
        self.assertEqual(payload["status"], "unavailable")
        self.assertFalse(payload["codex_authenticated"])

    def test_recognition_returns_busy_without_consuming_request(self):
        jpeg = b"\xff\xd8\xff\xe0test"
        body = json.dumps(
            {
                "schema_version": 1,
                "image_base64": base64.b64encode(jpeg).decode("ascii"),
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + "/v1/recognize",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Tailscale-User-Login": "owner@example.com",
            },
            method="POST",
        )

        bridge_server.RECOGNITION_SLOT.acquire()
        try:
            with self.assertRaises(urllib.error.HTTPError) as context:
                urllib.request.urlopen(request, timeout=2)
            self.assertEqual(context.exception.code, 429)
            context.exception.close()
        finally:
            bridge_server.RECOGNITION_SLOT.release()


if __name__ == "__main__":
    unittest.main()
