#!/usr/bin/env python3
"""Tailnet-only bridge from WeightCoach photos to the Mac mini Codex CLI."""

from __future__ import annotations

import base64
import binascii
import json
import math
import os
import subprocess
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional


SERVICE_NAME = "WeightCoach Mac mini Bridge"
SCHEMA_VERSION = 1
MAX_REQUEST_BYTES = 7_000_000
MAX_IMAGE_BYTES = 5_000_000
MAX_RESULT_BYTES = 1_000_000
MAX_RECOGNIZED_ITEMS = 24
ROOT = Path(__file__).resolve().parent
RESPONSE_SCHEMA_PATH = ROOT / "response-schema.json"
PROMPT_PATH = ROOT / "recognition-prompt.txt"
RECOGNITION_SLOT = threading.BoundedSemaphore(value=1)
DISABLED_CODEX_FEATURES = (
    "shell_tool",
    "unified_exec",
    "shell_snapshot",
    "apps",
    "browser_use",
    "browser_use_external",
    "browser_use_full_cdp_access",
    "computer_use",
    "image_generation",
    "in_app_browser",
    "goals",
    "hooks",
    "memories",
    "multi_agent",
    "multi_agent_v2",
    "plugins",
    "remote_plugin",
    "skill_mcp_dependency_install",
    "skill_search",
    "tool_call_mcp_elicitation",
    "tool_suggest",
    "workspace_dependencies",
)
OUTPUT_LANGUAGE_INSTRUCTIONS = {
    "zh-Hans": (
        "输出语言：简体中文。所有 name、portion_description、note 和 "
        "warnings 都必须使用简体中文；仅官方品牌或菜名需要时可在括号中"
        "保留英文。"
    ),
    "zh-Hant": (
        "輸出語言：繁體中文（臺灣常用詞）。所有 name、"
        "portion_description、note 與 warnings 都必須使用繁體中文；"
        "僅官方品牌或菜名需要時可在括號中保留英文。"
    ),
    "en": (
        "Output language: English. Write every name, portion_description, "
        "note, and warning in English. Preserve an official non-English dish "
        "name in parentheses only when it helps identify the item."
    ),
}


class BridgeFailure(Exception):
    def __init__(self, code: str, message: str, status: int) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


@dataclass(frozen=True)
class BridgeConfig:
    expected_login: str
    codex_path: Path
    model: str
    port: int
    timeout_seconds: int

    @classmethod
    def from_environment(cls) -> "BridgeConfig":
        expected_login = os.environ.get(
            "WEIGHTCOACH_TAILSCALE_LOGIN", ""
        ).strip()
        codex_path = Path(
            os.environ.get(
                "WEIGHTCOACH_CODEX_PATH",
                "/Applications/ChatGPT.app/Contents/Resources/codex",
            )
        )
        model = os.environ.get(
            "WEIGHTCOACH_CODEX_MODEL", "gpt-5.6-terra"
        ).strip()
        port = int(os.environ.get("WEIGHTCOACH_BRIDGE_PORT", "8765"))
        timeout_seconds = int(
            os.environ.get("WEIGHTCOACH_CODEX_TIMEOUT", "90")
        )
        return cls(
            expected_login=expected_login,
            codex_path=codex_path,
            model=model,
            port=port,
            timeout_seconds=timeout_seconds,
        )


@dataclass(frozen=True)
class RecognitionRequestData:
    jpeg_data: bytes
    output_language: str


def sanitized_environment() -> Dict[str, str]:
    allowed_keys = (
        "HOME",
        "USER",
        "LOGNAME",
        "TMPDIR",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "CODEX_HOME",
    )
    environment = {
        key: os.environ[key]
        for key in allowed_keys
        if key in os.environ
    }
    environment.setdefault("HOME", str(Path.home()))
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    return environment


def codex_status(config: BridgeConfig) -> Dict[str, Any]:
    if not config.codex_path.is_file():
        return {
            "authenticated": False,
            "version": None,
        }

    environment = sanitized_environment()
    try:
        login = subprocess.run(
            [str(config.codex_path), "login", "status"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
            env=environment,
        )
        version = subprocess.run(
            [str(config.codex_path), "--version"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
            env=environment,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {
            "authenticated": False,
            "version": None,
        }

    login_output = (login.stdout + login.stderr).strip()
    version_output = (version.stdout + version.stderr).strip()
    return {
        "authenticated": (
            login.returncode == 0
            and "Logged in using ChatGPT" in login_output
        ),
        "version": version_output if version.returncode == 0 else None,
    }


def decode_request_body(body: bytes) -> RecognitionRequestData:
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise BridgeFailure(
            "invalid_request",
            "请求格式无效，请重新拍照后重试。",
            400,
        )

    if not isinstance(payload, dict):
        raise BridgeFailure("invalid_request", "请求格式无效。", 400)
    required_fields = {"schema_version", "image_base64"}
    allowed_fields = required_fields | {"output_language"}
    if (
        not required_fields.issubset(payload)
        or not set(payload).issubset(allowed_fields)
    ):
        raise BridgeFailure(
            "invalid_request",
            "请求字段不完整或包含不允许的字段。",
            400,
        )
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise BridgeFailure(
            "unsupported_schema",
            "App 与 Mac mini 的识别协议版本不一致。",
            400,
        )
    image_base64 = payload.get("image_base64")
    if not isinstance(image_base64, str):
        raise BridgeFailure("invalid_image", "照片数据无效。", 400)
    output_language = payload.get("output_language", "zh-Hans")
    if output_language not in OUTPUT_LANGUAGE_INSTRUCTIONS:
        raise BridgeFailure(
            "invalid_request",
            "不支持请求的输出语言。",
            400,
        )

    try:
        image = base64.b64decode(image_base64, validate=True)
    except (ValueError, binascii.Error):
        raise BridgeFailure("invalid_image", "照片数据无效。", 400)
    if not image or len(image) > MAX_IMAGE_BYTES:
        raise BridgeFailure(
            "invalid_image",
            "照片为空或超过 5 MB，请重新拍照。",
            413,
        )
    if not image.startswith(b"\xff\xd8\xff"):
        raise BridgeFailure(
            "invalid_image",
            "只接受 App 处理后的 JPEG 照片。",
            415,
        )
    return RecognitionRequestData(
        jpeg_data=image,
        output_language=output_language,
    )


def build_codex_command(
    config: BridgeConfig,
    image_path: Path,
    result_path: Path,
    output_language: str = "zh-Hans",
) -> List[str]:
    language_instruction = OUTPUT_LANGUAGE_INSTRUCTIONS.get(output_language)
    if language_instruction is None:
        raise BridgeFailure(
            "invalid_request",
            "不支持请求的输出语言。",
            400,
        )
    prompt_template = PROMPT_PATH.read_text(encoding="utf-8").strip()
    prompt = prompt_template.replace(
        "{{OUTPUT_LANGUAGE_INSTRUCTION}}",
        language_instruction,
    )
    command = [
        str(config.codex_path),
        "--strict-config",
        "--ask-for-approval",
        "never",
    ]
    for feature in DISABLED_CODEX_FEATURES:
        command.extend(["--disable", feature])
    command.extend([
        "exec",
        "--ephemeral",
        "--ignore-user-config",
        "--ignore-rules",
        "--sandbox",
        "read-only",
        "--skip-git-repo-check",
        "--model",
        config.model,
        "--image",
        str(image_path),
        "--output-schema",
        str(RESPONSE_SCHEMA_PATH),
        "--output-last-message",
        str(result_path),
        prompt,
    ])
    return command


def _validated_number(
    value: Any,
    field: str,
    minimum: float,
    maximum: float,
    allow_none: bool = False,
) -> Optional[float]:
    if value is None and allow_none:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回了无效的营养数值。",
            502,
        )
    number = float(value)
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回了超出范围的营养数值。",
            502,
        )
    return round(number, 1)


def _validated_text(
    value: Any,
    field: str,
    maximum_length: int,
    allow_none: bool = False,
) -> Optional[str]:
    if value is None and allow_none:
        return None
    if not isinstance(value, str):
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回了无效的文字结果。",
            502,
        )
    text = value.strip()
    if not text or len(text) > maximum_length:
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回了不完整的文字结果。",
            502,
        )
    return text


def _receipt_note(
    note: Optional[str],
    output_language: str,
) -> str:
    """Guarantee that receipt estimates cannot look like observed portions."""
    localized_requirements = {
        "zh-Hans": (
            "按账单菜名和数量估算",
            "看不到实际份量",
            "；",
            "。",
        ),
        "zh-Hant": (
            "按帳單菜名和數量估算",
            "看不到實際份量",
            "；",
            "。",
        ),
        "en": (
            "Estimated from the receipt item name and quantity",
            "the actual portion is not visible",
            "; ",
            ".",
        ),
    }
    first_fact, second_fact, separator, terminator = localized_requirements[
        output_language
    ]
    required_phrases = (first_fact, second_fact)
    comparable_note = (note or "").lower()
    missing_phrases = [
        phrase
        for phrase in required_phrases
        if phrase.lower() not in comparable_note
    ]
    if not missing_phrases:
        return note or separator.join(required_phrases) + terminator

    suffix = separator.join(missing_phrases) + terminator
    if not note:
        return suffix

    maximum_length = 220
    prefix_length = maximum_length - len(separator) - len(suffix)
    prefix = note[: max(0, prefix_length)].rstrip("；。; ")
    if not prefix:
        return suffix
    return prefix + separator + suffix


def normalize_model_result(
    payload: Any,
    output_language: str = "zh-Hans",
) -> Dict[str, Any]:
    if output_language not in OUTPUT_LANGUAGE_INSTRUCTIONS:
        raise BridgeFailure(
            "invalid_request",
            "不支持请求的输出语言。",
            400,
        )
    if not isinstance(payload, dict):
        raise BridgeFailure(
            "invalid_model_result",
            "模型没有返回有效的识别结果。",
            502,
        )
    items = payload.get("items")
    warnings = payload.get("warnings")
    if not isinstance(items, list) or len(items) > MAX_RECOGNIZED_ITEMS:
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回的食物项目数量无效。",
            502,
        )
    if not isinstance(warnings, list) or len(warnings) > 6:
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回的注意事项格式无效。",
            502,
        )

    input_kind = payload.get("input_kind")
    if input_kind is None:
        raise BridgeFailure(
            "invalid_model_result",
            "模型没有返回图片类型；已停止处理以避免把账单误当成餐盘。",
            502,
        )
    if input_kind not in ("food_photo", "receipt_or_menu", "non_food"):
        raise BridgeFailure(
            "invalid_model_result",
            "模型返回了无效的图片类型。",
            502,
        )
    if input_kind == "non_food" and items:
        raise BridgeFailure(
            "invalid_model_result",
            "模型把非食物图片与食物项目混在了一起。",
            502,
        )

    foods: List[Dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            raise BridgeFailure(
                "invalid_model_result",
                "模型返回了无效的食物项目。",
                502,
            )
        confidence = _validated_number(
            item.get("confidence"), "confidence", 0, 1
        )
        calories = _validated_number(
            item.get("estimated_calories"),
            "estimated_calories",
            1,
            5_000,
        )
        calories_min = _validated_number(
            item.get("estimated_calories_min"),
            "estimated_calories_min",
            1,
            5_000,
            allow_none=True,
        )
        calories_max = _validated_number(
            item.get("estimated_calories_max"),
            "estimated_calories_max",
            1,
            5_000,
            allow_none=True,
        )
        if (calories_min is None) != (calories_max is None):
            raise BridgeFailure(
                "invalid_model_result",
                "模型返回的热量范围不完整。",
                502,
            )
        if (
            calories_min is not None
            and calories_max is not None
            and not calories_min <= calories <= calories_max
        ):
            raise BridgeFailure(
                "invalid_model_result",
                "模型返回的热量范围与中心估算不一致。",
                502,
            )
        note = _validated_text(
            item.get("note"),
            "note",
            220,
            allow_none=True,
        )
        if input_kind == "receipt_or_menu":
            note = _receipt_note(note, output_language)
        foods.append(
            {
                "name": _validated_text(
                    item.get("name"), "name", 80
                ),
                "portion": _validated_text(
                    item.get("portion_description"),
                    "portion_description",
                    120,
                ),
                "calories": calories,
                "calories_min": calories_min,
                "calories_max": calories_max,
                "protein": _validated_number(
                    item.get("protein_g"),
                    "protein_g",
                    0,
                    1_000,
                    allow_none=True,
                ),
                "carbs": _validated_number(
                    item.get("carbs_g"),
                    "carbs_g",
                    0,
                    1_000,
                    allow_none=True,
                ),
                "fat": _validated_number(
                    item.get("fat_g"),
                    "fat_g",
                    0,
                    1_000,
                    allow_none=True,
                ),
                "caffeine_mg": _validated_number(
                    item.get("caffeine_mg"),
                    "caffeine_mg",
                    0,
                    2_000,
                    allow_none=True,
                ),
                "confidence": confidence,
                # A single photo cannot verify weight or hidden cooking oil.
                # Receipt rows additionally cannot verify the actual serving.
                "needs_confirmation": True,
                "note": note,
            }
        )

    validated_warnings = [
        _validated_text(warning, "warning", 220)
        for warning in warnings
    ]
    return {
        "input_kind": input_kind,
        "foods": foods,
        "warnings": validated_warnings,
    }


def run_recognition(
    config: BridgeConfig,
    jpeg_data: bytes,
    request_id: str,
    output_language: str = "zh-Hans",
) -> Dict[str, Any]:
    started = time.monotonic()
    with tempfile.TemporaryDirectory(
        prefix="weightcoach-recognition-"
    ) as temporary_directory:
        temp_path = Path(temporary_directory)
        image_path = temp_path / "meal.jpg"
        result_path = temp_path / "result.json"
        stdout_path = temp_path / "codex-stdout.log"
        stderr_path = temp_path / "codex-stderr.log"
        image_path.write_bytes(jpeg_data)
        image_path.chmod(0o600)

        command = build_codex_command(
            config,
            image_path,
            result_path,
            output_language,
        )
        try:
            with stdout_path.open("wb") as stdout_file, stderr_path.open(
                "wb"
            ) as stderr_file:
                process = subprocess.run(
                    command,
                    cwd=str(temp_path),
                    stdin=subprocess.DEVNULL,
                    stdout=stdout_file,
                    stderr=stderr_file,
                    timeout=config.timeout_seconds,
                    env=sanitized_environment(),
                )
        except subprocess.TimeoutExpired:
            raise BridgeFailure(
                "recognition_timeout",
                "这次识别等待超时，请重试。",
                504,
            )
        except OSError:
            raise BridgeFailure(
                "bridge_unavailable",
                "Mac mini 上的识别程序无法启动。",
                503,
            )

        if process.returncode != 0:
            diagnostic = (
                read_file_tail(stdout_path) + read_file_tail(stderr_path)
            ).lower()
            subscription_markers = (
                "logged out",
                "login",
                "authentication",
                "rate limit",
                "usage limit",
                "quota",
            )
            if any(marker in diagnostic for marker in subscription_markers):
                raise BridgeFailure(
                    "subscription_unavailable",
                    "Mac mini 上的 ChatGPT 登录或订阅额度暂时不可用。",
                    503,
                )
            raise BridgeFailure(
                "recognition_failed",
                "这次没有得到可靠结果，请重拍或手动填写。",
                502,
            )

        try:
            if result_path.stat().st_size > MAX_RESULT_BYTES:
                raise ValueError("result too large")
            model_payload = json.loads(
                result_path.read_text(encoding="utf-8")
            )
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
            raise BridgeFailure(
                "invalid_model_result",
                "模型没有返回有效的结构化结果，请重试。",
                502,
            )

    normalized = normalize_model_result(model_payload, output_language)
    elapsed_ms = int((time.monotonic() - started) * 1_000)
    return {
        "schema_version": SCHEMA_VERSION,
        "analysis_id": request_id,
        "model": config.model,
        "elapsed_ms": elapsed_ms,
        "input_kind": normalized["input_kind"],
        "foods": normalized["foods"],
        "warnings": normalized["warnings"],
    }


def read_file_tail(path: Path, maximum_bytes: int = 65_536) -> str:
    try:
        with path.open("rb") as file:
            file.seek(0, os.SEEK_END)
            size = file.tell()
            file.seek(max(0, size - maximum_bytes), os.SEEK_SET)
            return file.read(maximum_bytes).decode(
                "utf-8", errors="replace"
            )
    except OSError:
        return ""


class BridgeHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: Any, config: BridgeConfig) -> None:
        super().__init__(address, BridgeRequestHandler)
        self.config = config


class BridgeRequestHandler(BaseHTTPRequestHandler):
    server: BridgeHTTPServer
    protocol_version = "HTTP/1.1"
    server_version = "WeightCoachBridge/1"

    def do_GET(self) -> None:
        try:
            self._authorize()
            if self.path != "/health":
                raise BridgeFailure("not_found", "接口不存在。", 404)
            status = codex_status(self.server.config)
            self._send_json(
                200,
                {
                    "status": (
                        "ready" if status["authenticated"] else "unavailable"
                    ),
                    "schema_version": SCHEMA_VERSION,
                    "service": SERVICE_NAME,
                    "codex_authenticated": status["authenticated"],
                    "codex_version": status["version"],
                    "model": self.server.config.model,
                },
            )
        except BridgeFailure as error:
            self._send_failure(error)

    def do_POST(self) -> None:
        request_id = uuid.uuid4().hex
        try:
            self._authorize()
            if self.path != "/v1/recognize":
                raise BridgeFailure("not_found", "接口不存在。", 404)
            content_type = self.headers.get("Content-Type", "")
            if not content_type.lower().startswith("application/json"):
                raise BridgeFailure(
                    "invalid_request",
                    "请求必须使用 JSON 格式。",
                    415,
                )
            content_length = self.headers.get("Content-Length")
            try:
                length = int(content_length or "")
            except ValueError:
                raise BridgeFailure(
                    "invalid_request", "请求长度无效。", 411
                )
            if not 0 < length <= MAX_REQUEST_BYTES:
                raise BridgeFailure(
                    "request_too_large",
                    "请求为空或超过大小限制。",
                    413,
                )
            body = self.rfile.read(length)
            recognition_request = decode_request_body(body)

            if not RECOGNITION_SLOT.acquire(blocking=False):
                raise BridgeFailure(
                    "busy",
                    "Mac mini 正在识别上一张照片，请稍后重试。",
                    429,
                )
            try:
                result = run_recognition(
                    self.server.config,
                    recognition_request.jpeg_data,
                    request_id,
                    recognition_request.output_language,
                )
            finally:
                RECOGNITION_SLOT.release()
            self._send_json(200, result)
            print(
                "{} request={} status=ok elapsed_ms={}".format(
                    SERVICE_NAME, request_id, result["elapsed_ms"]
                ),
                flush=True,
            )
        except BridgeFailure as error:
            self._send_failure(error)
            print(
                "{} request={} status={} code={}".format(
                    SERVICE_NAME, request_id, error.status, error.code
                ),
                flush=True,
            )
        except Exception:
            failure = BridgeFailure(
                "internal_error",
                "Mac mini 识别服务发生内部错误，请稍后重试。",
                500,
            )
            self._send_failure(failure)
            print(
                "{} request={} status=500 code=internal_error".format(
                    SERVICE_NAME, request_id
                ),
                flush=True,
            )

    def _authorize(self) -> None:
        login = self.headers.get("Tailscale-User-Login", "").strip()
        if not login or (
            login.casefold()
            != self.server.config.expected_login.casefold()
        ):
            raise BridgeFailure(
                "unauthorized",
                "当前 Tailscale 账户无权使用此识别服务。",
                401,
            )

    def _send_failure(self, failure: BridgeFailure) -> None:
        self._send_json(
            failure.status,
            {
                "error": {
                    "code": failure.code,
                    "message": failure.message,
                }
            },
        )

    def _send_json(self, status: int, payload: Dict[str, Any]) -> None:
        body = json.dumps(
            payload, ensure_ascii=False, separators=(",", ":")
        ).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string: str, *args: Any) -> None:
        return


def main() -> None:
    os.umask(0o077)
    config = BridgeConfig.from_environment()
    if not config.expected_login:
        raise SystemExit(
            "WEIGHTCOACH_TAILSCALE_LOGIN is required; refusing to start."
        )
    if not config.codex_path.is_file():
        raise SystemExit(
            "Codex CLI not found at {}".format(config.codex_path)
        )
    if not RESPONSE_SCHEMA_PATH.is_file() or not PROMPT_PATH.is_file():
        raise SystemExit("Bridge schema or prompt file is missing.")

    server = BridgeHTTPServer(("127.0.0.1", config.port), config)
    print(
        "{} listening on 127.0.0.1:{} model={}".format(
            SERVICE_NAME, config.port, config.model
        ),
        flush=True,
    )
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
