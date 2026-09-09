#!/bin/zsh
set -euo pipefail

SOURCE_DIR="${0:A:h}"
APP_DIR="$HOME/Library/Application Support/WeightCoachBridge"
LOG_DIR="$HOME/Library/Logs/WeightCoachBridge"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS_DIR/com.lukegogogo.weightcoach.bridge.plist"
LABEL="com.lukegogogo.weightcoach.bridge"
CODEX="/Applications/ChatGPT.app/Contents/Resources/codex"
TAILSCALE="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
LOCAL_PORT=8765
TAILSCALE_HTTPS_PORT="${WEIGHTCOACH_TAILSCALE_HTTPS_PORT:-8443}"

if [[ "$TAILSCALE_HTTPS_PORT" != <-> ]] ||
    (( TAILSCALE_HTTPS_PORT < 1 || TAILSCALE_HTTPS_PORT > 65535 )); then
    print -u2 "WEIGHTCOACH_TAILSCALE_HTTPS_PORT 必须是 1 到 65535 的端口号。"
    exit 1
fi

if [[ ! -x "$CODEX" ]]; then
    print -u2 "未找到 ChatGPT 内置 Codex：$CODEX"
    exit 1
fi
if [[ ! -x "$TAILSCALE" ]]; then
    print -u2 "未找到 Tailscale：$TAILSCALE"
    exit 1
fi
if ! "$CODEX" login status 2>&1 | /usr/bin/grep -q "Logged in using ChatGPT"; then
    print -u2 "请先在 Mac mini 的 ChatGPT 中登录订阅账户。"
    exit 1
fi

TAILSCALE_STATUS="$("$TAILSCALE" status --json)"
TAILSCALE_LOGIN="$(
    print -rn -- "$TAILSCALE_STATUS" |
        /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); uid=str(d.get("Self",{}).get("UserID","")); print(d.get("User",{}).get(uid,{}).get("LoginName",""))'
)"
DNS_NAME="$(
    print -rn -- "$TAILSCALE_STATUS" |
        /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("Self",{}).get("DNSName","").rstrip("."))'
)"
if [[ -z "$TAILSCALE_LOGIN" || -z "$DNS_NAME" ]]; then
    print -u2 "Tailscale 尚未连接，无法建立私有 HTTPS 入口。"
    exit 1
fi
BRIDGE_BASE_URL="https://$DNS_NAME:$TAILSCALE_HTTPS_PORT"
EXPECTED_SERVE_TARGET="http://127.0.0.1:$LOCAL_PORT"

check_serve_port_safely() {
    "$TAILSCALE" serve status --json |
        /usr/bin/python3 "$SOURCE_DIR/check_serve_port.py" \
            "$DNS_NAME:$TAILSCALE_HTTPS_PORT" \
            "$EXPECTED_SERVE_TARGET"
}

# Check the entire target-port configuration before tests, file writes, or
# LaunchAgent changes. Only a free port or this exact existing route is safe.
if ! check_serve_port_safely; then
    print -u2 "Tailscale HTTPS $TAILSCALE_HTTPS_PORT 未通过安全检查；未修改文件、服务或现有路由。"
    exit 1
fi

/usr/bin/python3 -m unittest discover -s "$SOURCE_DIR/tests" -p "test_*.py"

/usr/bin/install -d -m 700 "$APP_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
/usr/bin/install -m 600 \
    "$SOURCE_DIR/server.py" \
    "$SOURCE_DIR/response-schema.json" \
    "$SOURCE_DIR/recognition-prompt.txt" \
    "$SOURCE_DIR/text-recognition-prompt.txt" \
    "$APP_DIR/"

ESCAPED_APP_DIR="${APP_DIR//\//\\/}"
ESCAPED_LOG_DIR="${LOG_DIR//\//\\/}"
ESCAPED_LOGIN="${TAILSCALE_LOGIN//\//\\/}"
/usr/bin/sed \
    -e "s/__APP_DIR__/$ESCAPED_APP_DIR/g" \
    -e "s/__LOG_DIR__/$ESCAPED_LOG_DIR/g" \
    -e "s/__TAILSCALE_LOGIN__/$ESCAPED_LOGIN/g" \
    "$SOURCE_DIR/com.lukegogogo.weightcoach.bridge.plist.template" > "$PLIST"
/bin/chmod 600 "$PLIST"
/usr/bin/plutil -lint "$PLIST"

/bin/launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$UID" "$PLIST"
/bin/launchctl kickstart -k "gui/$UID/$LABEL"

LOCAL_HEALTH=""
for _ in {1..20}; do
    if LOCAL_HEALTH="$(
        /usr/bin/curl --silent --show-error --fail \
            --header "Tailscale-User-Login: $TAILSCALE_LOGIN" \
            "http://127.0.0.1:$LOCAL_PORT/health"
    )"; then
        break
    fi
    /bin/sleep 0.5
done
if [[ -z "$LOCAL_HEALTH" ]]; then
    print -u2 "本机桥接没有正常启动，请检查 $LOG_DIR/bridge-error.log"
    exit 1
fi

# Close the install-time race window immediately before changing Serve state.
if ! check_serve_port_safely; then
    print -u2 "安装期间 Tailscale HTTPS $TAILSCALE_HTTPS_PORT 配置发生变化；现有路由未修改。"
    exit 1
fi

"$TAILSCALE" serve --yes --bg \
    --https="$TAILSCALE_HTTPS_PORT" \
    "$EXPECTED_SERVE_TARGET"
PUBLIC_HEALTH="$(
    /usr/bin/curl --silent --show-error --fail \
        --max-time 20 \
        "$BRIDGE_BASE_URL/health"
)"

print "WeightCoach 识别桥已安装并启动："
print "  $BRIDGE_BASE_URL"
print "  Tailscale 账户：$TAILSCALE_LOGIN"
print "  本机健康检查：$LOCAL_HEALTH"
print "  私有 HTTPS 检查：$PUBLIC_HEALTH"
