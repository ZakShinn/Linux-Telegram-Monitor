# ltm-bot-core.sh — logic dung chung cho ltm-telegram-bot (vi/en)
# Goi: LTM_BOT_LANG=vi|en + source file nay + ltm_bot_main

: "${LTM_BOT_LANG:=vi}"
: "${CONF_BOT:=/etc/ltm-telegram-bot.conf}"
: "${CONF_REPORT:=/etc/server-telegram-report.conf}"

LTM_SHARE_DIR="${LTM_SHARE_DIR:-/usr/local/share/linux-telegram-monitor}"
PATH_SCHEDULE="${PATH_SCHEDULE:-/usr/local/bin/ltm-schedule}"
PATH_WATCH_SILENCE="${PATH_WATCH_SILENCE:-/var/lib/ltm-watch/silence_until}"
CONFIRM_DIR="${CONFIRM_DIR:-/var/run/ltm-bot-confirm}"
ALLOWED_SERVICES_FILE="${ALLOWED_SERVICES_FILE:-/etc/ltm-allowed-services.conf}"
ALLOWED_DOCKER_FILE="${ALLOWED_DOCKER_FILE:-/etc/ltm-allowed-docker.conf}"
EXEC_WHITELIST_FILE="${EXEC_WHITELIST_FILE:-/etc/ltm-allow-commands.conf}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/linux-telegram-monitor}"
REPORT_LOG="${REPORT_LOG:-/var/log/ltm-report.cron.log}"
UPDATE_LOG="${UPDATE_LOG:-/var/log/ltm-update.cron.log}"
VERSION_FILE="${VERSION_FILE:-/usr/local/share/linux-telegram-monitor/VERSION}"

ALLOW_REMOTE_ACTION="${ALLOW_REMOTE_ACTION:-0}"
CONFIRM_TTL_SEC="${CONFIRM_TTL_SEC:-90}"
TELEGRAM_ADMIN_CHAT_ID="${TELEGRAM_ADMIN_CHAT_ID:-}"

declare -a LTM_CHAT_IDS=()
declare -a PENDING_LABELS=()
declare -a PENDING_EXES=()

_t() {
  local k=$1
  case "$LTM_BOT_LANG:$k" in
    en:err_no_jq) echo "ltm-bot requires jq: sudo apt install jq" ;;
    en:err_need_report) echo "This command requires ALLOW_REMOTE_REPORT=1 in ${CONF_BOT}." ;;
    en:err_need_action) echo "This command requires ALLOW_REMOTE_ACTION=1 in ${CONF_BOT}." ;;
    en:err_admin_only) echo "Admin chat only. Set TELEGRAM_ADMIN_CHAT_ID in ${CONF_BOT}." ;;
    en:collecting) echo "Collecting" ;;
    en:no_output) echo "(no output)" ;;
    en:unknown_cmd) echo "Unknown command. Send /help." ;;
    en:confirm_usage) echo "Usage: /confirm &lt;token&gt;" ;;
    en:confirm_ok) echo "Confirmed. Running action..." ;;
    en:confirm_fail) echo "Invalid or expired token." ;;
    en:confirm_prompt) echo "Send within ${CONFIRM_TTL_SEC}s:" ;;
    en:not_whitelisted) echo "Not in whitelist:" ;;
    en:script_missing) echo "Script not found:" ;;
    en:report_disabled) echo "/report is disabled (ALLOW_REMOTE_REPORT=0)." ;;
    en:update_disabled) echo "/update is disabled. Set ALLOW_REMOTE_UPDATE=1 (high risk)." ;;
    en:action_disabled) echo "Remote actions disabled (ALLOW_REMOTE_ACTION=0)." ;;
    en:network_queue) echo "Offline. Queued" ;;
    en:network_back) echo "Network back. Running" ;;
    en:queued_jobs) echo "queued job(s)..." ;;
    en:bot_started) echo "ltm-bot running — authorized chat ID(s) only." ;;
    en:silence_ok) echo "ltm-watch alerts silenced until" ;;
    en:help_title) echo "Linux Telegram Monitor — commands" ;;
    vi:err_no_jq) echo "ltm-bot can lenh jq: sudo apt install jq" ;;
    vi:err_need_report) echo "Lenh nay can ALLOW_REMOTE_REPORT=1 trong ${CONF_BOT}." ;;
    vi:err_need_action) echo "Lenh nay can ALLOW_REMOTE_ACTION=1 trong ${CONF_BOT}." ;;
    vi:err_admin_only) echo "Chi chat admin. Dat TELEGRAM_ADMIN_CHAT_ID trong ${CONF_BOT}." ;;
    vi:collecting) echo "Thu thap" ;;
    vi:no_output) echo "(khong co dau ra)" ;;
    vi:unknown_cmd) echo "Lenh khong ro. Gui /help." ;;
    vi:confirm_usage) echo "Cach dung: /confirm &lt;token&gt;" ;;
    vi:confirm_ok) echo "Da xac nhan. Dang chay..." ;;
    vi:confirm_fail) echo "Token khong hop le hoac het han." ;;
    vi:confirm_prompt) echo "Gui trong ${CONFIRM_TTL_SEC}s:" ;;
    vi:not_whitelisted) echo "Khong nam trong whitelist:" ;;
    vi:script_missing) echo "Khong tim thay script:" ;;
    vi:report_disabled) echo "/report bi tat (ALLOW_REMOTE_REPORT=0)." ;;
    vi:update_disabled) echo "/update bi tat. Bat ALLOW_REMOTE_UPDATE=1 (rui ro cao)." ;;
    vi:action_disabled) echo "Hanh dong tu xa bi tat (ALLOW_REMOTE_ACTION=0)." ;;
    vi:network_queue) echo "Mat mang. Da xep hang" ;;
    vi:network_back) echo "Mang on lai. Dang chay lai" ;;
    vi:queued_jobs) echo "lenh da xep hang..." ;;
    vi:bot_started) echo "ltm-bot da chay — chi chat ID duoc phep." ;;
    vi:silence_ok) echo "ltm-watch tam tat canh bao den" ;;
    vi:help_title) echo "Linux Telegram Monitor — lenh" ;;
    *) echo "$k" ;;
  esac
}

ltm_parse_chat_ids() {
  LTM_CHAT_IDS=()
  local raw="${TELEGRAM_CHAT_ID// /,}"
  local id
  IFS=',' read -ra _parts <<< "$raw"
  for id in "${_parts[@]}"; do
    id="${id//[[:space:]]/}"
    [[ -n "$id" ]] && LTM_CHAT_IDS+=("$id")
  done
  [[ ${#LTM_CHAT_IDS[@]} -gt 0 ]] || LTM_CHAT_IDS=("$TELEGRAM_CHAT_ID")
  if [[ -z "${TELEGRAM_ADMIN_CHAT_ID// }" ]]; then
    TELEGRAM_ADMIN_CHAT_ID="${LTM_CHAT_IDS[0]}"
  fi
}

chat_is_allowed() {
  local cid=$1 id
  for id in "${LTM_CHAT_IDS[@]}"; do
    [[ "$id" == "$cid" ]] && return 0
  done
  return 1
}

chat_is_admin() {
  [[ "$1" == "$TELEGRAM_ADMIN_CHAT_ID" ]]
}

send_msg_to() {
  local cid=$1 text=$2
  curl -fsS --max-time 30 -X POST "${API}/sendMessage" \
    --data-urlencode "chat_id=${cid}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

send_msg() {
  local text=$1 cid
  for cid in "${LTM_CHAT_IDS[@]}"; do
    send_msg_to "$cid" "$text"
  done
}

sanitize_pre() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

send_pre_trunc_to() {
  local cid=$1 title=$2 raw=$3 limit="${4:-3800}"
  local esc trimmed
  esc=$(printf '%s' "$raw" | sanitize_pre)
  if [[ ${#esc} -gt "$limit" ]]; then
    if [[ "$LTM_BOT_LANG" == "en" ]]; then
      trimmed=$'\n...(trimmed)...'
    else
      trimmed=$'\n...(da cat)...'
    fi
    esc="${esc:0:$limit}${trimmed}"
  fi
  curl -fsS --max-time 45 -X POST "${API}/sendMessage" \
    --data-urlencode "chat_id=${cid}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=<b>${title}</b><pre>${esc}</pre>" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null 2>&1 || true
}

send_pre_trunc() {
  local title=$1 raw=$2 limit="${3:-3800}" cid
  for cid in "${LTM_CHAT_IDS[@]}"; do
    send_pre_trunc_to "$cid" "$title" "$raw" "$limit"
  done
}

net_ok() {
  curl -fsS --max-time 6 "${API}/getMe" >/dev/null 2>&1
}

normalize_cmd() {
  local t=$1
  t=${t%%@*}
  printf '%s' "$t" | tr '[:upper:]' '[:lower:]'
}

_in_whitelist_file() {
  local file=$1 name=$2
  [[ -f "$file" ]] || return 1
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -z "$line" ]] && continue
    [[ "$line" == "$name" ]] && return 0
  done <"$file"
  return 1
}

_confirm_token() {
  openssl rand -hex 3 2>/dev/null || head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

_request_confirm() {
  local action=$1 args=$2
  local tok exp
  mkdir -p "$CONFIRM_DIR" 2>/dev/null || true
  tok=$(_confirm_token)
  exp=$(($(date +%s) + CONFIRM_TTL_SEC))
  printf '%s\n' "$action" "$args" "$exp" >"${CONFIRM_DIR}/${tok}"
  if [[ "$LTM_BOT_LANG" == "en" ]]; then
    send_msg "⚠️ Confirm dangerous action <code>${action}</code>${args:+ — <code>${args}</code>}"
    send_msg "$(_t confirm_prompt) <b>/confirm ${tok}</b>"
  else
    send_msg "⚠️ Xác nhận hành động <code>${action}</code>${args:+ — <code>${args}</code>}"
    send_msg "$(_t confirm_prompt) <b>/confirm ${tok}</b>"
  fi
}

_handle_confirm() {
  local tok=$1
  local f="${CONFIRM_DIR}/${tok}"
  [[ -f "$f" ]] || { send_msg "❌ $(_t confirm_fail)"; return 1; }
  local action args exp now
  read -r action <"$f" || true
  read -r args < <(sed -n '2p' "$f") || true
  read -r exp < <(sed -n '3p' "$f") || true
  now=$(date +%s)
  rm -f "$f"
  if [[ -z "$action" ]] || [[ "${exp:-0}" -lt "$now" ]]; then
    send_msg "❌ $(_t confirm_fail)"
    return 1
  fi
  send_msg "✅ $(_t confirm_ok)"
  case "$action" in
  reboot) _do_reboot ;;
  service_restart) _do_service restart "$args" ;;
  service_stop) _do_service stop "$args" ;;
  service_start) _do_service start "$args" ;;
  docker_restart) _do_docker restart "$args" ;;
  docker_stop) _do_docker stop "$args" ;;
  docker_start) _do_docker start "$args" ;;
  docker_prune) _do_docker_prune ;;
  *) send_msg "❌ unknown action: <code>${action}</code>" ;;
  esac
}

_gate_report() {
  [[ "$ALLOW_REMOTE_REPORT" == "1" ]] || { send_msg "⛔ $(_t err_need_report)"; return 1; }
  return 0
}

_gate_action() {
  [[ "$ALLOW_REMOTE_ACTION" == "1" ]] || { send_msg "⛔ $(_t action_disabled)"; return 1; }
  return 0
}

_gate_admin() {
  local cid=$1
  chat_is_admin "$cid" || { send_msg "⛔ $(_t err_admin_only)"; return 1; }
  return 0
}

_run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif [[ -n "${SUDO_CMD:-}" ]]; then
    # shellcheck disable=SC2086
    $SUDO_CMD "$@"
  else
    sudo "$@"
  fi
}

_do_reboot() {
  send_msg "🔄 reboot..."
  sleep 2
  _run_as_root shutdown -r now "ltm-bot" || _run_as_root /sbin/reboot
}

_do_service() {
  local op=$1 unit=$2
  _in_whitelist_file "$ALLOWED_SERVICES_FILE" "$unit" || {
    send_msg "⛔ $(_t not_whitelisted) <code>${unit}</code>"
    return 0
  }
  local out
  out=$(_run_as_root systemctl "$op" "$unit" 2>&1) || true
  send_pre_trunc "systemctl ${op} ${unit}" "$out"
}

_do_docker() {
  local op=$1 name=$2
  command -v docker >/dev/null 2>&1 || { send_msg "docker missing"; return 0; }
  _in_whitelist_file "$ALLOWED_DOCKER_FILE" "$name" || {
    send_msg "⛔ $(_t not_whitelisted) <code>${name}</code>"
    return 0
  }
  local out
  out=$(docker "$op" "$name" 2>&1) || true
  send_pre_trunc "docker ${op} ${name}" "$out"
}

_do_docker_prune() {
  command -v docker >/dev/null 2>&1 || return 0
  local out
  out=$(docker system prune -f 2>&1) || true
  send_pre_trunc "docker system prune -f" "$out"
}

run_remote_snapshot() {
  local title=$1 script=$2
  _gate_report || return 0
  local out wt="$REMOTE_CMD_TIMEOUT"
  send_msg "⏳ $(_t collecting) <b>${title}</b>…"
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$wt" bash -lc "$script" 2>&1) || true
  else
    out=$(bash -lc "$script" 2>&1) || true
  fi
  [[ -z "${out//[:space:]/}" ]] && out="$(_t no_output)"
  send_pre_trunc "$title" "$out"
}

tail_log_file() {
  local title=$1 file=$2 lines=${3:-35}
  _gate_report || return 0
  if [[ ! -f "$file" ]]; then
    send_msg "❌ <code>${file}</code> — $(_t no_output)"
    return 0
  fi
  send_pre_trunc "$title" "$(tail -n "$lines" "$file" 2>/dev/null || true)"
}

run_script() {
  local label=$1 exe=$2
  if [[ ! -x "$exe" ]]; then
    send_msg "❌ $(_t script_missing) <code>${exe}</code>"
    return 0
  fi
  send_msg "⏳ <code>${label}</code>..."
  if [[ -n "${SUDO_CMD:-}" ]]; then
    # shellcheck disable=SC2086
    $SUDO_CMD "$exe" &
  else
    "$exe" &
  fi
}

queue_remote_job() {
  PENDING_LABELS+=("$1")
  PENDING_EXES+=("$2")
}

process_pending_jobs() {
  local n=${#PENDING_EXES[@]}
  [[ "$n" -gt 0 ]] || return 0
  net_ok || return 0
  send_msg "🌐 $(_t network_back) <b>${n}</b> $(_t queued_jobs)"
  local labels=("${PENDING_LABELS[@]}") exes=("${PENDING_EXES[@]}")
  PENDING_LABELS=()
  PENDING_EXES=()
  local i
  for ((i = 0; i < ${#exes[@]}; i++)); do
    run_script "${labels[$i]}" "${exes[$i]}"
  done
}

help_text() {
  if [[ "$LTM_BOT_LANG" == "en" ]]; then
    send_msg "<b>$(_t help_title)</b>

<b>Read</b> (ALLOW_REMOTE_REPORT=1): /quick /report /apt /rebootcheck /journal /tls /ufw /dns /route /timers /pressure /who /version /cron /schedule /lastreport /lastupdate + docker/* + system/*

<b>Actions</b> (ALLOW_REMOTE_ACTION=1, admin chat, confirm):
/reboot_now · /service restart|status &lt;unit&gt; · /docker restart|logs|prune · /apt_security

<b>Dangerous</b>: /update (ALLOW_REMOTE_UPDATE=1) · /silence 2h · /exec &lt;whitelisted&gt;

Menu: auto <code>setMyCommands</code> on start · refresh <b>/setcommands</b>"
  else
    send_msg "<b>$(_t help_title)</b>

<b>Đọc</b> (ALLOW_REMOTE_REPORT=1): /quick /report /apt /rebootcheck /journal /tls /ufw /dns /route /timers /pressure /who /version /cron /schedule /lastreport /lastupdate + docker/* + hệ thống

<b>Hành động</b> (ALLOW_REMOTE_ACTION=1, chat admin, /confirm):
/reboot_now · /service restart|status &lt;unit&gt; · /docker restart|logs|prune · /apt_security

<b>Nguy hiểm</b>: /update (ALLOW_REMOTE_UPDATE=1) · /silence 2h · /exec &lt;trong whitelist&gt;

Menu lệnh: tự <code>setMyCommands</code> khi chạy · cập nhật lại <b>/setcommands</b>"
  fi
}

# Danh sach menu lenh Telegram (setMyCommands) — UTF-8, co dau tren Telegram
_ltm_setmycommands_body() {
  if [[ "$LTM_BOT_LANG" == "en" ]]; then
    jq -c -n '{
      language_code: "en",
      commands: [
        {command:"start", description:"Start the bot"},
        {command:"help", description:"Command guide"},
        {command:"ping", description:"Check bot is online"},
        {command:"quick", description:"Quick server snapshot"},
        {command:"report", description:"Full resource report"},
        {command:"apt", description:"APT upgradable packages"},
        {command:"rebootcheck", description:"Reboot required flag"},
        {command:"journal", description:"Recent journal errors"},
        {command:"docker", description:"Docker containers list"},
        {command:"dockerstats", description:"Docker stats snapshot"},
        {command:"dockerhealth", description:"Unhealthy containers"},
        {command:"dockerlogs", description:"Container logs (name required)"},
        {command:"df", description:"Disk usage (df -hT)"},
        {command:"mem", description:"Memory summary"},
        {command:"load", description:"Load average"},
        {command:"failed", description:"Systemd failed units"},
        {command:"version", description:"LTM and system version"},
        {command:"schedule", description:"Cron schedule (ltm-schedule)"},
        {command:"lastreport", description:"Tail report cron log"},
        {command:"update", description:"Run system update (dangerous)"},
        {command:"silence", description:"Silence ltm-watch alerts (hours)"}
      ]
    }'
  else
    jq -c -n '{
      language_code: "vi",
      commands: [
        {command:"start", description:"Khởi động bot"},
        {command:"help", description:"Hướng dẫn sử dụng"},
        {command:"ping", description:"Kiểm tra bot online"},
        {command:"quick", description:"Tóm tắt nhanh server"},
        {command:"report", description:"Báo cáo tài nguyên đầy đủ"},
        {command:"apt", description:"Gói APT có thể nâng cấp"},
        {command:"rebootcheck", description:"Có cần reboot không"},
        {command:"journal", description:"Log lỗi gần đây (journal)"},
        {command:"docker", description:"Danh sách container Docker"},
        {command:"dockerstats", description:"Docker stats (một lần)"},
        {command:"dockerhealth", description:"Container unhealthy"},
        {command:"dockerlogs", description:"Log container (kèm tên)"},
        {command:"df", description:"Dung lượng ổ (df)"},
        {command:"mem", description:"Thông tin RAM"},
        {command:"load", description:"Load average"},
        {command:"failed", description:"Systemd unit lỗi"},
        {command:"version", description:"Phiên bản LTM / hệ thống"},
        {command:"schedule", description:"Lịch cron báo cáo"},
        {command:"lastreport", description:"Xem log báo cáo gần nhất"},
        {command:"update", description:"Cập nhật hệ thống (nguy hiểm)"},
        {command:"silence", description:"Tắt cảnh báo ltm-watch (giờ)"}
      ]
    }'
  fi
}

# POST https://api.telegram.org/bot<token>/setMyCommands  (JSON body)
sync_bot_commands() {
  command -v jq >/dev/null 2>&1 || return 0

  local body lang_code resp ok
  body=$(_ltm_setmycommands_body) || return 0
  lang_code=$(echo "$body" | jq -r '.language_code // empty')

  if [[ -n "$lang_code" ]]; then
    curl -fsS --max-time 20 -X POST "${API}/deleteMyCommands" \
      -H "Content-Type: application/json" \
      -d "{\"language_code\":\"${lang_code}\"}" >/dev/null 2>&1 || true
  else
    curl -fsS --max-time 20 -X POST "${API}/deleteMyCommands" >/dev/null 2>&1 || true
  fi

  resp=$(curl -fsS --max-time 30 -X POST "${API}/setMyCommands" \
    -H "Content-Type: application/json" \
    -d "$body" 2>&1) || resp='{"ok":false}'

  ok=$(echo "$resp" | jq -r '.ok // false' 2>/dev/null || echo false)
  if [[ "$ok" != "true" ]]; then
    echo "ltm-bot: setMyCommands failed: ${resp}" >&2
  fi
}

dispatch() {
  local raw=$1 from_cid=${2:-}
  [[ -z "${raw//[:space:]/}" ]] && return 0
  local first cmd rest
  first=$(printf '%s' "$raw" | awk '{print $1}')
  rest=$(printf '%s' "$raw" | cut -d' ' -f2-)
  cmd=$(normalize_cmd "$first")

  case "$cmd" in
  /help|/start) help_text ;;
  /setcommands|/synccommands)
    _gate_admin "$from_cid" || return 0
    sync_bot_commands
    if [[ "$LTM_BOT_LANG" == "en" ]]; then
      send_msg "✅ Bot command menu updated (<code>setMyCommands</code>)."
    else
      send_msg "✅ Đã cập nhật menu lệnh bot (<code>setMyCommands</code>)."
    fi
    ;;
  /ping) send_msg "pong — <code>$(hostname -s 2>/dev/null || echo '?')</code>" ;;

  /confirm)
    tok="${rest%% *}"
    tok="${tok//[[:space:]]/}"
    [[ -z "$tok" ]] && { send_msg "$(_t confirm_usage)"; return 0; }
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    _handle_confirm "$tok"
    ;;

  /silence)
    _gate_admin "$from_cid" || return 0
    local hrs="${rest:-2}"
    hrs="${hrs//[^0-9.]/}"
    [[ -z "$hrs" ]] && hrs=2
    local until
    until=$(($(date +%s) + ${hrs%.*} * 3600))
    mkdir -p "$(dirname "$PATH_WATCH_SILENCE")" 2>/dev/null || true
    echo "$until" >"$PATH_WATCH_SILENCE" 2>/dev/null || true
    send_msg "🔕 $(_t silence_ok) <code>$(date -d "@$until" '+%F %T' 2>/dev/null || date -r "$until" '+%F %T' 2>/dev/null || echo "$until")</code>"
    ;;

  /quick)
    run_remote_snapshot "⚡ Quick" "$(cat <<'EOS'
HN=$(hostname 2>/dev/null || echo "?")
DT=$(date 2>/dev/null || echo "?")
UP=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")
LD=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "N/A")
FR=$(free -h 2>/dev/null || echo "(no free)")
DI=$(df -h / 2>/dev/null | awk 'NR==2{print $3" / "$2" ("$5")"} END{if(NR<2) print "N/A"}')
printf 'Host: %s\nTime: %s\nUptime: %s\nload: %s\n%s\n/: %s\n' "$HN" "$DT" "$UP" "$LD" "$FR" "$DI"
EOS
)"
    ;;

  /apt)
    run_remote_snapshot "📦 APT" "$(cat <<'EOS'
command -v apt-get >/dev/null 2>&1 || { echo 'apt-get not found'; exit 0; }
echo '=== reboot-required ==='
if [[ -f /var/run/reboot-required ]]; then
  cat /var/run/reboot-required 2>/dev/null
  [[ -f /var/run/reboot-required.pkgs ]] && head -n 20 /var/run/reboot-required.pkgs
else
  echo '(no reboot-required flag)'
fi
echo ''
echo '=== apt list --upgradable (max 45) ==='
apt list --upgradable 2>/dev/null | grep -v '^Listing' | head -n 45
EOS
)"
    ;;

  /rebootcheck|/reboot)
    run_remote_snapshot "🔁 reboot-required" "$(cat <<'EOS'
if [[ -f /var/run/reboot-required ]]; then
  echo 'reboot-required: YES'
  cat /var/run/reboot-required 2>/dev/null
  echo '--- packages ---'
  head -n 30 /var/run/reboot-required.pkgs 2>/dev/null || true
else
  echo 'reboot-required: NO'
fi
EOS
)"
    ;;

  /journal)
    run_remote_snapshot "📜 journal" "command -v journalctl >/dev/null 2>&1 && journalctl -p err..alert --no-pager -n 35 -q 2>/dev/null || echo 'no journalctl'"
    ;;

  /tls)
    run_remote_snapshot "🔐 TLS (LE)" "$(cat <<'EOS'
command -v openssl >/dev/null 2>&1 || { echo 'need openssl'; exit 0; }
ledir=/etc/letsencrypt/live
[[ -d "$ledir" ]] || { echo "no $ledir"; exit 0; }
now=$(date +%s)
for cert in "$ledir"/*/cert.pem; do
  [[ -f "$cert" ]] || continue
  name=$(basename "$(dirname "$cert")")
  line=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2-)
  end=$(date -d "$line" +%s 2>/dev/null || echo 0)
  days=$(( (end - now) / 86400 ))
  echo "$name | ${days}d left | notAfter=$line"
done
EOS
)"
    ;;

  /ufw)
    run_remote_snapshot "🛡 UFW" "command -v ufw >/dev/null 2>&1 && ufw status verbose 2>&1 | head -n 45 || echo 'ufw not installed'"
    ;;

  /dns)
    run_remote_snapshot "🔎 DNS" "command -v resolvectl >/dev/null 2>&1 && resolvectl status 2>/dev/null | head -n 55 || echo 'no resolvectl'"
    ;;

  /route)
    run_remote_snapshot "🛤 route" "command -v ip >/dev/null 2>&1 && ip route show 2>/dev/null | head -n 45 || echo 'no ip'"
    ;;

  /timers)
    run_remote_snapshot "⏱ timers" "command -v systemctl >/dev/null 2>&1 && systemctl list-timers --all --no-pager 2>/dev/null | head -n 38 || echo 'no systemctl'"
    ;;

  /pressure)
    run_remote_snapshot "📉 pressure" "$(cat <<'EOS'
for f in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do
  [[ -r "$f" ]] && echo "$(basename "$f"): $(cat "$f" 2>/dev/null)"
done
EOS
)"
    ;;

  /who)
    run_remote_snapshot "👤 sessions" "$(cat <<'EOS'
who 2>/dev/null || true
echo '---'
w 2>/dev/null | head -n 15 || true
EOS
)"
    ;;

  /version)
    run_remote_snapshot "ℹ️ version" "$(cat <<EOS
LTM: \$(cat '${VERSION_FILE}' 2>/dev/null || echo 'unknown')
Kernel: \$(uname -r 2>/dev/null)
Host: \$(hostname -f 2>/dev/null || hostname)
Docker: \$(command -v docker >/dev/null 2>&1 && docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/A')
EOS
)"
    ;;

  /cron)
    run_remote_snapshot "📅 cron LTM" "$(cat <<EOS
[[ -f '${CRON_FILE}' ]] && cat '${CRON_FILE}' || echo '(no ${CRON_FILE})'
EOS
)"
    ;;

  /schedule)
    _gate_report || return 0
    if [[ -x "$PATH_SCHEDULE" ]]; then
      run_remote_snapshot "📅 ltm-schedule show" "'$PATH_SCHEDULE' show 2>&1"
    else
      run_remote_snapshot "📅 cron" "cat '${CRON_FILE}' 2>/dev/null || echo missing"
    fi
    ;;

  /lastreport) tail_log_file "📄 last report log" "$REPORT_LOG" 40 ;;
  /lastupdate) tail_log_file "📄 last update log" "$UPDATE_LOG" 40 ;;

  /docker) run_remote_snapshot "🐳 docker ps -a" "command -v docker >/dev/null 2>&1 && docker ps -a 2>&1 | head -n 65 || echo 'no docker'" ;;
  /dockerstats) run_remote_snapshot "🐳 docker stats" "command -v docker >/dev/null 2>&1 && docker stats --no-stream 2>&1 | head -n 50 || echo 'fail'" ;;
  /dockerdf) run_remote_snapshot "🐳 docker system df" "command -v docker >/dev/null 2>&1 && docker system df 2>&1 || echo 'no docker'" ;;
  /dockerhealth)
    run_remote_snapshot "🐳 unhealthy" "$(cat <<'EOS'
command -v docker >/dev/null 2>&1 || { echo 'no docker'; exit 0; }
U=$(docker ps -a --filter health=unhealthy --format '{{.Names}} {{.Status}}' 2>/dev/null || true)
[[ -z "${U//[:space:]/}" ]] && echo '(none)' || printf '%s\n' "$U"
EOS
)"
    ;;
  /compose) run_remote_snapshot "🐳 compose ls" "command -v docker >/dev/null 2>&1 && docker compose ls -a 2>&1 | head -n 40 || echo 'no compose'" ;;
  /dockernet) run_remote_snapshot "🐳 networks" "docker network ls 2>&1 | head -n 50" ;;
  /dockervol) run_remote_snapshot "🐳 volumes" "docker volume ls 2>&1 | head -n 60" ;;
  /dockerimg)
    run_remote_snapshot "🐳 images" "docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null | head -n 35"
    ;;

  /df) run_remote_snapshot "💽 df -hT" "df -hT 2>&1 | head -n 50" ;;
  /inode) run_remote_snapshot "📇 df -ih" "df -ih 2>&1 | head -n 50" ;;
  /mem)
    run_remote_snapshot "🧠 mem" "$(cat <<'EOS'
free -h 2>/dev/null; echo '---'
grep -E '^(MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null
EOS
)"
    ;;
  /load) run_remote_snapshot "📈 load" "uptime 2>/dev/null; echo '---'; cat /proc/loadavg 2>/dev/null" ;;
  /disk) run_remote_snapshot "💽 lsblk" "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>&1 | head -n 45" ;;
  /topcpu) run_remote_snapshot "🔥 top cpu" "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 22" ;;
  /topmem) run_remote_snapshot "🧠 top mem" "ps -eo pid,user,%mem,%cpu,comm --sort=-%mem 2>/dev/null | head -n 22" ;;
  /ports) run_remote_snapshot "🔌 ports" "ss -tuln 2>&1 | head -n 100" ;;
  /ip) run_remote_snapshot "📶 ip" "ip -br a 2>&1" ;;
  /failed)
    run_remote_snapshot "⚠️ failed units" "$(cat <<'EOS'
systemctl list-units --failed --no-legend --no-pager 2>/dev/null | head -n 45 || echo '(none)'
EOS
)"
    ;;
  /boot) run_remote_snapshot "⏰ boot" "who -b 2>/dev/null; uptime -p 2>/dev/null || uptime" ;;

  /apt_security)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    run_remote_snapshot "🔒 apt security" "$(cat <<'EOS'
if command -v unattended-upgrade >/dev/null 2>&1; then
  unattended-upgrade -d 2>&1 | tail -n 40
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq 2>/dev/null || true
  apt list --upgradable 2>/dev/null | head -n 40
else
  echo 'no apt tools'
fi
EOS
)"
    ;;

  /reboot_now)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    _request_confirm reboot ""
    ;;

  /service)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    local sop sname
    sop=$(printf '%s' "$rest" | awk '{print $1}')
    sname=$(printf '%s' "$rest" | awk '{print $2}')
    case "$sop" in
    restart|start|stop|status) ;;
    *)
      send_msg "Usage: /service restart|start|stop|status &lt;unit&gt;"
      return 0
      ;;
    esac
    [[ -z "$sname" ]] && { send_msg "Missing unit name"; return 0; }
    if [[ "$sop" == "status" ]]; then
      run_remote_snapshot "systemctl status ${sname}" "systemctl status '${sname}' --no-pager -l 2>&1 | head -n 40"
      return 0
    fi
    _request_confirm "service_${sop}" "$sname"
    ;;

  /docker_restart|/dockerrestart)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    local dname
    dname=$(printf '%s' "$rest" | awk '{print $1}')
    [[ -z "$dname" ]] && { send_msg "Usage: /docker_restart &lt;name&gt;"; return 0; }
    _request_confirm docker_restart "$dname"
    ;;

  /docker_logs|/dockerlogs)
    _gate_report || return 0
    local dname lines
    dname=$(printf '%s' "$rest" | awk '{print $1}')
    lines=$(printf '%s' "$rest" | awk '{print $2}')
    [[ -z "$dname" ]] && { send_msg "Usage: /docker_logs &lt;name&gt; [lines]"; return 0; }
    [[ -z "$lines" ]] && lines=80
    lines="${lines//[^0-9]/}"
    [[ -z "$lines" ]] && lines=80
    [[ "$lines" -gt 200 ]] && lines=200
    run_remote_snapshot "docker logs ${dname}" "docker logs --tail '${lines}' '${dname}' 2>&1"
    ;;

  /docker_prune|/dockerprune)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    _request_confirm docker_prune ""
    ;;

  /exec)
    _gate_action || return 0
    _gate_admin "$from_cid" || return 0
    local ename
    ename=$(printf '%s' "$rest" | awk '{print $1}')
    [[ -z "$ename" ]] && { send_msg "Usage: /exec &lt;name-in-whitelist&gt;"; return 0; }
    _in_whitelist_file "$EXEC_WHITELIST_FILE" "$ename" || {
      send_msg "⛔ $(_t not_whitelisted) <code>${ename}</code>"
      return 0
    }
    local script="${LTM_SHARE_DIR}/exec/${ename}.sh"
    [[ -x "$script" ]] || script="/etc/ltm/exec/${ename}.sh"
    [[ -x "$script" ]] || { send_msg "❌ missing <code>${script}</code>"; return 0; }
    run_remote_snapshot "exec ${ename}" "'${script}' 2>&1"
    ;;

  /report|/status)
    if [[ "$ALLOW_REMOTE_REPORT" != "1" ]]; then
      send_msg "⛔ $(_t report_disabled)"
      return 0
    fi
    if ! net_ok; then
      queue_remote_job "$(basename "$PATH_REPORT")" "$PATH_REPORT"
      send_msg "🌐 $(_t network_queue) <code>/report</code>"
      return 0
    fi
    run_script "$(basename "$PATH_REPORT")" "$PATH_REPORT"
    ;;

  /update)
    if [[ "$ALLOW_REMOTE_UPDATE" != "1" ]]; then
      send_msg "⛔ $(_t update_disabled)"
      return 0
    fi
    if ! net_ok; then
      queue_remote_job "$(basename "$PATH_UPDATE")" "$PATH_UPDATE"
      send_msg "🌐 $(_t network_queue) <code>/update</code>"
      return 0
    fi
    run_script "$(basename "$PATH_UPDATE")" "$PATH_UPDATE"
    ;;

  *)
    send_msg "❓ $(_t unknown_cmd)"
    ;;
  esac
}

ltm_bot_main() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$(_t err_no_jq)" >&2
    exit 1
  fi

  ltm_parse_chat_ids
  API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
  OFFSET=0

  sync_bot_commands
  send_msg "🤖 <b>$(_t bot_started)</b>"

  local chat_json
  chat_json=$(printf '%s' "${LTM_CHAT_IDS[*]}" | jq -R 'split(" ") | map(tonumber?) | map(select(. != null))' 2>/dev/null || echo '[]')
  # build jq array from chat ids
  local jq_ids="["
  local cid first=1
  for cid in "${LTM_CHAT_IDS[@]}"; do
    [[ "$first" -eq 1 ]] || jq_ids+=","
    jq_ids+="$cid"
    first=0
  done
  jq_ids+="]"

  while true; do
    process_pending_jobs || true
    local resp max_id
    resp=$(curl -fsS --max-time $((POLL_TIMEOUT + 15)) \
      "${API}/getUpdates?offset=${OFFSET}&timeout=${POLL_TIMEOUT}" 2>/dev/null) || {
      sleep 5
      continue
    }

    [[ "$(echo "$resp" | jq -r '.ok // false')" == "true" ]] || {
      sleep 3
      continue
    }

    max_id=$(echo "$resp" | jq -r 'if (.result | length) == 0 then 0 else [.result[].update_id] | max end')

    mapfile -t items < <(
      echo "$resp" | jq -c --argjson ids "$jq_ids" '
        .result[]?
        | select(.message.chat.id as $c | $ids | index($c))
        | {id: .update_id, cid: .message.chat.id, text: (.message.text // "")}
      ' 2>/dev/null
    )

    local row txt from_cid
    for row in "${items[@]:-}"; do
      [[ -z "${row:-}" ]] && continue
      txt=$(echo "$row" | jq -r '.text // empty')
      from_cid=$(echo "$row" | jq -r '.cid // empty')
      dispatch "$txt" "$from_cid" || true
    done

    [[ "${max_id:-0}" -gt 0 ]] && OFFSET=$((max_id + 1))
  done
}
