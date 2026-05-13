#!/usr/bin/env bash
# server-telegram-report.sh — Báo cáo tài nguyên server + Docker qua Telegram (không dùng btop)
#
# DEBIAN / UBUNTU — Gợi ý theo dõi (bật/tắt qua MONITOR_* trong /etc/server-telegram-report.conf):
#   Phần đầu tin: hostname, IP, OS (/etc/os-release), kernel, uptime, CPU/RAM/swap/đĩa /, load, nhiệt độ,
#   zombie, cảnh báo đầy ổ (DISK_ALERT_PERCENT), lsblk, RX/TX theo iface, Top CPU + Top MEM.
#   Khối tổng quát: boot (who -b), systemd failed units, df/inode, meminfo, cổng ss, ip -br,
#   timedatectl (NTP), trạng thái systemd, timers, định tuyến ip route, ss thống kê TCP,
#   pressure stall (/proc/pressure), resolvectl, UFW; trên APT: dpkg --audit, apt upgradable,
#   reboot-required.pkgs, unattended-upgrades; tuỳ chọn: needrestart, AppArmor, snap, flatpak;
#   RAID /proc/mdstat, mount NFS; TLS LE, journal err; Docker.
#
# CÀI ĐẶT
# -------
# sudo bash install.sh          # → /usr/local/bin/server-telegram-report và ltm-report (tên ngắn)
# sudo cp /usr/local/share/linux-telegram-monitor/server-telegram-report.conf.example /etc/server-telegram-report.conf
# sudo chmod 600 /etc/server-telegram-report.conf
# # điền TELEGRAM_BOT_TOKEN và TELEGRAM_CHAT_ID
# sudo server-telegram-report
#
# Cron mỗi 6 giờ:
# 0 */6 * * * /usr/local/bin/ltm-report >>/var/log/server-telegram-report.cron.log 2>&1
#
# Biến môi trường (nếu không dùng file): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
# Legacy: TOKEN, CHAT_ID vẫn được đọc nếu hai biến trên trống.

set -Eeuo pipefail

readonly CONF_SYSTEM="/etc/server-telegram-report.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/server-telegram-report.conf"

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"

TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"

: "${TELEGRAM_BOT_TOKEN:?Thiếu TELEGRAM_BOT_TOKEN (hoặc TOKEN) — $CONF_SYSTEM}"
: "${TELEGRAM_CHAT_ID:?Thiếu TELEGRAM_CHAT_ID (hoặc CHAT_ID) — $CONF_SYSTEM}"

CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
INSTALL_MISSING_DEPS="${INSTALL_MISSING_DEPS:-1}"
TZ="${TZ:-Asia/Ho_Chi_Minh}"

# Theo dõi bổ sung (1 = bật, 0 = tắt)
MONITOR_SYSTEMD_FAILED="${MONITOR_SYSTEMD_FAILED:-1}"
MONITOR_LAST_BOOT="${MONITOR_LAST_BOOT:-1}"
MONITOR_DF_ALL="${MONITOR_DF_ALL:-1}"
MONITOR_INODES="${MONITOR_INODES:-1}"
MONITOR_MEMINFO="${MONITOR_MEMINFO:-1}"
MONITOR_LISTEN_PORTS="${MONITOR_LISTEN_PORTS:-1}"
MONITOR_IP_BRIEF="${MONITOR_IP_BRIEF:-1}"
MONITOR_DOCKER="${MONITOR_DOCKER:-1}"
# Chỉ có hiệu lực khi MONITOR_DOCKER=1 và đã kết nối docker
MONITOR_DOCKER_SYSTEM_DF="${MONITOR_DOCKER_SYSTEM_DF:-1}"
MONITOR_DOCKER_HEALTH="${MONITOR_DOCKER_HEALTH:-1}"
MONITOR_DOCKER_COMPOSE="${MONITOR_DOCKER_COMPOSE:-0}"
MONITOR_DOCKER_NETWORKS="${MONITOR_DOCKER_NETWORKS:-0}"
# Cảnh báo & nâng cao (mặc định an toàn: journal/tls tắt nếu không cần)
MONITOR_ZOMBIES="${MONITOR_ZOMBIES:-1}"
MONITOR_DISK_ALERT="${MONITOR_DISK_ALERT:-1}"
DISK_ALERT_PERCENT="${DISK_ALERT_PERCENT:-90}"
MONITOR_TLS_CERTS="${MONITOR_TLS_CERTS:-0}"
CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"
MONITOR_JOURNAL_ERR="${MONITOR_JOURNAL_ERR:-0}"

# Debian / Ubuntu — chi tiết (1=bật). Phần APT chỉ chạy khi có apt-get.
MONITOR_OS_RELEASE="${MONITOR_OS_RELEASE:-1}"
MONITOR_TOP_MEM="${MONITOR_TOP_MEM:-1}"
MONITOR_TIMEDATECTL="${MONITOR_TIMEDATECTL:-1}"
MONITOR_DPKG_AUDIT="${MONITOR_DPKG_AUDIT:-1}"
MONITOR_APT_PENDING="${MONITOR_APT_PENDING:-1}"
APT_PENDING_LIST_LINES="${APT_PENDING_LIST_LINES:-50}"
MONITOR_REBOOT_PENDING="${MONITOR_REBOOT_PENDING:-1}"
MONITOR_SYSTEMD_SUMMARY="${MONITOR_SYSTEMD_SUMMARY:-1}"
MONITOR_SYSTEMD_TIMERS="${MONITOR_SYSTEMD_TIMERS:-1}"
MONITOR_IP_ROUTE="${MONITOR_IP_ROUTE:-1}"
MONITOR_SS_CONN_STATS="${MONITOR_SS_CONN_STATS:-1}"
MONITOR_PRESSURE="${MONITOR_PRESSURE:-1}"
MONITOR_RESOLVECTL="${MONITOR_RESOLVECTL:-1}"
MONITOR_UFW="${MONITOR_UFW:-1}"
MONITOR_NEEDRESTART="${MONITOR_NEEDRESTART:-0}"
MONITOR_APPARMOR="${MONITOR_APPARMOR:-0}"
MONITOR_SNAP="${MONITOR_SNAP:-0}"
MONITOR_FLATPAK="${MONITOR_FLATPAK:-0}"
MONITOR_UNATTENDED_UPGRADES="${MONITOR_UNATTENDED_UPGRADES:-1}"
MONITOR_MDSTAT="${MONITOR_MDSTAT:-1}"
MONITOR_NFS_MOUNTS="${MONITOR_NFS_MOUNTS:-1}"

API_MSG_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
API_DOC_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export TZ
export TMPDIR="${TMPDIR:-/tmp}"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- helpers ---
need() { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Cần quyền root để cài gói: $*" >&2
    return 1
  fi
}

install_missing() {
  local req=(curl sed awk grep ps free df lsblk uname hostname date tr head wc)
  local miss=()
  for b in "${req[@]}"; do
    need "$b" || miss+=("$b")
  done
  need ss || miss+=(ss)
  need ip || miss+=(ip)
  [ "${#miss[@]}" -eq 0 ] && return 0

  local pkgs_common=(curl sed gawk grep procps coreutils util-linux iproute2)
  local pkgs_sensors_apt=(lm-sensors)
  local pkgs_sensors_rpm=(lm_sensors)

  if command -v apt-get >/dev/null 2>&1; then
    as_root sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -yq update' || true
    as_root apt-get -yq install --no-install-recommends "${pkgs_common[@]}" "${pkgs_sensors_apt[@]}" || true
  elif command -v dnf >/dev/null 2>&1; then
    local pkgs_rhel=(curl sed gawk grep procps coreutils util-linux iproute)
    as_root dnf -y install "${pkgs_rhel[@]}" || true
    as_root dnf -y install epel-release || true
    as_root dnf -y install "${pkgs_sensors_rpm[@]}" || true
  elif command -v yum >/dev/null 2>&1; then
    as_root yum -y install curl sed gawk grep procps coreutils util-linux iproute || true
    as_root yum -y install epel-release || true
    as_root yum -y install "${pkgs_sensors_rpm[@]}" || true
  elif command -v apk >/dev/null 2>&1; then
    as_root apk add --no-cache curl sed gawk grep procps coreutils util-linux iproute2 || true
    as_root apk add --no-cache lm-sensors || true
  fi
}

tg_send() {
  curl --max-time "$CURL_TIMEOUT" -fsS -X POST "$API_MSG_URL" \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=$1" >/dev/null 2>&1 || true
}

tg_send_doc() {
  local file="$1" caption="${2:-}"
  [ -s "$file" ] || return 0
  curl --max-time "$CURL_TIMEOUT" -fsS -X POST "$API_DOC_URL" \
    -F "chat_id=$TELEGRAM_CHAT_ID" \
    -F "caption=$caption" \
    -F "document=@${file}" >/dev/null 2>&1 || true
  rm -f -- "$file" 2>/dev/null || true
}

sanitize_pre() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# Mountpoint % — các dòng có Use% ≥ ngưỡng (theo df -P)
collect_disk_pressure_lines() {
  local th="${DISK_ALERT_PERCENT:-90}"
  df -P -x tmpfs -x devtmpfs 2>/dev/null | awk -v th="$th" '
    NR > 1 && $1 ~ /^\/dev/ {
      pct = $(NF - 1)
      gsub(/%/, "", pct)
      if ((pct + 0) >= (th + 0))
        printf "%s  %s%%\n", $NF, pct
    }'
}

report_tls_letsencrypt() {
  [[ "$MONITOR_TLS_CERTS" != "1" ]] && return 0
  local ledir="/etc/letsencrypt/live"
  if ! command -v openssl >/dev/null 2>&1; then
    tg_send "<b>🔐 TLS</b>: cài <code>openssl</code> để kiểm tra chứng chỉ."
    return 0
  fi
  if [[ ! -d "$ledir" ]]; then
    tg_send "<b>🔐 TLS</b>: không có <code>$ledir</code> (bỏ qua Let's Encrypt)."
    return 0
  fi
  local out="" cert name line end_epoch now days warn wdays
  now=$(date +%s)
  wdays="${CERT_WARN_DAYS:-30}"
  shopt -s nullglob
  for cert in "$ledir"/*/cert.pem; do
    [[ -f "$cert" ]] || continue
    name=$(basename "$(dirname "$cert")")
    line=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2-)
    [[ -z "$line" ]] && continue
    if end_epoch=$(date -d "$line" +%s 2>/dev/null); then
      days=$(( (end_epoch - now) / 86400 ))
      warn=""
      [[ "$days" -lt "$wdays" ]] && warn="⚠️ "
      out+=$(printf '%s\n' "${warn}${name} | còn ${days} ngày (nhắc <${wdays}d) | notAfter=${line}")
    fi
  done
  shopt -u nullglob
  if [[ -z "$out" ]]; then
    out="(không đọc được cert.pem trong $ledir)"
  fi
  tg_send_pre_trunc "🔐 Chứng chỉ TLS (LE / openssl)" "$(printf '%s' "$out")"
}

# Khối text → Telegram &lt;pre&gt; (cắt nếu quá dài)
tg_send_pre_trunc() {
  local title=$1
  local raw=$2
  local limit="${3:-3800}"
  local esc
  esc=$(printf '%s' "$raw" | sanitize_pre)
  if [[ ${#esc} -gt "$limit" ]]; then
    esc="${esc:0:$limit}"$'\n...(đã cắt bớt)...'
  fi
  tg_send "<b>$title</b><pre>$esc</pre>"
}

# Chi tiết đặc thù Debian/Ubuntu (APT, systemd-resolved, UFW, …). Không làm fail báo cáo.
extra_monitoring_debian_ubuntu() {
  local buf apt_based=0 lines cnt est syn lis
  command -v apt-get >/dev/null 2>&1 && apt_based=1

  if [[ "$MONITOR_TIMEDATECTL" == "1" ]] && command -v timedatectl >/dev/null 2>&1; then
    buf=$(timedatectl status 2>/dev/null || true)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "🕐 timedatectl (timezone / NTP)" "$buf"
  fi

  if [[ "$apt_based" == "1" ]]; then
    if [[ "$MONITOR_DPKG_AUDIT" == "1" ]]; then
      buf=$(dpkg --audit 2>/dev/null || true)
      if [[ -z "${buf//[:space:]/}" ]]; then
        tg_send "<b>📋 dpkg --audit:</b> không có gói lỗi (hoặc không đọc được)."
      else
        tg_send_pre_trunc "📋 dpkg — gói cần xử lý (audit)" "$buf"
      fi
    fi

    if [[ "$MONITOR_APT_PENDING" == "1" ]]; then
      buf=$(apt list --upgradable 2>/dev/null | grep -v '^Listing' || true)
      cnt=$(printf '%s\n' "$buf" | grep -c . || true)
      lines="${APT_PENDING_LIST_LINES:-50}"
      tg_send_pre_trunc "📦 APT — có thể nâng cấp (đếm ~${cnt}, tối đa ${lines} dòng)" "$(printf 'Ước lượng số dòng gói: %s\n\n%s\n' "${cnt:-0}" "$(printf '%s\n' "$buf" | head -n "$lines")")"
    fi

    if [[ "$MONITOR_REBOOT_PENDING" == "1" ]]; then
      if [[ -f /var/run/reboot-required ]]; then
        buf="reboot-required: có"$'\n'
        if [[ -f /var/run/reboot-required.pkgs ]]; then
          buf+="reboot-required.pkgs (tối đa 45 dòng):"$'\n'"$(head -n 45 /var/run/reboot-required.pkgs 2>/dev/null || true)"
        else
          buf+="(không có reboot-required.pkgs)"
        fi
      else
        buf="reboot-required: không có cờ /var/run/reboot-required"
      fi
      tg_send_pre_trunc "🔁 Khởi động lại sau cập nhật (APT)" "$buf"
    fi

    if [[ "$MONITOR_UNATTENDED_UPGRADES" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
      if [[ -f /lib/systemd/system/unattended-upgrades.service ]] || [[ -f /usr/lib/systemd/system/unattended-upgrades.service ]]; then
        buf="is-enabled: $(systemctl is-enabled unattended-upgrades 2>/dev/null || echo 'n/a')"
        buf+=$'\n'"$(systemctl status unattended-upgrades --no-pager -l 2>/dev/null | head -n 22 || true)"
        tg_send_pre_trunc "🤖 unattended-upgrades (systemd)" "$buf"
      fi
    fi
  fi

  if [[ "$MONITOR_SYSTEMD_SUMMARY" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    buf="$(systemctl is-system-running 2>/dev/null || echo '?')"
    buf+=$'\n'"$(systemctl show --property=SystemState --property=FailedJobs --no-pager 2>/dev/null || true)"
    tg_send_pre_trunc "⚙️ systemd — running / SystemState" "$buf"
  fi

  if [[ "$MONITOR_SYSTEMD_TIMERS" == "1" ]] && command -v systemctl >/dev/null 2>&1; then
    buf=$(systemctl list-timers --all --no-pager 2>/dev/null | head -n 38)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "⏱ systemd timers" "$buf"
    buf=$(systemctl list-timers --failed --no-pager --no-legend 2>/dev/null || true)
    if [[ -n "${buf//[:space:]/}" ]]; then
      tg_send_pre_trunc "⚠️ systemd timers FAILED" "$buf"
    fi
  fi

  if [[ "$MONITOR_IP_ROUTE" == "1" ]] && need ip; then
    buf=$(ip route show 2>/dev/null | head -n 45)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "🛤 ip route" "$buf"
  fi

  if [[ "$MONITOR_SS_CONN_STATS" == "1" ]] && need ss; then
    est=$(ss -tan state established 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    syn=$(ss -tan state syn-recv 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    lis=$(ss -tan state listening 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    buf=$(printf 'TCP established rows: %s\nTCP syn-recv: %s\nTCP listening: %s\n\nSample established (≤25):\n%s' \
      "${est:-0}" "${syn:-0}" "${lis:-0}" "$(ss -tan state established 2>/dev/null | tail -n +2 | head -n 25)")
    tg_send_pre_trunc "🔌 TCP ss — thống kê & mẫu" "$buf"
  fi

  if [[ "$MONITOR_PRESSURE" == "1" ]]; then
    buf=""
    for f in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do
      [[ -r "$f" ]] && buf+="$(basename "$f"): $(cat "$f" 2>/dev/null || true)"$'\n'
    done
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "📉 Pressure stall (/proc/pressure)" "$buf"
  fi

  if [[ "$MONITOR_RESOLVECTL" == "1" ]] && command -v resolvectl >/dev/null 2>&1; then
    buf=$(resolvectl status 2>/dev/null | head -n 55)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "🔎 DNS (resolvectl)" "$buf"
  fi

  if [[ "$MONITOR_UFW" == "1" ]] && command -v ufw >/dev/null 2>&1; then
    buf=$(LC_ALL=C ufw status verbose 2>/dev/null | head -n 45)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "🛡 UFW" "$buf"
  fi

  if [[ "$MONITOR_NEEDRESTART" == "1" ]] && command -v needrestart >/dev/null 2>&1; then
    buf=$(needrestart -b 2>/dev/null | head -n 65 || true)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "♻️ needrestart (nhị phân/dịch vụ cần restart)" "$buf"
  fi

  if [[ "$MONITOR_APPARMOR" == "1" ]] && command -v aa-status >/dev/null 2>&1; then
    buf=$(aa-status 2>/dev/null | head -n 50)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "🔒 AppArmor (aa-status)" "$buf"
  fi

  if [[ "$MONITOR_SNAP" == "1" ]] && command -v snap >/dev/null 2>&1; then
    buf=$(snap list 2>/dev/null | head -n 42)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "📦 snap list" "$buf"
  fi

  if [[ "$MONITOR_FLATPAK" == "1" ]] && command -v flatpak >/dev/null 2>&1; then
    buf=$(flatpak list 2>/dev/null | head -n 38)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "📦 flatpak list" "$buf"
  fi

  if [[ "$MONITOR_MDSTAT" == "1" ]] && [[ -r /proc/mdstat ]]; then
    buf=$(grep -v '^$' /proc/mdstat 2>/dev/null || true)
    [[ -n "${buf//[:space:]/}" ]] && tg_send_pre_trunc "💿 /proc/mdstat (software RAID)" "$buf"
  fi

  if [[ "$MONITOR_NFS_MOUNTS" == "1" ]]; then
    if command -v findmnt >/dev/null 2>&1; then
      buf=$(findmnt -rn -t nfs,nfs4 2>/dev/null | head -n 35 || true)
    else
      buf=$(awk '$3 ~ /^nfs/ || $3 ~ /^nfs4/ {print}' /proc/mounts 2>/dev/null | head -n 35 || true)
    fi
    if [[ -n "${buf//[:space:]/}" ]]; then
      tg_send_pre_trunc "📁 NFS mounts" "$buf"
    fi
  fi
}

extra_monitoring() {
  local buf

  if [[ "$MONITOR_LAST_BOOT" == "1" ]] || [[ "$MONITOR_SYSTEMD_FAILED" == "1" ]]; then
    buf=""
    if [[ "$MONITOR_LAST_BOOT" == "1" ]]; then
      buf+="$(who -b 2>/dev/null | head -n 1)"$'\n\n'
    fi
    if [[ "$MONITOR_SYSTEMD_FAILED" == "1" ]]; then
      if command -v systemctl >/dev/null 2>&1; then
        buf+="systemctl --failed:"$'\n'
        local failed
        failed=$(systemctl list-units --failed --no-legend --no-pager 2>/dev/null | head -n 35)
        if [[ -z "${failed//[:space:]/}" ]]; then
          buf+="(không có unit failed)"$'\n'
        else
          buf+="$failed"$'\n'
        fi
      else
        buf+="(không có systemctl — bỏ qua failed units)"$'\n'
      fi
    fi
    tg_send_pre_trunc "⚙️ Boot &amp; systemd" "$buf"
  fi

  if [[ "$MONITOR_DF_ALL" == "1" ]]; then
    buf=$(df -hT 2>/dev/null | head -n 50)
    tg_send_pre_trunc "💽 Filesystems (df -hT)" "$buf"
  fi

  if [[ "$MONITOR_INODES" == "1" ]]; then
    buf=$(df -ih 2>/dev/null | head -n 50)
    tg_send_pre_trunc "📇 Inodes (df -ih)" "$buf"
  fi

  if [[ "$MONITOR_MEMINFO" == "1" ]]; then
    buf=$(grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree|SwapCached):' /proc/meminfo 2>/dev/null || true)
    [[ -n "$buf" ]] && tg_send_pre_trunc "🧠 /proc/meminfo (tóm tắt)" "$buf"
  fi

  if [[ "$MONITOR_LISTEN_PORTS" == "1" ]]; then
    if need ss; then
      buf=$(ss -tuln 2>/dev/null | head -n 100)
    else
      buf="(chưa có lệnh ss — cài gói iproute2 / iproute)"
    fi
    tg_send_pre_trunc "🔌 Cổng lắng nghe (ss -tuln)" "$buf"
  fi

  if [[ "$MONITOR_IP_BRIEF" == "1" ]]; then
    if need ip; then
      buf=$(ip -br a 2>/dev/null || true)
    else
      buf="(chưa có lệnh ip — cài iproute2 / iproute)"
    fi
    [[ -n "$buf" ]] && tg_send_pre_trunc "📶 Giao diện &amp; IP (ip -br a)" "$buf"
  fi

  extra_monitoring_debian_ubuntu

  report_tls_letsencrypt

  if [[ "$MONITOR_JOURNAL_ERR" == "1" ]]; then
    if command -v journalctl >/dev/null 2>&1; then
      buf=$(journalctl -p err..alert --no-pager -n 35 -q 2>/dev/null || true)
      if [[ -n "${buf//[:space:]/}" ]]; then
        tg_send_pre_trunc "📜 systemd journal (err…alert)" "$buf"
      else
        tg_send "<b>📜 journal</b>: không có dòng err/alert gần đây (hoặc không đọc được)."
      fi
    else
      tg_send "<b>📜 journal</b>: không có <code>journalctl</code>."
    fi
  fi
}

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

_cpu_idle_total() {
  awk '/^cpu /{
    user=$2; nice=$3; sys=$4; idle=$5; iow=$6; irq=$7; sirq=$8; steal=$9;
    if (iow=="") iow=0; if (irq=="") irq=0; if (sirq=="") sirq=0; if (steal=="") steal=0;
    total=user+nice+sys+idle+iow+irq+sirq+steal;
    print idle+iow, total; exit
  }' /proc/stat
}

cpu_usage() {
  read -r idle1 total1 < <(_cpu_idle_total)
  sleep 1
  read -r idle2 total2 < <(_cpu_idle_total)
  local didle=$((idle2 - idle1)) dtotal=$((total2 - total1))
  if [ "${dtotal:-0}" -gt 0 ]; then
    awk -v di="$didle" -v dt="$dtotal" 'BEGIN{printf "%.1f%%", 100*(1-di/dt)}'
  else
    echo "N/A"
  fi
}

cpu_temp() {
  if need sensors; then
    local t
    t=$(sensors 2>/dev/null | awk 'match($0,/\+?([0-9]+(\.[0-9]+)?)°C/,m){print m[1]; exit}')
    if [ -n "${t:-}" ]; then
      printf '%s°C' "$t"
      return 0
    fi
  fi
  local z type mv
  for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    type=$(tr '[:upper:]' '[:lower:]' <"$z/type" 2>/dev/null || true)
    case "$type" in
    *x86_pkg_temp* | *tctl* | *cpu* | *acpitz*)
      mv=$(cat "$z/temp" 2>/dev/null || true)
      if [ -n "$mv" ] && [ "$mv" -gt 0 ] 2>/dev/null; then
        awk -v mv="$mv" 'BEGIN{printf "%.1f°C", mv/1000.0}'
        return 0
      fi
      ;;
    esac
  done
  echo "N/A"
}

load_coretemp_if_possible() {
  if need sensors && need lsmod && need modprobe; then
    if ! lsmod 2>/dev/null | grep -q '^coretemp'; then
      as_root modprobe coretemp 2>/dev/null || true
    fi
  fi
}

docker_report() {
  if ! command -v docker >/dev/null 2>&1; then
    tg_send "<b>ℹ️ Docker:</b> chưa cài <code>docker</code>."
    return 0
  fi

  local sock="/var/run/docker.sock"
  if [ ! -S "$sock" ]; then
    tg_send "<b>ℹ️ Docker:</b> daemon chưa chạy (không thấy <code>$sock</code>)."
    return 0
  fi
  if [ ! -r "$sock" ] || [ ! -w "$sock" ]; then
    local ow
    ow=$(stat -c '%U:%G %a' "$sock" 2>/dev/null || echo "unknown")
    tg_send "<b>ℹ️ Docker:</b> không có quyền truy cập <code>$sock</code> (perm: <code>$ow</code>). Chạy script bằng user trong nhóm <code>docker</code> hoặc root."
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    tg_send "<b>ℹ️ Docker:</b> lỗi <code>docker info</code> (daemon không chạy hoặc không có quyền)."
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

  declare -A UPTIME STATUS CPU MEM MEM_PCT
  while IFS=$'\t' read -r name runfor status; do
    [[ -z "${name:-}" ]] && continue
    UPTIME["$name"]="$runfor"
    STATUS["$name"]="$status"
  done < <(docker ps -a --format '{{.Names}}\t{{.RunningFor}}\t{{.Status}}' 2>/dev/null)

  while IFS=$'\t' read -r name cpu mem mempct; do
    [[ -z "${name:-}" ]] && continue
    CPU["$name"]="$cpu"
    MEM["$name"]="$mem"
    MEM_PCT["$name"]="$mempct"
  done < <(docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null)

  mapfile -t NAMES < <(docker ps -a --format '{{.Names}}' 2>/dev/null)

  local tmpf
  tmpf="$(mktemp "${TMPDIR:-/tmp}/docker_report.XXXXXX.txt")"
  {
    printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "NAME" "UPTIME" "CPU" "MEM" "MEM%" "STATUS"
    printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "----------------------------" "--------------" "--------" "------------------------" "------" "--------------------"
    local n
    for n in "${NAMES[@]}"; do
      printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" \
        "${n:0:28}" "${UPTIME[$n]:-N/A}" "${CPU[$n]:-N/A}" "${MEM[$n]:-N/A}" "${MEM_PCT[$n]:-N/A}" "${STATUS[$n]:-N/A}"
    done
  } >"$tmpf"

  local CONTENT
  CONTENT=$(sanitize_pre <"$tmpf")
  rm -f -- "$tmpf"

  if [ "${#CONTENT}" -le 3800 ]; then
    tg_send "<b>📦 Containers</b><pre>$CONTENT</pre>"
  else
    tmpf="$(mktemp "${TMPDIR:-/tmp}/docker_report.XXXXXX.txt")"
    {
      printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "NAME" "UPTIME" "CPU" "MEM" "MEM%" "STATUS"
      printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" "----------------------------" "--------------" "--------" "------------------------" "------" "--------------------"
      local n2
      for n2 in "${NAMES[@]}"; do
        printf "%-28s %-14s %-8s %-24s %-7s %-20s\n" \
          "${n2:0:28}" "${UPTIME[$n2]:-N/A}" "${CPU[$n2]:-N/A}" "${MEM[$n2]:-N/A}" "${MEM_PCT[$n2]:-N/A}" "${STATUS[$n2]:-N/A}"
      done
    } >"$tmpf"
    tg_send_doc "$tmpf" "📦 Containers (chi tiết)"
  fi

  # --- Docker: bổ sung (container / tài nguyên) ---
  local dx
  if [[ "${MONITOR_DOCKER_SYSTEM_DF:-1}" == "1" ]]; then
    dx=$(docker system df 2>/dev/null || true)
    [[ -n "${dx//[:space:]/}" ]] && tg_send_pre_trunc "🐳 Docker — <code>system df</code> (ảnh/container/build cache)" "$dx"
  fi

  if [[ "${MONITOR_DOCKER_HEALTH:-1}" == "1" ]]; then
    dx=$(docker ps -a --filter health=unhealthy --format '{{.Names}}	{{.Status}}' 2>/dev/null || true)
    if [[ -z "${dx//[:space:]/}" ]]; then
      tg_send "<b>🐳 Healthcheck</b>: không có container <code>unhealthy</code>."
    else
      tg_send_pre_trunc "🐳 Container <code>unhealthy</code> (healthcheck)" "$(printf '%s\n' "$dx" | tr '\t' ' ')"
    fi
  fi

  if [[ "${MONITOR_DOCKER_COMPOSE:-0}" == "1" ]] && docker compose version >/dev/null 2>&1; then
    dx=$(docker compose ls -a 2>/dev/null || true)
    [[ -n "${dx//[:space:]/}" ]] && tg_send_pre_trunc "🐳 Compose — <code>docker compose ls -a</code>" "$dx"
  fi

  if [[ "${MONITOR_DOCKER_NETWORKS:-0}" == "1" ]]; then
    dx=$(docker network ls --format 'table {{.Name}}	{{.Driver}}	{{.Scope}}	{{.ID}}' 2>/dev/null | head -n 40 || true)
    [[ -n "${dx//[:space:]/}" ]] && tg_send_pre_trunc "🐳 Docker networks" "$dx"
  fi
}

# --- main ---
if [[ "$INSTALL_MISSING_DEPS" == "1" ]]; then
  install_missing || true
fi

load_coretemp_if_possible

OS_HTML=""
if [[ "$MONITOR_OS_RELEASE" == "1" ]] && [[ -r /etc/os-release ]]; then
  OS_PRETTY_LINE=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  OS_CODENAME=$(grep -E '^VERSION_CODENAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
  OS_SUFFIX=""
  [[ -n "${OS_CODENAME:-}" ]] && OS_SUFFIX=" (${OS_CODENAME})"
  OS_HTML=$'\n'"<b>📀 OS:</b> <code>${OS_PRETTY_LINE:-unknown}${OS_SUFFIX}</code>"
fi

HOSTNAME=$(hostname 2>/dev/null || echo "?")
IPV4_PUBLIC=$(curl -fsS -4 -m 3 --connect-timeout 2 https://ifconfig.me 2>/dev/null || echo "N/A")
IPV6_PUBLIC=$(curl -fsS -6 -m 3 --connect-timeout 2 https://ifconfig.me 2>/dev/null || echo "N/A")
IP_PRIVATE=$(hostname -I 2>/dev/null | awk '{print $1}')
DATE=$(date "+%d/%m/%Y %H:%M")
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
TEMP=$(cpu_temp)

ZOMBIE_LINE=""
if [[ "$MONITOR_ZOMBIES" == "1" ]]; then
  ZC=$(ps -eo stat= 2>/dev/null | grep -c '^Z' || true)
  ZOMBIE_LINE="• Zombies: <code>${ZC:-0}</code>"$'\n'
fi

DISK_ALERT_BLOCK=""
if [[ "$MONITOR_DISK_ALERT" == "1" ]]; then
  DPL=$(collect_disk_pressure_lines || true)
  if [[ -n "${DPL//[:space:]/}" ]]; then
    DISK_ALERT_BLOCK=$'\n'"⚠️ <b>Ổ gần đầy (≥${DISK_ALERT_PERCENT}%)</b>"$'\n'"<pre>$(printf '%s' "$DPL" | sanitize_pre)</pre>"
  fi
fi

MSG_HEAD=$(cat <<EOF
<b>📡 Server Report</b>

<b>🏷 Hostname:</b> <code>$HOSTNAME</code>
<b>🌐 IPv4 Public:</b> <code>$IPV4_PUBLIC</code>
<b>🌐 IPv6 Public:</b> <code>$IPV6_PUBLIC</code>
<b>🏠 IP Private:</b> <code>${IP_PRIVATE:-N/A}</code>
<b>🕰 Local Time:</b> <code>$DATE</code> (<code>$TZ</code>)
<b>🧰 Kernel:</b> <code>$KERNEL</code>
<b>⏳ Uptime:</b> <code>$UPTIME</code>${OS_HTML}

<b>📊 Resource</b>
• CPU: <code>$CPU</code>
• RAM: <code>$MEMORY</code>
• Swap: <code>$SWAP</code>
• Disk /: <code>$DISK_USED / $DISK_TOTAL ($DISK_PERCENT)</code>
• LoadAvg: <code>$LOAD_AVG</code>
• CPU Temp: <code>$TEMP</code>
• Processes / Sessions: <code>$PROCESS / $USERS</code>
${ZOMBIE_LINE}${DISK_ALERT_BLOCK}
EOF
)
tg_send "$MSG_HEAD"

DISK_INFO=$(lsblk -o NAME,SIZE,RO,TYPE,MOUNTPOINT -e 7,11 2>/dev/null || true)
DISK_INFO_PRETTY=$(printf "%s\n" "$DISK_INFO" | sed '1!s/^/  /' | sanitize_pre)
tg_send "<b>🗂️ Disk / block</b><pre>$DISK_INFO_PRETTY</pre>"

NET_LINES=()
NET_LINES+=("IFACE                RX         TX")
mapfile -t IFACES < <(ls /sys/class/net/ 2>/dev/null || true)
for iface in "${IFACES[@]}"; do
  [ -d "/sys/class/net/$iface/statistics" ] || continue
  rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
  tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
  NET_LINES+=("$(printf "%-20s %10s %10s" "$iface" "$(human_bytes "$rx")" "$(human_bytes "$tx")")")
done
NET_TABLE=$(printf "%s\n" "${NET_LINES[@]}" | sanitize_pre)
tg_send "<b>🌍 Network</b><pre>$NET_TABLE</pre>"

PS_SHOW=$(ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu 2>/dev/null | head -n 15 | sanitize_pre)
tg_send "<b>📝 Top CPU processes</b><pre>$PS_SHOW</pre>"

if [[ "$MONITOR_TOP_MEM" == "1" ]]; then
  PS_MEM_SHOW=$(ps -eo pid,user,%cpu,%mem,cmd --sort=-%mem 2>/dev/null | head -n 15 | sanitize_pre)
  tg_send "<b>📝 Top MEM processes</b><pre>$PS_MEM_SHOW</pre>"
fi

extra_monitoring

if [[ "$MONITOR_DOCKER" == "1" ]]; then
  docker_report
fi

exit 0
