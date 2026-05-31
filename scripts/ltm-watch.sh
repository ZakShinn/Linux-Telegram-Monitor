#!/usr/bin/env bash
# ltm-watch.sh — Canh bao Telegram theo nguong (khong gui full report)
#
#   sudo ltm-watch              # mot lan
#   sudo ltm-watch --loop       # daemon (systemd)
# Cau hinh: /etc/ltm-watch.conf (hoac token tu server-telegram-report.conf)

set -euo pipefail

readonly CONF_SYSTEM="/etc/ltm-watch.conf"
readonly CONF_REPORT="/etc/server-telegram-report.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/ltm-watch.conf"
STATE_DIR="${STATE_DIR:-/var/lib/ltm-watch}"
SILENCE_FILE="${SILENCE_FILE:-${STATE_DIR}/silence_until}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/state.env}"

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  [[ -f "$CONF_REPORT" ]] && source "$CONF_REPORT"
fi

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"

: "${TELEGRAM_BOT_TOKEN:?Thieu TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID:?Thieu TELEGRAM_CHAT_ID}"

WATCH_INTERVAL="${WATCH_INTERVAL:-300}"
WATCH_DISK_PERCENT="${WATCH_DISK_PERCENT:-90}"
WATCH_LOAD_PER_CPU="${WATCH_LOAD_PER_CPU:-2}"
WATCH_MEM_PERCENT="${WATCH_MEM_PERCENT:-95}"
WATCH_DOCKER_UNHEALTHY="${WATCH_DOCKER_UNHEALTHY:-1}"
WATCH_TLS_DAYS="${WATCH_TLS_DAYS:-14}"
WATCH_HTTP_URLS="${WATCH_HTTP_URLS:-}"
WATCH_LANG="${WATCH_LANG:-vi}"

LOOP=0
[[ "${1:-}" == "--loop" ]] && LOOP=1

mkdir -p "$STATE_DIR" 2>/dev/null || STATE_DIR="${TMPDIR:-/tmp}/ltm-watch"

tg_send() {
  local text=$1 cid raw
  raw="${TELEGRAM_CHAT_ID// /,}"
  IFS=',' read -ra _cids <<< "$raw"
  for cid in "${_cids[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -z "$cid" ]] && continue
    curl -fsS --max-time 25 -X POST \
      "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      --data-urlencode "chat_id=${cid}" \
      --data-urlencode "parse_mode=HTML" \
      --data-urlencode "text=${text}" \
      --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
  done
}

watch_silenced() {
  [[ -f "$SILENCE_FILE" ]] || return 1
  local until now
  until=$(cat "$SILENCE_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  [[ "${until:-0}" -gt "$now" ]]
}

state_get() {
  local k=$1
  [[ -f "$STATE_FILE" ]] && grep -E "^${k}=" "$STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

state_set() {
  local k=$1 v=$2
  touch "$STATE_FILE" 2>/dev/null || return 0
  if grep -qE "^${k}=" "$STATE_FILE" 2>/dev/null; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$STATE_FILE" 2>/dev/null || true
  else
    echo "${k}=${v}" >>"$STATE_FILE"
  fi
}

alert_once() {
  local key=$1 msg=$2
  local prev
  prev=$(state_get "$key")
  [[ "$prev" == "1" ]] && return 0
  state_set "$key" "1"
  tg_send "$msg"
}

alert_clear() {
  local key=$1
  local prev
  prev=$(state_get "$key")
  [[ "$prev" == "1" ]] && state_set "$key" "0"
}

check_disk() {
  local th="${WATCH_DISK_PERCENT}"
  local bad=""
  bad=$(df -P -x tmpfs -x devtmpfs 2>/dev/null | awk -v th="$th" '
    NR>1 && $1 ~ /^\/dev/ {
      gsub(/%/,"",$5); if (($5+0) >= (th+0)) print $NF" "$5"%"
    }')
  if [[ -n "${bad//[:space:]/}" ]]; then
    if [[ "$WATCH_LANG" == "en" ]]; then
      alert_once disk_high "⚠️ <b>ltm-watch</b> — disk ≥${th}% on <code>$(hostname -s)</code><pre>$(printf '%s' "$bad")</pre>"
    else
      alert_once disk_high "⚠️ <b>ltm-watch</b> — ổ ≥${th}% trên <code>$(hostname -s)</code><pre>$(printf '%s' "$bad")</pre>"
    fi
  else
    alert_clear disk_high
  fi
}

check_load() {
  local lpc="${WATCH_LOAD_PER_CPU}" cpus load1
  cpus=$(nproc 2>/dev/null || echo 1)
  load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)
  awk -v l="$load1" -v c="$cpus" -v m="$lpc" 'BEGIN{exit !(l > c*m)}' || {
    alert_clear load_high
    return 0
  }
  if [[ "$WATCH_LANG" == "en" ]]; then
    alert_once load_high "⚠️ <b>ltm-watch</b> — high load <code>${load1}</code> (cpus=${cpus}, threshold=${lpc}/cpu) on <code>$(hostname -s)</code>"
  else
    alert_once load_high "⚠️ <b>ltm-watch</b> — load cao <code>${load1}</code> (cpus=${cpus}, ngưỡng=${lpc}/cpu) trên <code>$(hostname -s)</code>"
  fi
}

check_mem() {
  local th="${WATCH_MEM_PERCENT}" used pct
  read -r used pct < <(free 2>/dev/null | awk '/^Mem:/{printf "%d %d", $3, ($3/$2)*100}')
  [[ "${pct:-0}" -ge "$th" ]] || { alert_clear mem_high; return 0; }
  if [[ "$WATCH_LANG" == "en" ]]; then
    alert_once mem_high "⚠️ <b>ltm-watch</b> — RAM ~${pct}% used on <code>$(hostname -s)</code>"
  else
    alert_once mem_high "⚠️ <b>ltm-watch</b> — RAM ~${pct}% đã dùng trên <code>$(hostname -s)</code>"
  fi
}

check_docker_unhealthy() {
  [[ "$WATCH_DOCKER_UNHEALTHY" == "1" ]] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  local u
  u=$(docker ps -a --filter health=unhealthy --format '{{.Names}}' 2>/dev/null | head -n 10 || true)
  if [[ -n "${u//[:space:]/}" ]]; then
    if [[ "$WATCH_LANG" == "en" ]]; then
      alert_once docker_bad "⚠️ <b>ltm-watch</b> — unhealthy containers on <code>$(hostname -s)</code><pre>${u}</pre>"
    else
      alert_once docker_bad "⚠️ <b>ltm-watch</b> — container unhealthy trên <code>$(hostname -s)</code><pre>${u}</pre>"
    fi
  else
    alert_clear docker_bad
  fi
}

check_tls() {
  local wdays="${WATCH_TLS_DAYS}" ledir="/etc/letsencrypt/live"
  command -v openssl >/dev/null 2>&1 || return 0
  [[ -d "$ledir" ]] || return 0
  local warn="" cert name line end now days
  now=$(date +%s)
  shopt -s nullglob
  for cert in "$ledir"/*/cert.pem; do
    [[ -f "$cert" ]] || continue
    name=$(basename "$(dirname "$cert")")
    line=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2-)
    end=$(date -d "$line" +%s 2>/dev/null || echo 0)
    days=$(( (end - now) / 86400 ))
    [[ "$days" -lt "$wdays" ]] && warn+="${name}: ${days}d left"$'\n'
  done
  shopt -u nullglob
  if [[ -n "${warn//[:space:]/}" ]]; then
    if [[ "$WATCH_LANG" == "en" ]]; then
      alert_once tls_warn "⚠️ <b>ltm-watch</b> — TLS expiring (&lt;${wdays}d) <code>$(hostname -s)</code><pre>${warn}</pre>"
    else
      alert_once tls_warn "⚠️ <b>ltm-watch</b> — TLS sắp hết (&lt;${wdays} ngày) <code>$(hostname -s)</code><pre>${warn}</pre>"
    fi
  else
    alert_clear tls_warn
  fi
}

check_http() {
  [[ -n "${WATCH_HTTP_URLS// }" ]] || return 0
  local url fails=""
  IFS=',' read -ra urls <<< "${WATCH_HTTP_URLS// /,}"
  for url in "${urls[@]}"; do
    url="${url//[[:space:]]/}"
    [[ -z "$url" ]] && continue
    curl -fsS --max-time 8 -o /dev/null "$url" 2>/dev/null || fails+="${url}"$'\n'
  done
  if [[ -n "${fails//[:space:]/}" ]]; then
    if [[ "$WATCH_LANG" == "en" ]]; then
      alert_once http_down "⚠️ <b>ltm-watch</b> — HTTP check failed <code>$(hostname -s)</code><pre>${fails}</pre>"
    else
      alert_once http_down "⚠️ <b>ltm-watch</b> — HTTP lỗi <code>$(hostname -s)</code><pre>${fails}</pre>"
    fi
  else
    alert_clear http_down
  fi
}

watch_cycle() {
  watch_silenced && return 0
  check_disk
  check_load
  check_mem
  check_docker_unhealthy
  check_tls
  check_http
}

watch_cycle

if [[ "$LOOP" == "1" ]]; then
  while true; do
    sleep "$WATCH_INTERVAL"
    watch_cycle
  done
fi

exit 0
