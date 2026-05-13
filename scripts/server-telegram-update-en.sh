#!/usr/bin/env bash
# server-telegram-update-en.sh — APT update + optional fwupd + Telegram summary (English)

set -euo pipefail

readonly CONF_SYSTEM="/etc/server-telegram-update.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/server-telegram-update.conf"

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"

: "${TELEGRAM_BOT_TOKEN:?Missing TELEGRAM_BOT_TOKEN — $CONF_SYSTEM}"
: "${TELEGRAM_CHAT_ID:?Missing TELEGRAM_CHAT_ID — $CONF_SYSTEM}"

SEND_LOG_AS_DOCUMENT="${SEND_LOG_AS_DOCUMENT:-1}"
REBOOT_IF_REQUIRED="${REBOOT_IF_REQUIRED:-0}"
RUN_FWUPD="${RUN_FWUPD:-1}"

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
KERNEL_BEFORE="$(uname -r)"
OS="$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
start_time="$(date '+%Y-%m-%d %H:%M:%S')"
start_epoch=$(date +%s)

log_dir="/var/log"
log_file="${log_dir}/server-telegram-update_$(date +%F_%H-%M-%S).log"
[[ -w "$log_dir" ]] 2>/dev/null || log_file="${TMPDIR:-/tmp}/server-telegram-update_$(date +%F_%H-%M-%S).log"

df_root_line() { df -hP / 2>/dev/null | awk 'NR==2 {print $4" free / "$2" total "$5; exit}'; }
mem_avail_line() { free -h 2>/dev/null | awk '/^Mem:/{print $7" available, total "$2}'; }

DISK_BEFORE="$(df_root_line || echo "N/A")"
MEM_BEFORE="$(mem_avail_line || echo "N/A")"

apt_update_exit=0
apt_upgrade_exit=0
fwupd_rc=0
fwupd_status=""
overall_status="OK"
upgrade_list_text=""
pkg_count=0
need_restart_hint=""
kernel_after=""
reboot_hint_pkgs=""

html_escape() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

tg_send_message_html() {
  curl -fsS --connect-timeout 15 --max-time 120 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=$1" \
    --data-urlencode "disable_web_page_preview=true" >/dev/null || true
}

tg_send_document() {
  curl -fsS --connect-timeout 15 --max-time 300 -X POST \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID}" \
    -F "document=@${1}" \
    -F "caption=${2}" >/dev/null || true
}

collect_upgrade_list() {
  local upgrade_raw
  upgrade_raw=$(apt list --upgradable 2>/dev/null | awk 'NR>1' || true)
  [[ -z "$upgrade_raw" ]] && return 0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pkg new_ver old_ver
    pkg=$(printf '%s' "$line" | cut -d/ -f1)
    new_ver=$(printf '%s' "$line" | awk '{print $2}')
    old_ver=$(printf '%s' "$line" | grep -oP '\[upgradable from: \K[^]]+' || true)
    [[ -z "$pkg" ]] && continue
    printf '%s\n' "$pkg | ${old_ver:-?} -> ${new_ver:-?}"
  done <<< "$upgrade_raw"
}

{
  echo "=== Start: $start_time ==="
  echo "Host: $HOSTNAME"
  echo "OS: $OS"
  echo "Kernel (before): $KERNEL_BEFORE"
  echo "Root FS (before): $DISK_BEFORE"
  echo "RAM (before): $MEM_BEFORE"
  echo

  echo "--- apt update ---"
  if ! apt-get update -y; then
    apt_update_exit=$?
    overall_status="apt update failed"
    echo "apt-get update exit code: $apt_update_exit"
  fi

  upgrade_list_text="$(collect_upgrade_list || true)"
  if [[ -n "$upgrade_list_text" ]]; then
    pkg_count=$(printf '%s\n' "$upgrade_list_text" | grep -c . || true)
  else
    pkg_count=0
  fi

  echo "Upgradable packages count: $pkg_count"
  [[ -n "$upgrade_list_text" ]] && printf '%s\n' "$upgrade_list_text"
  echo

  echo "--- apt upgrade ---"
  if ! apt-get upgrade -y -o Dpkg::Options::=--force-confold; then
    apt_upgrade_exit=$?
    overall_status="apt upgrade failed"
  fi

  echo "--- apt full-upgrade ---"
  if ! apt-get full-upgrade -y -o Dpkg::Options::=--force-confold; then
    overall_status="apt full-upgrade failed"
    apt_upgrade_exit=2
  fi

  echo "--- apt autoremove ---"
  apt-get autoremove -y --purge || true

  echo "--- apt autoclean ---"
  apt-get autoclean -y || true

  if [[ "${RUN_FWUPD}" == "1" ]] && command -v fwupdmgr >/dev/null 2>&1; then
    echo "--- fwupdmgr ---"
    export FWUPD_NONINTERACTIVE=1
    fwupdmgr refresh || fwupd_rc=1
    if ! fwupdmgr update -y; then
      fwupdmgr update || fwupd_rc=1
    fi
    [[ "$fwupd_rc" -eq 0 ]] && fwupd_status="OK" || fwupd_status="failed (see log)"
  elif [[ "${RUN_FWUPD}" != "1" ]]; then
    echo "--- fwupdmgr: skipped (RUN_FWUPD=0) ---"
    fwupd_status="disabled (RUN_FWUPD=0)"
  else
    echo "--- fwupdmgr: command not found (apt install fwupd) ---"
    fwupd_status="fwupdmgr not found"
  fi

  if command -v needrestart >/dev/null 2>&1; then
    echo "--- needrestart ---"
    needrestart -b 2>/dev/null | head -n 50 || true
    need_restart_hint=$(needrestart -b 2>/dev/null | head -n 20 || true)
  fi

  if [[ -f "/var/run/reboot-required" ]]; then
    echo "--- /var/run/reboot-required ---"
    cat /var/run/reboot-required 2>/dev/null || true
  fi
  if [[ -f "/var/run/reboot-required.pkgs" ]]; then
    echo "--- reboot-required.pkgs (trimmed) ---"
    head -n 30 /var/run/reboot-required.pkgs 2>/dev/null || true
    reboot_hint_pkgs=$(head -n 15 /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' '; ' || true)
  fi

  kernel_after="$(uname -r)"
  echo
  echo "Kernel (after): $kernel_after"
  echo "Root FS (after): $(df_root_line || echo N/A)"
  echo "=== End: $(date '+%Y-%m-%d %H:%M:%S') ==="
} &>"$log_file"

end_epoch=$(date +%s)
elapsed_sec=$((end_epoch - start_epoch))
[[ -z "$kernel_after" ]] && kernel_after="$(uname -r)"

[[ "$apt_update_exit" -ne 0 || "$apt_upgrade_exit" -ne 0 ]] && overall_status="APT failed (see log)"
[[ "$fwupd_rc" -ne 0 && "$overall_status" == "OK" ]] && overall_status="FWUPD warning (see log)"

list_html=""
if [[ -n "$upgrade_list_text" ]]; then
  esc_list="$(html_escape "$upgrade_list_text")"
  if [[ ${#esc_list} -gt 3500 ]]; then
    esc_list="${esc_list:0:3500}"$'\n...(trimmed, see log file)...'
  fi
  list_html="<pre>${esc_list}</pre>"
else
  list_html="<i>No packages in upgradable list after apt update (or apt update failed).</i>"
fi

needrestart_block=""
if [[ -n "${need_restart_hint:-}" ]]; then
  needrestart_block=$'\n\n'"<b>needrestart</b>"$'\n'"<pre>$(html_escape "$need_restart_hint")</pre>"
fi

reboot_pkgs_block=""
if [[ -n "$reboot_hint_pkgs" ]]; then
  reboot_pkgs_block=$'\n'"<b>Packages triggering reboot</b> (trimmed): <code>$(html_escape "$reboot_hint_pkgs")</code>"
fi

reboot_block=""
if [[ -f "/var/run/reboot-required" ]]; then
  reboot_block=$'\n\n'"⚠️ <b>/var/run/reboot-required</b> is present — reboot is recommended when appropriate."
  if [[ "$REBOOT_IF_REQUIRED" == "1" ]]; then
    reboot_block+=$'\n'"<i>REBOOT_IF_REQUIRED=1 — reboot will run after sending Telegram.</i>"
  fi
fi

kernel_note=""
if [[ "$kernel_after" != "$KERNEL_BEFORE" ]]; then
  kernel_note=$'\n'"<i>Running kernel changed in this session (${KERNEL_BEFORE} -> ${kernel_after}). Reboot is usually needed to fully switch to the new kernel.</i>"
else
  kernel_note=$'\n'"<i>Running kernel: <code>$(html_escape "$kernel_after")</code> (a reboot may still be needed if new kernel packages were installed).</i>"
fi

msg="<b>📦 System update report (APT)</b>

<b>What this run tracked</b>:
• <b>Before</b>: root FS free space and available RAM.
• <b>APT</b>: <code>apt update</code> -> upgradable list -> <code>upgrade</code>/<code>full-upgrade</code> -> <code>autoremove</code>/<code>autoclean</code>.
• <b>FWUPD</b>: device firmware update (if enabled and available).
• <b>needrestart</b>: services/binaries that may need restart.
• <b>reboot-required</b>: reboot hint files under <code>/var/run/</code>.

🖥 <b>Host</b>: $(html_escape "$HOSTNAME")
🧬 <b>OS</b>: $(html_escape "$OS")

📋 <b>Resource snapshot</b>
• Root FS before: <code>$(html_escape "$DISK_BEFORE")</code>
• RAM before: <code>$(html_escape "$MEM_BEFORE")</code>$kernel_note

🧪 <b>Kernel before</b>: <code>$(html_escape "$KERNEL_BEFORE")</code>
🧪 <b>Kernel after</b>: <code>$(html_escape "$kernel_after")</code>

📦 <b>Upgradable packages (after apt update)</b>: <b>$pkg_count</b>
$list_html

🔌 <b>FWUPD</b>: $(html_escape "${fwupd_status:-N/A}")$reboot_pkgs_block
⏱ <b>Duration</b>: <b>${elapsed_sec}s</b>
📊 <b>Status</b>: $(html_escape "$overall_status")
🕒 <b>Start / End</b>: $(html_escape "$start_time") -> $(html_escape "$(date '+%Y-%m-%d %H:%M:%S')")
$needrestart_block$reboot_block

📄 Log: <code>$(html_escape "$log_file")</code>"

tg_send_message_html "$msg"

if [[ "$SEND_LOG_AS_DOCUMENT" == "1" ]] && [[ -f "$log_file" ]]; then
  tg_send_document "$log_file" "Update log: $start_time"
fi

if [[ "$REBOOT_IF_REQUIRED" == "1" ]] && [[ -f "/var/run/reboot-required" ]]; then
  sleep 5
  systemd-run --unit=server-telegram-update-reboot /sbin/shutdown -r now "server-telegram-update" || /sbin/shutdown -r now
fi

exit 0
