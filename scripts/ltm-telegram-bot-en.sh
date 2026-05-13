#!/usr/bin/env bash
# ltm-telegram-bot-en.sh — Telegram command bot (getUpdates) for report/update actions
# Requires: bash, curl, jq

set -euo pipefail

readonly CONF_BOT="/etc/ltm-telegram-bot.conf"
readonly CONF_REPORT="/etc/server-telegram-report.conf"
readonly CONF_USER_BOT="${XDG_CONFIG_HOME:-$HOME/.config}/ltm-telegram-bot.conf"
readonly CONF_USER_REP="${XDG_CONFIG_HOME:-$HOME/.config}/server-telegram-report.conf"

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
POLL_TIMEOUT="${POLL_TIMEOUT:-25}"
REMOTE_CMD_TIMEOUT="${REMOTE_CMD_TIMEOUT:-35}"
[[ "$POLL_TIMEOUT" -gt 50 ]] && POLL_TIMEOUT=50
[[ "$REMOTE_CMD_TIMEOUT" -gt 120 ]] && REMOTE_CMD_TIMEOUT=120

if ! command -v jq >/dev/null 2>&1; then
  echo "ltm-bot requires jq: sudo apt install jq (or dnf install jq)" >&2
  exit 1
fi

API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
OFFSET=0
declare -a PENDING_LABELS=()
declare -a PENDING_EXES=()

net_ok() {
  curl -fsS --max-time 6 "${API}/getMe" >/dev/null 2>&1
}

send_msg() {
  local text=$1
  curl -fsS --max-time 30 -X POST "${API}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

sanitize_pre() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

send_pre_trunc() {
  local title=$1 raw=$2
  local limit="${3:-3800}"
  local esc
  esc=$(printf '%s' "$raw" | sanitize_pre)
  if [[ ${#esc} -gt "$limit" ]]; then
    esc="${esc:0:$limit}"$'\n...(trimmed)...'
  fi
  curl -fsS --max-time 45 -X POST "${API}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=<b>${title}</b><pre>${esc}</pre>" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

sync_bot_commands() {
  # Remove existing commands first, then publish the latest list.
  curl -fsS --max-time 20 -X POST "${API}/deleteMyCommands" >/dev/null 2>&1 || true
  curl -fsS --max-time 25 -X POST "${API}/setMyCommands" \
    --data-urlencode 'commands=[
      {"command":"help","description":"Show command list"},
      {"command":"ping","description":"Bot health check"},
      {"command":"report","description":"Run full report"},
      {"command":"update","description":"Run system update"},
      {"command":"quick","description":"Quick server snapshot"},
      {"command":"docker","description":"List containers"},
      {"command":"df","description":"Filesystem usage"},
      {"command":"mem","description":"Memory summary"}
    ]' >/dev/null 2>&1 || true
}

_help_report_gate_msg() {
  send_msg "⛔ This command requires <code>ALLOW_REMOTE_REPORT=1</code> in <code>${CONF_BOT}</code>."
}

run_remote_snapshot() {
  local title=$1 script=$2
  if [[ "$ALLOW_REMOTE_REPORT" != "1" ]]; then
    _help_report_gate_msg
    return 0
  fi
  local out wt="$REMOTE_CMD_TIMEOUT"
  send_msg "⏳ Collecting <b>${title}</b>..."
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$wt" bash -lc "$script" 2>&1) || true
  else
    out=$(bash -lc "$script" 2>&1) || true
  fi
  [[ -z "${out//[:space:]/}" ]] && out="(no output)"
  send_pre_trunc "$title" "$out"
}

help_text() {
  send_msg "<b>Linux Telegram Monitor — commands</b>

<b>Public</b>
<b>/help</b> <b>/start</b> — command list
<b>/ping</b> — pong + hostname

<b>Full report</b> (requires <code>ALLOW_REMOTE_REPORT=1</code>)
<b>/report</b> <b>/status</b> — run <code>server-telegram-report</code> (same style as cron)

<b>Quick / Docker</b> (same permission as /report)
<b>/quick</b> — hostname, uptime, load, RAM, root disk
<b>/docker</b> — <code>docker ps -a</code>
<b>/dockerstats</b> — <code>docker stats --no-stream</code>
<b>/dockerdf</b> — <code>docker system df</code>
<b>/dockerhealth</b> — unhealthy containers
<b>/compose</b> — <code>docker compose ls -a</code>
<b>/dockernet</b> — <code>docker network ls</code>
<b>/dockervol</b> — <code>docker volume ls</code>
<b>/dockerimg</b> — <code>docker images</code> (trimmed)

<b>System</b>
<b>/df</b> — <code>df -hT</code> · <b>/inode</b> — inode usage
<b>/mem</b> — <code>free -h</code> + meminfo summary · <b>/load</b> — load average
<b>/disk</b> — <code>lsblk</code> · <b>/topcpu</b> · <b>/topmem</b>
<b>/ports</b> — listening ports · <b>/ip</b> — interfaces
<b>/failed</b> — failed systemd units · <b>/boot</b> — boot + uptime

<b>Dangerous</b>: <b>/update</b> requires <code>ALLOW_REMOTE_UPDATE=1</code>.

Only configured <b>Chat ID</b> can control this bot."

  sleep 1
  send_msg "<b>Tip</b>: use BotFather <code>setMyCommands</code>. Command timeout: <code>REMOTE_CMD_TIMEOUT</code>s."
}

run_script() {
  local label=$1
  local exe=$2
  if [[ ! -x "$exe" ]]; then
    send_msg "❌ Script not found: <code>${exe}</code>"
    return 0
  fi
  send_msg "⏳ Started <code>${label}</code>. Results will be sent by the script itself."
  if [[ -n "${SUDO_CMD:-}" ]]; then
    # shellcheck disable=SC2086
    $SUDO_CMD "$exe" &
  else
    "$exe" &
  fi
}

queue_remote_job() {
  local label=$1 exe=$2
  PENDING_LABELS+=("$label")
  PENDING_EXES+=("$exe")
}

process_pending_jobs() {
  local n i
  n=${#PENDING_EXES[@]}
  [[ "$n" -gt 0 ]] || return 0
  net_ok || return 0

  send_msg "🌐 Network is back. Re-running <b>${n}</b> queued command(s)..."
  local labels=("${PENDING_LABELS[@]}")
  local exes=("${PENDING_EXES[@]}")
  PENDING_LABELS=()
  PENDING_EXES=()
  for ((i = 0; i < ${#exes[@]}; i++)); do
    run_script "${labels[$i]}" "${exes[$i]}"
  done
}

normalize_cmd() {
  local t=$1
  t=${t%%@*}
  printf '%s' "$t" | tr '[:upper:]' '[:lower:]'
}

dispatch() {
  local raw=$1
  [[ -z "${raw//[:space:]/}" ]] && return 0
  local first cmd
  first=$(printf '%s' "$raw" | awk '{print $1}')
  cmd=$(normalize_cmd "$first")

  case "$cmd" in
  /help|/start) help_text ;;
  /ping) send_msg "pong — <code>$(hostname -s 2>/dev/null || echo '?')</code>" ;;
  /quick)
    run_remote_snapshot "⚡ Quick snapshot" "$(cat <<'EOS'
HN=$(hostname 2>/dev/null || echo "?")
DT=$(date 2>/dev/null || echo "?")
UP=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")
LD=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "N/A")
FR=$(free -h 2>/dev/null || echo "(no free)")
DI=$(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"} END{if(NR<2) print "N/A"}')
printf '🖥 Host: %s\n🕒 %s\n⏳ %s\n📈 load: %s\n%s\n💽 / %s\n' "$HN" "$DT" "$UP" "$LD" "$FR" "$DI"
EOS
)"
    ;;
  /docker)
    run_remote_snapshot "🐳 docker ps -a" "command -v docker >/dev/null 2>&1 && docker ps -a 2>&1 | head -n 65 || echo 'docker command missing or failed.'"
    ;;
  /dockerstats)
    run_remote_snapshot "🐳 docker stats (--no-stream)" "command -v docker >/dev/null 2>&1 && docker stats --no-stream --no-trunc=false 2>&1 | head -n 50 || echo 'docker stats failed.'"
    ;;
  /dockerdf)
    run_remote_snapshot "🐳 docker system df" "command -v docker >/dev/null 2>&1 && docker system df 2>&1 || echo 'docker missing or failed.'"
    ;;
  /dockerhealth)
    run_remote_snapshot "🐳 unhealthy containers" "$(cat <<'EOS'
command -v docker >/dev/null 2>&1 || { echo 'docker not installed.'; exit 0; }
U=$(docker ps -a --filter health=unhealthy --format '{{.Names}} {{.Status}}' 2>/dev/null || true)
if [[ -z "${U//[:space:]/}" ]]; then
  echo '(no unhealthy containers)'
else
  printf '%s\n' "$U"
fi
EOS
)"
    ;;
  /compose)
    run_remote_snapshot "🐳 docker compose ls -a" "command -v docker >/dev/null 2>&1 && docker compose ls -a 2>&1 | head -n 40 || echo 'docker compose missing or failed.'"
    ;;
  /dockernet)
    run_remote_snapshot "🐳 docker network ls" "command -v docker >/dev/null 2>&1 && docker network ls 2>&1 | head -n 50 || echo 'docker missing or failed.'"
    ;;
  /dockervol)
    run_remote_snapshot "🐳 docker volume ls" "command -v docker >/dev/null 2>&1 && docker volume ls 2>&1 | head -n 60 || echo 'docker missing or failed.'"
    ;;
  /dockerimg)
    run_remote_snapshot "🐳 docker images (trimmed)" "$(cat <<'EOS'
command -v docker >/dev/null 2>&1 || { echo 'docker not installed.'; exit 0; }
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.ID}}' 2>/dev/null | head -n 35
EOS
)"
    ;;
  /df)
    run_remote_snapshot "💽 df -hT" "df -hT 2>&1 | head -n 50"
    ;;
  /inode)
    run_remote_snapshot "📇 df -ih" "df -ih 2>&1 | head -n 50"
    ;;
  /mem)
    run_remote_snapshot "🧠 memory" "$(cat <<'EOS'
free -h 2>/dev/null || echo 'free command not available'
echo '---'
grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null || true
EOS
)"
    ;;
  /load)
    run_remote_snapshot "📈 load / uptime" "$(cat <<'EOS'
uptime 2>/dev/null || echo 'uptime N/A'
echo "---"
cat /proc/loadavg 2>/dev/null || true
EOS
)"
    ;;
  /disk)
    run_remote_snapshot "💽 lsblk" "lsblk -o NAME,SIZE,RO,TYPE,MOUNTPOINT -e 7,11 2>&1 | head -n 45"
    ;;
  /topcpu)
    run_remote_snapshot "🔥 Top CPU" "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu --no-headers 2>/dev/null | head -n 22 || ps aux --sort=-%cpu | head -n 22"
    ;;
  /topmem)
    run_remote_snapshot "🧠 Top MEM" "ps -eo pid,user,%mem,%cpu,comm --sort=-%mem --no-headers 2>/dev/null | head -n 22 || ps aux --sort=-%mem | head -n 22"
    ;;
  /ports)
    run_remote_snapshot "🔌 ss -tuln" "command -v ss >/dev/null 2>&1 && ss -tuln 2>&1 | head -n 100 || echo 'Install iproute2 (ss).'"
    ;;
  /ip)
    run_remote_snapshot "📶 ip -br a" "command -v ip >/dev/null 2>&1 && ip -br a 2>&1 || echo 'Install iproute2 (ip).'"
    ;;
  /failed)
    run_remote_snapshot "⚠️ systemd failed units" "$(cat <<'EOS'
command -v systemctl >/dev/null 2>&1 || { echo 'systemctl not found.'; exit 0; }
failed=$(systemctl list-units --failed --no-legend --no-pager 2>/dev/null | head -n 45)
if [[ -z "${failed//[:space:]/}" ]]; then
  echo '(no failed units)'
else
  printf '%s\n' "$failed"
fi
EOS
)"
    ;;
  /boot)
    run_remote_snapshot "⏰ boot / uptime" "$(cat <<'EOS'
who -b 2>/dev/null | head -n 1 || true
uptime -p 2>/dev/null || uptime 2>/dev/null || true
EOS
)"
    ;;
  /report|/status)
    if [[ "$ALLOW_REMOTE_REPORT" != "1" ]]; then
      send_msg "⛔ <code>/report</code> is disabled (ALLOW_REMOTE_REPORT=0)."
      return 0
    fi
    if ! net_ok; then
      queue_remote_job "$(basename "$PATH_REPORT")" "$PATH_REPORT"
      send_msg "🌐 Network is unavailable. Queued <code>/report</code>; it will run automatically when network is back."
      return 0
    fi
    run_script "$(basename "$PATH_REPORT")" "$PATH_REPORT"
    ;;
  /update)
    if [[ "$ALLOW_REMOTE_UPDATE" != "1" ]]; then
      send_msg "⛔ <code>/update</code> is disabled. Set ALLOW_REMOTE_UPDATE=1 in <code>${CONF_BOT}</code> (high risk)."
      return 0
    fi
    if ! net_ok; then
      queue_remote_job "$(basename "$PATH_UPDATE")" "$PATH_UPDATE"
      send_msg "🌐 Network is unavailable. Queued <code>/update</code>; it will run automatically when network is back."
      return 0
    fi
    run_script "$(basename "$PATH_UPDATE")" "$PATH_UPDATE"
    ;;
  *)
    send_msg "❓ Unknown command. Send <b>/help</b>."
    ;;
  esac
}

sync_bot_commands
send_msg "🤖 <b>ltm-bot</b> started — only configured Chat ID is accepted."

while true; do
  process_pending_jobs || true
  resp=$(curl -fsS --max-time $((POLL_TIMEOUT + 15)) \
    "${API}/getUpdates?offset=${OFFSET}&timeout=${POLL_TIMEOUT}" 2>/dev/null) || {
    sleep 5
    continue
  }

  if [[ "$(echo "$resp" | jq -r '.ok // false')" != "true" ]]; then
    sleep 3
    continue
  fi

  max_id=$(echo "$resp" | jq -r 'if (.result | length) == 0 then 0 else [.result[].update_id] | max end')

  mapfile -t items < <(
    echo "$resp" | jq -c --argjson cid "${TELEGRAM_CHAT_ID}" '
      .result[]?
      | select(.message.chat.id == $cid)
      | {id: .update_id, text: (.message.text // "")}
    ' 2>/dev/null
  )

  for row in "${items[@]:-}"; do
    [[ -z "${row:-}" ]] && continue
    txt=$(echo "$row" | jq -r '.text // empty')
    dispatch "$txt" || true
  done

  if [[ "${max_id:-0}" -gt 0 ]]; then
    OFFSET=$((max_id + 1))
  fi
done
