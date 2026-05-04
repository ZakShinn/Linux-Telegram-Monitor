#!/usr/bin/env bash
# Cài vào PREFIX/bin. Symlink: ltm-update, ltm-report
#
#   sudo bash install.sh
#
# Tự động bỏ qua hỏi tuỳ chọn: SKIP_INSTALL_PROMPTS=1 hoặc không có TTY (cron/pipe)
# Kiểu cấu hình (chỉ khi có TTY): LTM_INSTALL_PROFILE=basic|advanced — bỏ qua menu chọn 1/2
# Lịch cron sau cài khi không hỏi: LTM_INSTALL_CRON=default (báo ~6 giờ + cập nhật CN)
# Chỉ tạo file trong DESTDIR (đóng gói): không ghi /etc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
BIN="${DESTDIR}${PREFIX}/bin"
SHARE="${DESTDIR}${PREFIX}/share/linux-telegram-monitor"

if [[ "$(id -u)" -ne 0 ]] && [[ -z "$DESTDIR" ]]; then
  echo "Chạy với sudo để ghi ${PREFIX}/bin (hoặc chỉ DESTDIR)." >&2
  exit 1
fi

install -d -m 755 "$BIN"
install -d -m 755 "$SHARE"

install -m 755 "$SCRIPT_DIR/scripts/server-telegram-update.sh" "$BIN/server-telegram-update"
install -m 755 "$SCRIPT_DIR/scripts/server-telegram-report.sh" "$BIN/server-telegram-report"
install -m 755 "$SCRIPT_DIR/scripts/ltm-telegram-bot.sh" "$BIN/ltm-bot"
install -m 755 "$SCRIPT_DIR/scripts/ltm-schedule.sh" "$BIN/ltm-schedule"

ln -sf server-telegram-update "$BIN/ltm-update"
ln -sf server-telegram-report "$BIN/ltm-report"

install -m 644 "$SCRIPT_DIR/scripts/server-telegram-update.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/server-telegram-report.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-telegram-bot.conf.example" "$SHARE/"

# --- Hỏi [Y/n] hoặc [y/N]; trả về 0 = có / bật, 1 = không / tắt
_prompt_yes() {
  local msg=$1
  local def=$2
  local a
  if [[ "$def" == "y" ]]; then
    read -r -p "$msg [Y/n]: " a </dev/tty || true
    [[ -z "${a:-}" ]] && return 0
    [[ "$a" =~ ^[Yy] ]] && return 0
    return 1
  else
    read -r -p "$msg [y/N]: " a </dev/tty || true
    [[ -z "${a:-}" ]] && return 1
    [[ "$a" =~ ^[Yy] ]] && return 0
    return 1
  fi
}

interactive_configure() {
  if [[ -n "$DESTDIR" ]]; then
    echo "" >&2
    echo "→ Đang dùng DESTDIR: bỏ qua cấu hình tương tác và không ghi /etc." >&2
    return 0
  fi
  if [[ "${SKIP_INSTALL_PROMPTS:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]] || [[ ! -c /dev/tty ]]; then
    echo "" >&2
    echo "→ Không phải terminal tương tác: bỏ qua hỏi tuỳ chọn (đặt SKIP_INSTALL_PROMPTS=1 để ẩn gợi ý)." >&2
    return 0
  fi

  local profile="${LTM_INSTALL_PROFILE:-}"
  if [[ -z "$profile" ]]; then
    echo ""
    echo "════════ Chọn cách cấu hình ════════"
    echo "  1) Cơ bản  — chỉ vài câu; phần còn lại dùng mặc định (như gợi ý [Y/n] chuẩn)"
    echo "  2) Chuyên sâu — hỏi đầy đủ từng tuỳ chọn"
    local pc
    read -r -p "Nhập 1 hoặc 2 [Enter = 1]: " pc </dev/tty || true
    case "${pc:-1}" in
      2) profile=advanced ;;
      *) profile=basic ;;
    esac
  elif [[ "$profile" != "basic" && "$profile" != "advanced" ]]; then
    echo "LTM_INSTALL_PROFILE không hợp lệ (chỉ basic|advanced), dùng basic." >&2
    profile=basic
  fi

  # Mặc định khi không hỏi (chế độ cơ bản) — trùng gợi ý Enter trong script cũ
  local U_SEND=1 U_FW=1 U_REBOOT=0
  local R_INSTALL_DEPS=1 R_DOCKER=1
  local R_BOOT=1 R_SYSTEMD=1 R_DF=1 R_INODE=1 R_MEM=1 R_SS=1 R_IP=1
  local R_DISKA=1 R_ZOMB=1 R_TLS=0 R_JRNL=0
  local R_DOCKER_DF=1 R_DOCKER_HL=1 R_DOCKER_COMPOSE=0 R_DOCKER_NET=0

  echo ""
  echo "════════ Tuỳ chọn tính năng (Enter = chữ in HOA trong [Y/n]) ════════"
  if [[ "$profile" == "advanced" ]]; then
    echo " (Chế độ chuyên sâu)"
  else
    echo " (Chế độ cơ bản — chỉ hỏi các mục chính)"
  fi
  echo ""

  echo "── server-telegram-update (ltm-update) ──"
  _prompt_yes "  Gửi file log chi tiết kèm tin Telegram?" y && U_SEND=1 || U_SEND=0
  _prompt_yes "  Chạy cập nhật firmware (fwupdmgr)? Tắt nếu máy ảo / không cần." y && U_FW=1 || U_FW=0
  _prompt_yes "  Tự reboot khi hệ thống báo cần (/var/run/reboot-required)? NGUY HIỂM." n && U_REBOOT=1 || U_REBOOT=0

  echo ""
  echo "── server-telegram-report (ltm-report) ──"
  _prompt_yes "  Tự cài gói thiếu (curl, iproute/ss…)?" y && R_INSTALL_DEPS=1 || R_INSTALL_DEPS=0
  _prompt_yes "  Báo cáo Docker (containers, stats)? Tắt nếu máy không dùng Docker." y && R_DOCKER=1 || R_DOCKER=0

  if [[ "$profile" == "advanced" ]]; then
    echo ""
    echo "── Các khối theo dõi bổ sung (sau Top CPU) ──"
    _prompt_yes "  Thời điểm boot gần nhất (who -b)?" y && R_BOOT=1 || R_BOOT=0
    _prompt_yes "  systemd — unit lỗi (systemctl --failed)?" y && R_SYSTEMD=1 || R_SYSTEMD=0
    _prompt_yes "  Tất cả filesystem (df -hT)?" y && R_DF=1 || R_DF=0
    _prompt_yes "  Inode theo phân vùng (df -ih)?" y && R_INODE=1 || R_INODE=0
    _prompt_yes "  Tóm tắt RAM từ /proc/meminfo?" y && R_MEM=1 || R_MEM=0
    _prompt_yes "  Cổng đang lắng nghe (ss -tuln)?" y && R_SS=1 || R_SS=0
    _prompt_yes "  Địa chỉ IP giao diện (ip -br a)?" y && R_IP=1 || R_IP=0

    echo ""
    echo "── Theo dõi nâng cao (ltm-report) ──"
    _prompt_yes "  Cảnh báo ổ đầy (≥ 90% trên thiết bị /dev)?" y && R_DISKA=1 || R_DISKA=0
    _prompt_yes "  Đếm tiến trình zombie (defunct)?" y && R_ZOMB=1 || R_ZOMB=0
    _prompt_yes "  Kiểm tra chứng chỉ TLS (Let's Encrypt / openssl)?" n && R_TLS=1 || R_TLS=0
    _prompt_yes "  Gửi log lỗi gần đây (journalctl err…alert)?" n && R_JRNL=1 || R_JRNL=0
  fi

  if [[ "$R_DOCKER" != "1" ]]; then
    R_DOCKER_DF=0 R_DOCKER_HL=0 R_DOCKER_COMPOSE=0 R_DOCKER_NET=0
  elif [[ "$profile" == "advanced" ]]; then
    echo ""
    echo "── Docker / container (khi báo cáo Docker bật) ──"
    _prompt_yes "  Gửi 'docker system df' (dung lượng images/containers)?" y && R_DOCKER_DF=1 || R_DOCKER_DF=0
    _prompt_yes "  Liệt kê container unhealthy (healthcheck)?" y && R_DOCKER_HL=1 || R_DOCKER_HL=0
    _prompt_yes "  Chạy 'docker compose ls -a' (Compose v2)?" n && R_DOCKER_COMPOSE=1 || R_DOCKER_COMPOSE=0
    _prompt_yes "  Chạy 'docker network ls' (bridge/host/…)?" n && R_DOCKER_NET=1 || R_DOCKER_NET=0
  fi

  echo ""
  if ! _prompt_yes "Ghi các tuỳ chọn trên vào /etc/*.conf?" y; then
    echo "Đã bỏ qua ghi file. Mẫu vẫn ở: $SHARE/"
    return 0
  fi

  local TG_TOKEN="YOUR_BOT_TOKEN_HERE" TG_CHAT="YOUR_CHAT_ID_HERE"
  echo ""
  if _prompt_yes "Nhập Bot Token và Chat ID ngay? (nếu Không → để placeholder, sửa sau bằng nano)" n; then
    read -rs -p "  TELEGRAM_BOT_TOKEN (ẩn khi gõ): " TG_TOKEN </dev/tty || true
    echo "" >&2
    read -rp "  TELEGRAM_CHAT_ID: " TG_CHAT </dev/tty || true
    TG_TOKEN="${TG_TOKEN//$'\r'/}"
    TG_CHAT="${TG_CHAT//$'\r'/}"
    [[ -z "$TG_TOKEN" ]] && TG_TOKEN="YOUR_BOT_TOKEN_HERE"
    [[ -z "$TG_CHAT" ]] && TG_CHAT="YOUR_CHAT_ID_HERE"
  fi

  local write_update=1 write_report=1
  if [[ -f /etc/server-telegram-update.conf ]]; then
    if ! _prompt_yes "  Ghi đè /etc/server-telegram-update.conf đã tồn tại?" n; then
      write_update=0
    fi
  fi
  if [[ -f /etc/server-telegram-report.conf ]]; then
    if ! _prompt_yes "  Ghi đè /etc/server-telegram-report.conf đã tồn tại?" n; then
      write_report=0
    fi
  fi

  install -d -m 755 /etc

  if [[ "$write_update" -eq 1 ]]; then
    {
      echo "# Sinh bởi install.sh — sudo chmod 600 /etc/server-telegram-update.conf"
      printf 'TELEGRAM_BOT_TOKEN=%q\n' "$TG_TOKEN"
      printf 'TELEGRAM_CHAT_ID=%q\n' "$TG_CHAT"
      echo "SEND_LOG_AS_DOCUMENT=$U_SEND"
      echo "REBOOT_IF_REQUIRED=$U_REBOOT"
      echo "RUN_FWUPD=$U_FW"
    } >/etc/server-telegram-update.conf
    chmod 600 /etc/server-telegram-update.conf
    echo "Đã tạo /etc/server-telegram-update.conf"
  fi

  if [[ "$write_report" -eq 1 ]]; then
    {
      echo "# Sinh bởi install.sh — sudo chmod 600 /etc/server-telegram-report.conf"
      printf 'TELEGRAM_BOT_TOKEN=%q\n' "$TG_TOKEN"
      printf 'TELEGRAM_CHAT_ID=%q\n' "$TG_CHAT"
      echo 'TZ="Asia/Ho_Chi_Minh"'
      echo "CURL_TIMEOUT=60"
      echo "INSTALL_MISSING_DEPS=$R_INSTALL_DEPS"
      echo "MONITOR_LAST_BOOT=$R_BOOT"
      echo "MONITOR_SYSTEMD_FAILED=$R_SYSTEMD"
      echo "MONITOR_DF_ALL=$R_DF"
      echo "MONITOR_INODES=$R_INODE"
      echo "MONITOR_MEMINFO=$R_MEM"
      echo "MONITOR_LISTEN_PORTS=$R_SS"
      echo "MONITOR_IP_BRIEF=$R_IP"
      echo "MONITOR_DOCKER=$R_DOCKER"
      echo "MONITOR_DOCKER_SYSTEM_DF=$R_DOCKER_DF"
      echo "MONITOR_DOCKER_HEALTH=$R_DOCKER_HL"
      echo "MONITOR_DOCKER_COMPOSE=$R_DOCKER_COMPOSE"
      echo "MONITOR_DOCKER_NETWORKS=$R_DOCKER_NET"
      echo "MONITOR_DISK_ALERT=$R_DISKA"
      echo "DISK_ALERT_PERCENT=90"
      echo "MONITOR_ZOMBIES=$R_ZOMB"
      echo "MONITOR_TLS_CERTS=$R_TLS"
      echo "CERT_WARN_DAYS=30"
      echo "MONITOR_JOURNAL_ERR=$R_JRNL"
    } >/etc/server-telegram-report.conf
    chmod 600 /etc/server-telegram-report.conf
    echo "Đã tạo /etc/server-telegram-report.conf"
  fi

  echo ""
  if [[ "$TG_TOKEN" =~ ^YOUR_ ]] || [[ "$TG_CHAT" =~ ^YOUR_ ]]; then
    echo "Chưa nhập token/chat thật — chỉnh: sudo nano /etc/server-telegram-update.conf"
    echo "                                      sudo nano /etc/server-telegram-report.conf"
  else
    echo "Đã ghi token/chat vào 2 file /etc — kiểm tra lại quyền: chmod 600 /etc/server-telegram-*.conf"
  fi
}

_maybe_cron_schedule() {
  [[ -n "${DESTDIR:-}" ]] && return 0
  if [[ "${SKIP_INSTALL_PROMPTS:-0}" == "1" ]]; then
    case "${LTM_INSTALL_CRON:-}" in
    default | defaults | 1 | yes | y | Y)
      if [[ -x "$BIN/ltm-schedule" ]]; then
        "$BIN/ltm-schedule" defaults || true
      fi
      ;;
    esac
    return 0
  fi
  if [[ ! -t 0 ]] || [[ ! -c /dev/tty ]]; then
    return 0
  fi
  if ! [[ -x "$BIN/ltm-schedule" ]]; then
    return 0
  fi
  echo ""
  if _prompt_yes "Đặt lịch cron: báo cáo mỗi ~6 giờ, chạy cập nhật Chủ Nhật 03:00? (đổi sau: sudo ltm-schedule)" y; then
    "$BIN/ltm-schedule" defaults </dev/null || true
  fi
}

interactive_configure
_maybe_cron_schedule

cat <<EOF
Đã cài:
  $BIN/server-telegram-update   (ltm-update)
  $BIN/server-telegram-report    (ltm-report)
  $BIN/ltm-bot                 — bot lệnh Telegram (cần jq, xem README)
  $BIN/ltm-schedule           — ghi lịch cron báo/cập nhật

Mẫu tham chiếu (nếu không dùng file đã tạo):
  $SHARE/server-telegram-update.conf.example
  $SHARE/server-telegram-report.conf.example
  $SHARE/ltm-telegram-bot.conf.example

Chạy:
  sudo server-telegram-update   hoặc   sudo ltm-update
  sudo server-telegram-report  hoặc   sudo ltm-report
  sudo ltm-bot                  — lệnh từ Telegram (/report, /help, …)
  sudo ltm-schedule             — hoặc: sudo ltm-schedule defaults

Sau khi git pull bản mới:  SKIP_INSTALL_PROMPTS=1 sudo bash install.sh
  (ghi đè lệnh + mẫu share, giữ /etc; systemd: systemctl restart ltm-bot nếu có)

Tuỳ chọn môi trường:
  SKIP_INSTALL_PROMPTS=1        — không hỏi, chỉ cài binary (cron: có thể đặt LTM_INSTALL_CRON=default)
  LTM_INSTALL_CRON=default      — chỉ có nghĩa khi kèm SKIP_INSTALL_PROMPTS=1: ghi cron mặc định luôn
  LTM_INSTALL_PROFILE=basic     — cấu hình tương tác ngắn (bỏ qua menu 1/2)
  LTM_INSTALL_PROFILE=advanced — hỏi đầy đủ như chọn "2" trên menu
EOF
