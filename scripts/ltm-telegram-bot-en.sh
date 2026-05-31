#!/usr/bin/env bash
# ltm-telegram-bot-en.sh — Telegram bot (English on Telegram)

set -euo pipefail

readonly CONF_BOT="/etc/ltm-telegram-bot.conf"
readonly CONF_REPORT="/etc/server-telegram-report.conf"
readonly CONF_USER_BOT="${XDG_CONFIG_HOME:-$HOME/.config}/ltm-telegram-bot.conf"
readonly CONF_USER_REP="${XDG_CONFIG_HOME:-$HOME/.config}/server-telegram-report.conf"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LTM_SHARE_DIR="${LTM_SHARE_DIR:-/usr/local/share/linux-telegram-monitor}"
[[ -f "${SCRIPT_DIR}/ltm-bot-core.sh" ]] && LTM_SHARE_DIR="$SCRIPT_DIR"

# shellcheck source=/dev/null
[[ -f "$CONF_BOT" ]] && source "$CONF_BOT"
# shellcheck source=/dev/null
[[ -f "$CONF_USER_BOT" ]] && source "$CONF_USER_BOT"
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  [[ -f "$CONF_REPORT" ]] && source "$CONF_REPORT"
  [[ -f "$CONF_USER_REP" ]] && source "$CONF_USER_REP"
fi

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"

: "${TELEGRAM_BOT_TOKEN:?Missing TELEGRAM_BOT_TOKEN — create $CONF_BOT}"
: "${TELEGRAM_CHAT_ID:?Missing TELEGRAM_CHAT_ID}"

PATH_REPORT="${PATH_REPORT:-/usr/local/bin/server-telegram-report}"
PATH_UPDATE="${PATH_UPDATE:-/usr/local/bin/server-telegram-update}"
ALLOW_REMOTE_REPORT="${ALLOW_REMOTE_REPORT:-1}"
ALLOW_REMOTE_UPDATE="${ALLOW_REMOTE_UPDATE:-0}"
ALLOW_REMOTE_ACTION="${ALLOW_REMOTE_ACTION:-0}"
POLL_TIMEOUT="${POLL_TIMEOUT:-25}"
REMOTE_CMD_TIMEOUT="${REMOTE_CMD_TIMEOUT:-35}"
[[ "$POLL_TIMEOUT" -gt 50 ]] && POLL_TIMEOUT=50
[[ "$REMOTE_CMD_TIMEOUT" -gt 120 ]] && REMOTE_CMD_TIMEOUT=120

export LTM_BOT_LANG=en
# shellcheck source=ltm-bot-core.sh
source "${LTM_SHARE_DIR}/ltm-bot-core.sh"
ltm_bot_main
