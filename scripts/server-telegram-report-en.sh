#!/usr/bin/env bash
# server-telegram-report-en.sh — English Telegram report for Ubuntu/Debian
# Uses the same config files as server-telegram-report.sh:
#   /etc/server-telegram-report.conf
#   ~/.config/server-telegram-report.conf

set -Eeuo pipefail

readonly CONF_SYSTEM="/etc/server-telegram-report.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/server-telegram-report.conf"

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"

: "${TELEGRAM_BOT_TOKEN:?Missing TELEGRAM_BOT_TOKEN (or TOKEN) — $CONF_SYSTEM}"
: "${TELEGRAM_CHAT_ID:?Missing TELEGRAM_CHAT_ID (or CHAT_ID) — $CONF_SYSTEM}"

CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
TZ="${TZ:-UTC}"
MONITOR_DOCKER="${MONITOR_DOCKER:-1}"

API_MSG_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
API_DOC_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ
export TMPDIR="${TMPDIR:-/tmp}"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

need() { command -v "$1" >/dev/null 2>&1; }

tg_send() {
  curl --max-time "$CURL_TIMEOUT" -fsS -X POST "$API_MSG_URL" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=$1" >/dev/null 2>&1 || true
}

tg_send_doc() {
  local file="$1" caption="${2:-}"
  [[ -s "$file" ]] || return 0
  curl --max-time "$CURL_TIMEOUT" -fsS -X POST "$API_DOC_URL" \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "caption=$caption" \
    -F "document=@${file}" >/dev/null 2>&1 || true
  rm -f -- "$file" 2>/dev/null || true
}

sanitize_pre() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

human_bytes() {
  local b="${1:-0}"
  if need numfmt; then
    numfmt --to=iec --suffix=B --format="%.2f" "$b" 2>/dev/null || echo "0B"
  else
    awk -v x="$b" 'BEGIN{
      if (x<=0){print "0B"; exit}
      split("B KB MB GB TB",u); i=1;
      while (x>=1024 && i<5){x/=1024;i++}
      printf "%.2f %s\n", x, u[i]
    }'
  fi
}

cpu_usage() {
  local idle1 total1 idle2 total2 didle dtotal
  read -r idle1 total1 < <(awk '/^cpu /{print $5+$6, $2+$3+$4+$5+$6+$7+$8+$9; exit}' /proc/stat)
  sleep 1
  read -r idle2 total2 < <(awk '/^cpu /{print $5+$6, $2+$3+$4+$5+$6+$7+$8+$9; exit}' /proc/stat)
  didle=$((idle2 - idle1))
  dtotal=$((total2 - total1))
  if [[ "$dtotal" -gt 0 ]]; then
    awk -v di="$didle" -v dt="$dtotal" 'BEGIN{printf "%.1f%%", 100*(1-di/dt)}'
  else
    echo "N/A"
  fi
}

docker_report() {
  if ! need docker; then
    tg_send "<b>ℹ️ Docker:</b> <code>docker</code> is not installed."
    return 0
  fi
  if ! docker info >/dev/null 2>&1; then
    tg_send "<b>ℹ️ Docker:</b> daemon not available or insufficient permissions."
    return 0
  fi

  local ver containers running images
  ver="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'N/A')"
  containers="$(docker ps -aq 2>/dev/null | wc -l | awk '{print $1}')"
  running="$(docker ps -q 2>/dev/null | wc -l | awk '{print $1}')"
  images="$(docker images -q 2>/dev/null | wc -l | awk '{print $1}')"

  tg_send "<b>🐳 Docker</b>
• Version: <code>$ver</code>
• Containers: <code>$containers</code> (running: <code>$running</code>)
• Images: <code>$images</code>"

  local tmpf
  tmpf="$(mktemp "${TMPDIR:-/tmp}/docker_report_en.XXXXXX.txt")"
  {
    printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "NAME" "UPTIME" "CPU" "MEM" "MEM%" "STATUS"
    printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "----------------------------" "--------------" "--------" "------------------------" "------" "--------------------"
    docker ps -a --format '{{.Names}}|{{.RunningFor}}|{{.Status}}' 2>/dev/null | while IFS='|' read -r name runfor status; do
      [[ -z "${name:-}" ]] && continue
      printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "${name:0:28}" "${runfor:-N/A}" "N/A" "N/A" "N/A" "${status:-N/A}"
    done
  } >"$tmpf"

  tg_send_doc "$tmpf" "Docker containers (English report)"
}

HOSTNAME=$(hostname 2>/dev/null || echo "?")
IPV4_PUBLIC=$(curl -fsS -4 -m 3 --connect-timeout 2 https://ifconfig.me 2>/dev/null || echo "N/A")
IPV6_PUBLIC=$(curl -fsS -6 -m 3 --connect-timeout 2 https://ifconfig.me 2>/dev/null || echo "N/A")
IP_PRIVATE=$(hostname -I 2>/dev/null | awk '{print $1}')
DATE=$(date "+%Y-%m-%d %H:%M:%S")
UPTIME=$(uptime -p 2>/dev/null || echo "N/A")
KERNEL=$(uname -r)
LOAD_AVG=$(awk '{print $1" "$2" "$3}' /proc/loadavg)
CPU=$(cpu_usage)
MEMORY=$(free -h | awk '/Mem:/ {print $3 " / " $2}')
SWAP=$(free -h | awk '/Swap:/ {print $3 " / " $2}')
DISK_TOTAL=$(df -h / 2>/dev/null | awk '/\/$/ {print $2; exit}')
DISK_USED=$(df -h / 2>/dev/null | awk '/\/$/ {print $3; exit}')
DISK_PERCENT=$(df -h / 2>/dev/null | awk '/\/$/ {print $5; exit}')
PROCESS=$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')
USERS=$(who 2>/dev/null | wc -l | tr -d ' ')

OS_HTML=""
if [[ -r /etc/os-release ]]; then
  OS_PRETTY_LINE=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  OS_CODENAME=$(grep -E '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  OS_SUFFIX=""
  [[ -n "${OS_CODENAME:-}" ]] && OS_SUFFIX=" (${OS_CODENAME})"
  OS_HTML=$'\n'"<b>📀 OS:</b> <code>${OS_PRETTY_LINE:-unknown}${OS_SUFFIX}</code>"
fi

MSG_HEAD=$(cat <<EOF
<b>📡 Server Report (English)</b>

<b>🏷 Hostname:</b> <code>$HOSTNAME</code>
<b>🌐 IPv4 Public:</b> <code>$IPV4_PUBLIC</code>
<b>🌐 IPv6 Public:</b> <code>$IPV6_PUBLIC</code>
<b>🏠 Private IP:</b> <code>${IP_PRIVATE:-N/A}</code>
<b>🕰 Local Time:</b> <code>$DATE</code> (<code>$TZ</code>)
<b>🧰 Kernel:</b> <code>$KERNEL</code>
<b>⏳ Uptime:</b> <code>$UPTIME</code>${OS_HTML}

<b>📊 Resources</b>
• CPU: <code>$CPU</code>
• RAM: <code>$MEMORY</code>
• Swap: <code>$SWAP</code>
• Disk /: <code>$DISK_USED / $DISK_TOTAL ($DISK_PERCENT)</code>
• LoadAvg: <code>$LOAD_AVG</code>
• Processes / Sessions: <code>$PROCESS / $USERS</code>
EOF
)
tg_send "$MSG_HEAD"

DISK_INFO=$(lsblk -o NAME,SIZE,RO,TYPE,MOUNTPOINT -e 7,11 2>/dev/null || true)
DISK_INFO_PRETTY=$(printf "%s\n" "$DISK_INFO" | sed '1!s/^/  /' | sanitize_pre)
tg_send "<b>🗂️ Disk / block devices</b><pre>$DISK_INFO_PRETTY</pre>"

NET_LINES=()
NET_LINES+=("IFACE                RX         TX")
mapfile -t IFACES < <(ls /sys/class/net/ 2>/dev/null || true)
for iface in "${IFACES[@]}"; do
  [[ -d "/sys/class/net/$iface/statistics" ]] || continue
  rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
  tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
  NET_LINES+=("$(printf "%-20s %10s %10s" "$iface" "$(human_bytes "$rx")" "$(human_bytes "$tx")")")
done
NET_TABLE=$(printf "%s\n" "${NET_LINES[@]}" | sanitize_pre)
tg_send "<b>🌍 Network I/O</b><pre>$NET_TABLE</pre>"

PS_CPU=$(ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu 2>/dev/null | head -n 15 | sanitize_pre)
tg_send "<b>📝 Top CPU processes</b><pre>$PS_CPU</pre>"

PS_MEM=$(ps -eo pid,user,%cpu,%mem,cmd --sort=-%mem 2>/dev/null | head -n 15 | sanitize_pre)
tg_send "<b>📝 Top memory processes</b><pre>$PS_MEM</pre>"

if [[ "$MONITOR_DOCKER" == "1" ]]; then
  docker_report
fi

exit 0
