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

/usr/bin/python3 -m unittest discover -s "$SOURCE_DIR/tests" -p "test_*.py"

/usr/bin/install -d -m 700 "$APP_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
/usr/bin/install -m 600 \
    "$SOURCE_DIR/server.py" \
    "$SOURCE_DIR/response-schema.json" \
    "$SOURCE_DIR/recognition-prompt.txt" \
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
            "http://127.0.0.1:8765/health"
    )"; then
        break
    fi
    /bin/sleep 0.5
done
if [[ -z "$LOCAL_HEALTH" ]]; then
    print -u2 "本机桥接没有正常启动，请检查 $LOG_DIR/bridge-error.log"
    exit 1
fi

"$TAILSCALE" serve --yes --bg 8765
PUBLIC_HEALTH="$(
    /usr/bin/curl --silent --show-error --fail \
        --max-time 20 \
        "https://$DNS_NAME/health"
)"

print "WeightCoach 识别桥已安装并启动："
print "  https://$DNS_NAME"
print "  Tailscale 账户：$TAILSCALE_LOGIN"
print "  本机健康检查：$LOCAL_HEALTH"
print "  私有 HTTPS 检查：$PUBLIC_HEALTH"
