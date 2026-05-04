#!/usr/bin/env bash
# ubuntu-telegram-update.sh — Cập nhật Ubuntu + thông báo Telegram
#
# CÀI ĐẶT NHANH
# --------------
# Từ thư mục repo (khuyến nghị — cài vào /usr/local/bin):
#      sudo bash install.sh
# Hoặc thủ công:
#      sudo install -m 755 ubuntu-telegram-update.sh /usr/local/bin/ubuntu-telegram-update
# File cấu hình (sau khi chạy install.sh, mẫu nằm tại
# /usr/local/share/linux-telegram-monitor/ubuntu-telegram-update.conf.example):
#      sudo cp .../ubuntu-telegram-update.conf.example /etc/ubuntu-telegram-update.conf
#      sudo chmod 600 /etc/ubuntu-telegram-update.conf
#      sudo nano /etc/ubuntu-telegram-update.conf
#    Điền TELEGRAM_BOT_TOKEN và TELEGRAM_CHAT_ID.
# Chạy thử:
#      sudo ubuntu-telegram-update
#
# Cron hàng tuần (ví dụ Chủ nhật 3:00):
#      sudo crontab -e
#      0 3 * * 0 /usr/local/bin/ubuntu-telegram-update >> /var/log/ubuntu-telegram-update.cron.log 2>&1
#
# Hoặc systemd timer: gọi /usr/local/bin/ubuntu-telegram-update

set -euo pipefail

readonly CONF_SYSTEM="/etc/ubuntu-telegram-update.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/ubuntu-telegram-update.conf"

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"

: "${TELEGRAM_BOT_TOKEN:?Thiếu TELEGRAM_BOT_TOKEN — cấu hình $CONF_SYSTEM hoặc biến môi trường}"
: "${TELEGRAM_CHAT_ID:?Thiếu TELEGRAM_CHAT_ID — cấu hình $CONF_SYSTEM hoặc biến môi trường}"

SEND_LOG_AS_DOCUMENT="${SEND_LOG_AS_DOCUMENT:-1}"
REBOOT_IF_REQUIRED="${REBOOT_IF_REQUIRED:-0}"
RUN_FWUPD="${RUN_FWUPD:-1}"

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
KERNEL="$(uname -r)"
OS="$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
start_time="$(date '+%Y-%m-%d %H:%M:%S')"
log_file="/var/log/ubuntu-telegram-update_$(date +%F_%H-%M-%S).log"
if [[ ! -w "$(dirname "$log_file")" ]]; then
  log_file="/tmp/ubuntu-telegram-update_$(date +%F_%H-%M-%S).log"
fi

apt_update_exit=0
apt_upgrade_exit=0
fwupd_rc=0
fwupd_status=""
overall_status="OK"

# Escape cho Telegram HTML (chỉ vài ký tự cần thiết khi dùng <pre>)
html_escape() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

tg_send_message_html() {
  local text=$1
  curl -fsS --connect-timeout 15 --max-time 120 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${text}" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null || true
}

tg_send_document() {
  local path=$1 caption=$2
  curl -fsS --connect-timeout 15 --max-time 300 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "document=@${path}" \
    -F "caption=${caption}" >/dev/null || true
}

# Thu thập danh sách nâng cấp (sau apt update); văn bản thuần, escape HTML khi gửi Telegram
collect_upgrade_list() {
  local upgrade_raw
  upgrade_raw=$(apt list --upgradable 2>/dev/null | awk 'NR>1' || true)
  if [[ -z "$upgrade_raw" ]]; then
    printf ''
    return
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pkg new_ver old_ver
    pkg=$(printf '%s' "$line" | cut -d/ -f1)
    new_ver=$(printf '%s' "$line" | awk '{print $2}')
    old_ver=$(printf '%s' "$line" | grep -oP '\[upgradable from: \K[^]]+' || true)
    [[ -z "$pkg" ]] && continue
    printf '%s\n' "$pkg | ${old_ver:-?} → ${new_ver:-?}"
  done <<< "$upgrade_raw"
}

upgrade_list_text=""
pkg_count=0
need_restart_hint=""

{
  echo "=== Bắt đầu: $start_time ==="
  echo "Host: $HOSTNAME"
  echo "OS: $OS"
  echo "Kernel: $KERNEL"
  echo

  echo "--- apt update ---"
  if ! apt-get update -y; then
    apt_update_exit=$?
    overall_status="LỖI apt update"
    echo "apt-get update thất bại (mã $apt_update_exit)"
  fi

  upgrade_list_text="$(collect_upgrade_list || true)"
  if [[ -n "$upgrade_list_text" ]]; then
    pkg_count=$(printf '%s\n' "$upgrade_list_text" | grep -c . || true)
  else
    pkg_count=0
  fi

  echo "Số gói có bản nâng cấp (ước lượng): $pkg_count"
  [[ -n "$upgrade_list_text" ]] && printf '%s\n' "$upgrade_list_text"
  echo

  echo "--- apt upgrade ---"
  if ! apt-get upgrade -y -o Dpkg::Options::=--force-confold; then
    apt_upgrade_exit=$?
    overall_status="LỖI apt upgrade"
  fi

  echo "--- apt full-upgrade ---"
  if ! apt-get full-upgrade -y -o Dpkg::Options::=--force-confold; then
    overall_status="LỖI apt full-upgrade"
    apt_upgrade_exit=2
  fi

  echo "--- apt autoremove ---"
  apt-get autoremove -y --purge || true

  echo "--- apt autoclean ---"
  apt-get autoclean -y || true

  # Firmware qua fwupd (nếu có gói fwupd / lệnh fwupdmgr)
  if [[ "${RUN_FWUPD}" == "1" ]] && command -v fwupdmgr >/dev/null 2>&1; then
    echo "--- fwupdmgr refresh ---"
    export FWUPD_NONINTERACTIVE=1
    fwupdmgr refresh || fwupd_rc=1
    echo "--- fwupdmgr update ---"
    if ! fwupdmgr update -y; then
      fwupdmgr update || fwupd_rc=1
    fi
    if [[ "$fwupd_rc" -eq 0 ]]; then
      fwupd_status="OK"
    else
      fwupd_status="có lỗi (xem log)"
    fi
  elif [[ "${RUN_FWUPD}" != "1" ]]; then
    echo "--- fwupdmgr (bỏ qua: RUN_FWUPD=0) ---"
    fwupd_status="tắt (RUN_FWUPD=0)"
  else
    echo "--- fwupdmgr (bỏ qua: chưa cài fwupd / không có lệnh) ---"
    fwupd_status="không có fwupdmgr (apt install fwupd)"
  fi

  if command -v needrestart >/dev/null 2>&1; then
    echo "--- needrestart (tóm tắt) ---"
    needrestart -b 2>/dev/null | head -n 50 || true
    need_restart_hint=$'\n'"$(needrestart -b 2>/dev/null | head -n 20 || true)"
  fi

  reboot_required_file="/var/run/reboot-required"
  if [[ -f "$reboot_required_file" ]]; then
    echo "--- Reboot được khuyến nghị (/var/run/reboot-required) ---"
    cat "$reboot_required_file" 2>/dev/null || true
  fi

  echo
  echo "=== Kết thúc: $(date '+%Y-%m-%d %H:%M:%S') ==="
} &> "$log_file"

if [[ "$apt_update_exit" -ne 0 ]] || [[ "$apt_upgrade_exit" -ne 0 ]]; then
  overall_status="Có lỗi trong quá trình cập nhật (xem log)"
fi
if [[ "$fwupd_rc" -ne 0 ]] && [[ "$overall_status" == "OK" ]]; then
  overall_status="Cảnh báo: fwupdmgr (xem log)"
fi

list_html=""
if [[ -n "$upgrade_list_text" ]]; then
  esc_list="$(html_escape "$upgrade_list_text")"
  if [[ ${#esc_list} -gt 3500 ]]; then
    esc_list="${esc_list:0:3500}"$'\n...(đã cắt bớt — mở file log để xem đủ danh sách)...'
  fi
  list_html="<pre>${esc_list}</pre>"
else
  list_html="<i>Không có gói nào trong danh sách nâng cấp sau apt update (hoặc apt update lỗi).</i>"
fi

needrestart_block=""
if [[ -n "${need_restart_hint:-}" ]]; then
  needrestart_block=$'\n\n'"<b>needrestart (rút gọn)</b>"$'\n'"<pre>$(html_escape "$need_restart_hint")</pre>"
fi

reboot_block=""
if [[ -f "/var/run/reboot-required" ]]; then
  reboot_block=$'\n\n'"⚠️ <b>Hệ thống khuyến nghị khởi động lại</b> (tồn tại /var/run/reboot-required)."
  if [[ "$REBOOT_IF_REQUIRED" == "1" ]]; then
    reboot_block+=$'\n'"<i>REBOOT_IF_REQUIRED=1 — sẽ reboot sau khi gửi Telegram...</i>"
  fi
fi

msg="🔧 <b>Báo cáo cập nhật Ubuntu</b>

🖥 <b>Host</b>: $(html_escape "$HOSTNAME")
🧬 <b>OS</b>: $(html_escape "$OS")
🧪 <b>Kernel</b>: <code>$(html_escape "$KERNEL")</code>

📦 <b>Gói có bản mới (ước lượng)</b>: <b>$pkg_count</b>
$list_html

🔌 <b>FWUPD</b> <code>fwupdmgr</code>: $(html_escape "${fwupd_status:-N/A}")
📊 <b>Trạng thái</b>: $(html_escape "$overall_status")
🕒 <b>Bắt đầu</b>: $(html_escape "$start_time")
🕒 <b>Kết thúc</b>: $(html_escape "$(date '+%Y-%m-%d %H:%M:%S')")
$needrestart_block$reboot_block

📄 Log: <code>$(html_escape "$log_file")</code>"

tg_send_message_html "$msg"

if [[ "$SEND_LOG_AS_DOCUMENT" == "1" ]] && [[ -f "$log_file" ]]; then
  tg_send_document "$log_file" "Log chi tiết: $start_time"
fi

if [[ "$REBOOT_IF_REQUIRED" == "1" ]] && [[ -f "/var/run/reboot-required" ]]; then
  sleep 5
  systemd-run --unit="ubuntu-telegram-update-reboot" /sbin/shutdown -r now "ubuntu-telegram-update: reboot theo cấu hình" || /sbin/shutdown -r now
fi

exit 0
