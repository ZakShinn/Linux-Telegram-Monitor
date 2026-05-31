#!/usr/bin/env bash
# Cap nhat menu lenh Telegram (setMyCommands) khong can chay poll bot
#
#   LTM_BOT_LANG=vi sudo -E bash ltm-bot-sync-commands.sh
#   LTM_BOT_LANG=en sudo -E bash ltm-bot-sync-commands.sh
#
# Tuong duong:
#   curl "https://api.telegram.org/bot<TOKEN>/setMyCommands" \
#     -H "Content-Type: application/json" \
#     -d '{"language_code":"vi","commands":[{"command":"start","description":"Khởi động bot"},...]}'

set -euo pipefail

readonly CONF_BOT="/etc/ltm-telegram-bot.conf"
readonly CONF_REPORT="/etc/server-telegram-report.conf"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LTM_SHARE_DIR="${LTM_SHARE_DIR:-/usr/local/share/linux-telegram-monitor}"
[[ -f "${SCRIPT_DIR}/ltm-bot-core.sh" ]] && LTM_SHARE_DIR="$SCRIPT_DIR"

# shellcheck source=/dev/null
[[ -f "$CONF_BOT" ]] && source "$CONF_BOT"
[[ -z "${TELEGRAM_BOT_TOKEN:-}" ]] && [[ -f "$CONF_REPORT" ]] && source "$CONF_REPORT"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
: "${TELEGRAM_BOT_TOKEN:?Thieu TELEGRAM_BOT_TOKEN}"

export LTM_BOT_LANG="${LTM_BOT_LANG:-vi}"
API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

# shellcheck source=ltm-bot-core.sh
source "${LTM_SHARE_DIR}/ltm-bot-core.sh"
sync_bot_commands
echo "Done. Kiem tra menu lenh trong chat voi bot (go / de xem goi y)."
