#!/usr/bin/env bash
# Cai vao PREFIX/bin. Symlink: ltm-update, ltm-report
#
#   sudo bash install.sh
#
# Tu dong bo qua hoi tuy chon: SKIP_INSTALL_PROMPTS=1 hoac khong co TTY (cron/pipe)
# Kieu cau hinh (chi khi co TTY): LTM_INSTALL_PROFILE=basic|advanced
# Lich cron sau cai: LTM_INSTALL_CRON=default (bao 15 phut + cap nhat moi ngay 00:00)
# Ngon ngu tin Telegram: LTM_INSTALL_REPORT_LANG=vi|en (vi = co dau; menu cai dat khong dau)
# Chi tao file trong DESTDIR: khong ghi /etc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
BIN="${DESTDIR}${PREFIX}/bin"
SHARE="${DESTDIR}${PREFIX}/share/linux-telegram-monitor"

if [[ "$(id -u)" -ne 0 ]] && [[ -z "$DESTDIR" ]]; then
  echo "Loi: Can chay voi sudo de ghi ${PREFIX}/bin (hoac chi DESTDIR)." >&2
  echo "Error: Run with sudo to write ${PREFIX}/bin (or use DESTDIR only)." >&2
  exit 1
fi

install -d -m 755 "$BIN"
install -d -m 755 "$SHARE"

INSTALL_LANG="${LTM_INSTALL_REPORT_LANG:-}"
select_install_lang() {
  if [[ -z "$INSTALL_LANG" ]]; then
    INSTALL_LANG="vi"
  fi
  case "$INSTALL_LANG" in
    vi|vn|VI|VN) INSTALL_LANG="vi" ;;
    en|EN) INSTALL_LANG="en" ;;
    *)
      echo "Canh bao: LTM_INSTALL_REPORT_LANG khong hop le ($INSTALL_LANG), dung vi." >&2
      echo "Warning: Invalid LTM_INSTALL_REPORT_LANG ($INSTALL_LANG), fallback to vi." >&2
      INSTALL_LANG="vi"
      ;;
  esac

  if [[ "${SKIP_INSTALL_PROMPTS:-0}" != "1" ]] && [[ -t 0 ]] && [[ -c /dev/tty ]] && [[ -z "${LTM_INSTALL_REPORT_LANG:-}" ]]; then
    echo ""
    echo "======== Chon ngon ngu cai dat / installation language ========"
    echo "  1) Tieng Viet (ltm-update + ltm-report, tin Telegram co dau)"
    echo "  2) English (ltm-update + ltm-report in English)"
    local lc
    read -r -p "Nhap 1 hoac 2 [Enter = 1]: " lc </dev/tty || true
    case "${lc:-1}" in
      2) INSTALL_LANG="en" ;;
      *) INSTALL_LANG="vi" ;;
    esac
  fi
}

select_install_lang

if [[ "$INSTALL_LANG" == "en" ]]; then
  install -m 755 "$SCRIPT_DIR/scripts/server-telegram-update-en.sh" "$BIN/server-telegram-update"
  install -m 755 "$SCRIPT_DIR/scripts/server-telegram-report-en.sh" "$BIN/server-telegram-report"
  install -m 755 "$SCRIPT_DIR/scripts/ltm-telegram-bot-en.sh" "$BIN/ltm-bot"
  install -m 755 "$SCRIPT_DIR/scripts/ltm-schedule-en.sh" "$BIN/ltm-schedule"
else
  install -m 755 "$SCRIPT_DIR/scripts/server-telegram-update.sh" "$BIN/server-telegram-update"
  install -m 755 "$SCRIPT_DIR/scripts/server-telegram-report.sh" "$BIN/server-telegram-report"
  install -m 755 "$SCRIPT_DIR/scripts/ltm-telegram-bot.sh" "$BIN/ltm-bot"
  install -m 755 "$SCRIPT_DIR/scripts/ltm-schedule.sh" "$BIN/ltm-schedule"
fi

install -m 755 "$SCRIPT_DIR/scripts/ltm-bot-core.sh" "$SHARE/"
install -m 755 "$SCRIPT_DIR/scripts/ltm-watch.sh" "$BIN/ltm-watch"
install -m 755 "$SCRIPT_DIR/scripts/ltm-bot-sync-commands.sh" "$BIN/ltm-bot-sync-commands"

ln -sf server-telegram-update "$BIN/ltm-update"
ln -sf server-telegram-report "$BIN/ltm-report"
rm -f -- \
  "$BIN/ltm-report-en" \
  "$BIN/server-telegram-report-en" \
  "$BIN/server-telegram-update-en" \
  "$BIN/ltm-telegram-bot-en" \
  "$BIN/ltm-schedule-en" \
  2>/dev/null || true

# Mot so may co sudo secure_path khong chua /usr/local/bin.
# Tao symlink tuong thich o /usr/bin (neu cai that, khong dung DESTDIR) de goi duoc qua sudo.
install_compat_links() {
  [[ -n "$DESTDIR" ]] && return 0
  [[ "$PREFIX" != "/usr/local" ]] && return 0
  [[ -d /usr/bin ]] || return 0

  ln -sfn "/usr/local/bin/ltm-update" /usr/bin/ltm-update 2>/dev/null || true
  ln -sfn "/usr/local/bin/ltm-report" /usr/bin/ltm-report 2>/dev/null || true
  ln -sfn "/usr/local/bin/ltm-schedule" /usr/bin/ltm-schedule 2>/dev/null || true
  ln -sfn "/usr/local/bin/ltm-bot" /usr/bin/ltm-bot 2>/dev/null || true
  ln -sfn "/usr/local/bin/ltm-watch" /usr/bin/ltm-watch 2>/dev/null || true
  rm -f -- /usr/bin/ltm-report-en 2>/dev/null || true
}

install -m 644 "$SCRIPT_DIR/scripts/server-telegram-update.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/server-telegram-report.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-telegram-bot.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-watch.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-allowed-services.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-allowed-docker.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-allow-commands.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/ltm-watch.service.example" "$SHARE/"
if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
  install -m 644 "$SCRIPT_DIR/VERSION" "$SHARE/VERSION"
fi

# --- Hoi [Y/n] hoac [y/N]; tra ve 0 = co/bat, 1 = khong/tat
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
    echo "-> Dang dung DESTDIR: bo qua cau hinh tuong tac va khong ghi /etc." >&2
    return 0
  fi
  if [[ "${SKIP_INSTALL_PROMPTS:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]] || [[ ! -c /dev/tty ]]; then
    echo "" >&2
    echo "-> Khong phai terminal tuong tac: bo qua hoi tuy chon (dat SKIP_INSTALL_PROMPTS=1 de an goi y)." >&2
    return 0
  fi

  local profile="${LTM_INSTALL_PROFILE:-}"
  if [[ -z "$profile" ]]; then
    echo ""
    echo "======== Chon cach cau hinh ========"
    echo "  1) Co ban  - chi vai cau; phan con lai dung mac dinh (nhu goi y [Y/n] chuan)"
    echo "  2) Chuyen sau - hoi day du tung tuy chon"
    local pc
    read -r -p "Nhap 1 hoac 2 [Enter = 1]: " pc </dev/tty || true
    case "${pc:-1}" in
      2) profile=advanced ;;
      *) profile=basic ;;
    esac
  elif [[ "$profile" != "basic" && "$profile" != "advanced" ]]; then
    echo "LTM_INSTALL_PROFILE khong hop le (chi basic|advanced), dung basic." >&2
    profile=basic
  fi

  # Mac dinh khi khong hoi (che do co ban) - trung goi y Enter trong script cu
  local U_SEND=1 U_FW=1 U_REBOOT=0
  local R_INSTALL_DEPS=1 R_DOCKER=1
  local R_BOOT=1 R_SYSTEMD=1 R_DF=1 R_INODE=1 R_MEM=1 R_SS=1 R_IP=1
  local R_DISKA=1 R_ZOMB=1 R_TLS=0 R_JRNL=0
  local R_DOCKER_DF=1 R_DOCKER_HL=1 R_DOCKER_COMPOSE=0 R_DOCKER_NET=0
  local B_ALLOW_REPORT=1 B_ALLOW_UPDATE=1 B_ALLOW_ACTION=0

  echo ""
  echo "======== Tuy chon tinh nang (Enter = chu in HOA trong [Y/n]) ========"
  if [[ "$profile" == "advanced" ]]; then
    echo " (Che do chuyen sau)"
  else
    echo " (Che do co ban - chi hoi cac muc chinh)"
  fi
  echo ""

  echo "-- server-telegram-update (ltm-update) --"
  _prompt_yes "  Gui file log chi tiet kem tin Telegram?" y && U_SEND=1 || U_SEND=0
  _prompt_yes "  Chay cap nhat firmware (fwupdmgr)? Tat neu may ao / khong can." y && U_FW=1 || U_FW=0
  _prompt_yes "  Tu reboot khi he thong bao can (/var/run/reboot-required)? NGUY HIEM." n && U_REBOOT=1 || U_REBOOT=0

  echo ""
  echo "-- server-telegram-report (ltm-report) --"
  _prompt_yes "  Tu cai goi thieu (curl, iproute/ss...)?" y && R_INSTALL_DEPS=1 || R_INSTALL_DEPS=0
  _prompt_yes "  Bao cao Docker (container, stats)? Tat neu may khong dung Docker." y && R_DOCKER=1 || R_DOCKER=0

  if [[ "$profile" == "advanced" ]]; then
    echo ""
    echo "-- Cac khoi theo doi bo sung (sau Top CPU) --"
    _prompt_yes "  Thoi diem boot gan nhat (who -b)?" y && R_BOOT=1 || R_BOOT=0
    _prompt_yes "  systemd - unit loi (systemctl --failed)?" y && R_SYSTEMD=1 || R_SYSTEMD=0
    _prompt_yes "  Tat ca filesystem (df -hT)?" y && R_DF=1 || R_DF=0
    _prompt_yes "  Inode theo phan vung (df -ih)?" y && R_INODE=1 || R_INODE=0
    _prompt_yes "  Tom tat RAM tu /proc/meminfo?" y && R_MEM=1 || R_MEM=0
    _prompt_yes "  Cong dang lang nghe (ss -tuln)?" y && R_SS=1 || R_SS=0
    _prompt_yes "  Dia chi IP giao dien (ip -br a)?" y && R_IP=1 || R_IP=0

    echo ""
    echo "-- Theo doi nang cao (ltm-report) --"
    _prompt_yes "  Canh bao o day (>= 90% tren thiet bi /dev)?" y && R_DISKA=1 || R_DISKA=0
    _prompt_yes "  Dem tien trinh zombie (defunct)?" y && R_ZOMB=1 || R_ZOMB=0
    _prompt_yes "  Kiem tra chung chi TLS (Let's Encrypt / openssl)?" n && R_TLS=1 || R_TLS=0
    _prompt_yes "  Gui log loi gan day (journalctl err...alert)?" n && R_JRNL=1 || R_JRNL=0
  fi

  if [[ "$R_DOCKER" != "1" ]]; then
    R_DOCKER_DF=0 R_DOCKER_HL=0 R_DOCKER_COMPOSE=0 R_DOCKER_NET=0
  elif [[ "$profile" == "advanced" ]]; then
    echo ""
    echo "-- Docker / container (khi bao cao Docker bat) --"
    _prompt_yes "  Gui 'docker system df' (dung luong image/container)?" y && R_DOCKER_DF=1 || R_DOCKER_DF=0
    _prompt_yes "  Liet ke container unhealthy (healthcheck)?" y && R_DOCKER_HL=1 || R_DOCKER_HL=0
    _prompt_yes "  Chay 'docker compose ls -a' (Compose v2)?" n && R_DOCKER_COMPOSE=1 || R_DOCKER_COMPOSE=0
    _prompt_yes "  Chay 'docker network ls' (bridge/host/...)?" n && R_DOCKER_NET=1 || R_DOCKER_NET=0
  fi

  echo ""
  echo "-- Telegram bot command control (ltm-bot) --"
  _prompt_yes "  Bat dieu khien lenh tu Telegram (/report, /status)?" y && B_ALLOW_REPORT=1 || B_ALLOW_REPORT=0
  _prompt_yes "  Bat lenh /update tu Telegram? (can than voi quyen root)" y && B_ALLOW_UPDATE=1 || B_ALLOW_UPDATE=0
  _prompt_yes "  Bat hanh dong tu xa (/reboot_now, /service, /docker_restart)? CAN THAN." n && B_ALLOW_ACTION=1 || B_ALLOW_ACTION=0

  echo ""
  if ! _prompt_yes "Ghi cac tuy chon tren vao /etc/*.conf?" y; then
    echo "Da bo qua ghi file. Mau van o: $SHARE/"
    return 0
  fi

  local TG_TOKEN_UPD="YOUR_BOT_TOKEN_HERE" TG_CHAT_UPD="YOUR_CHAT_ID_HERE"
  local TG_TOKEN_REP="YOUR_BOT_TOKEN_HERE" TG_CHAT_REP="YOUR_CHAT_ID_HERE"
  local SAME_TG=1
  echo ""
  if _prompt_yes "Dung cung bot/chat Telegram cho update va report?" y; then
    SAME_TG=1
  else
    SAME_TG=0
  fi

  if _prompt_yes "Nhap Telegram credentials ngay? (neu Khong -> de placeholder, sua sau bang nano)" n; then
    echo "  [update] Bot Token + Chat ID"
    read -rs -p "  TELEGRAM_BOT_TOKEN (update, an khi go): " TG_TOKEN_UPD </dev/tty || true
    echo "" >&2
    read -rp "  TELEGRAM_CHAT_ID (update): " TG_CHAT_UPD </dev/tty || true
    TG_TOKEN_UPD="${TG_TOKEN_UPD//$'\r'/}"
    TG_CHAT_UPD="${TG_CHAT_UPD//$'\r'/}"
    [[ -z "$TG_TOKEN_UPD" ]] && TG_TOKEN_UPD="YOUR_BOT_TOKEN_HERE"
    [[ -z "$TG_CHAT_UPD" ]] && TG_CHAT_UPD="YOUR_CHAT_ID_HERE"

    if [[ "$SAME_TG" -eq 1 ]]; then
      TG_TOKEN_REP="$TG_TOKEN_UPD"
      TG_CHAT_REP="$TG_CHAT_UPD"
    else
      echo ""
      echo "  [report] Bot Token + Chat ID"
      read -rs -p "  TELEGRAM_BOT_TOKEN (report, an khi go): " TG_TOKEN_REP </dev/tty || true
      echo "" >&2
      read -rp "  TELEGRAM_CHAT_ID (report): " TG_CHAT_REP </dev/tty || true
      TG_TOKEN_REP="${TG_TOKEN_REP//$'\r'/}"
      TG_CHAT_REP="${TG_CHAT_REP//$'\r'/}"
      [[ -z "$TG_TOKEN_REP" ]] && TG_TOKEN_REP="YOUR_BOT_TOKEN_HERE"
      [[ -z "$TG_CHAT_REP" ]] && TG_CHAT_REP="YOUR_CHAT_ID_HERE"
    fi
  else
    TG_TOKEN_REP="$TG_TOKEN_UPD"
    TG_CHAT_REP="$TG_CHAT_UPD"
  fi

  local write_update=1 write_report=1 write_bot=1
  if [[ -f /etc/server-telegram-update.conf ]]; then
    if ! _prompt_yes "  Ghi de /etc/server-telegram-update.conf da ton tai?" n; then
      write_update=0
    fi
  fi
  if [[ -f /etc/server-telegram-report.conf ]]; then
    if ! _prompt_yes "  Ghi de /etc/server-telegram-report.conf da ton tai?" n; then
      write_report=0
    fi
  fi
  if [[ -f /etc/ltm-telegram-bot.conf ]]; then
    if ! _prompt_yes "  Ghi de /etc/ltm-telegram-bot.conf da ton tai?" n; then
      write_bot=0
    fi
  fi

  install -d -m 755 /etc

  if [[ "$write_update" -eq 1 ]]; then
    {
      echo "# Sinh boi install.sh - sudo chmod 600 /etc/server-telegram-update.conf"
      printf 'TELEGRAM_BOT_TOKEN=%q\n' "$TG_TOKEN_UPD"
      printf 'TELEGRAM_CHAT_ID=%q\n' "$TG_CHAT_UPD"
      echo "SEND_LOG_AS_DOCUMENT=$U_SEND"
      echo "REBOOT_IF_REQUIRED=$U_REBOOT"
      echo "RUN_FWUPD=$U_FW"
    } >/etc/server-telegram-update.conf
    chmod 600 /etc/server-telegram-update.conf
    echo "Da tao /etc/server-telegram-update.conf"
  fi

  if [[ "$write_report" -eq 1 ]]; then
    {
      echo "# Sinh boi install.sh - sudo chmod 600 /etc/server-telegram-report.conf"
      printf 'TELEGRAM_BOT_TOKEN=%q\n' "$TG_TOKEN_REP"
      printf 'TELEGRAM_CHAT_ID=%q\n' "$TG_CHAT_REP"
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
    echo "Da tao /etc/server-telegram-report.conf"
  fi

  if [[ "$write_bot" -eq 1 ]]; then
    {
      echo "# Sinh boi install.sh - sudo chmod 600 /etc/ltm-telegram-bot.conf"
      printf 'TELEGRAM_BOT_TOKEN=%q\n' "$TG_TOKEN_REP"
      printf 'TELEGRAM_CHAT_ID=%q\n' "$TG_CHAT_REP"
      echo "ALLOW_REMOTE_REPORT=$B_ALLOW_REPORT"
      echo "ALLOW_REMOTE_UPDATE=$B_ALLOW_UPDATE"
      echo "ALLOW_REMOTE_ACTION=$B_ALLOW_ACTION"
      echo '# TELEGRAM_ADMIN_CHAT_ID=""  # de trong = chat dau tien trong TELEGRAM_CHAT_ID'
      echo "PATH_REPORT=\"${BIN}/server-telegram-report\""
      echo "PATH_UPDATE=\"${BIN}/server-telegram-update\""
      echo "SUDO_CMD=\"\""
      echo "POLL_TIMEOUT=25"
      echo "REMOTE_CMD_TIMEOUT=35"
    } >/etc/ltm-telegram-bot.conf
    chmod 600 /etc/ltm-telegram-bot.conf
    echo "Da tao /etc/ltm-telegram-bot.conf"
  fi

  echo ""
  if [[ "$TG_TOKEN_UPD" =~ ^YOUR_ ]] || [[ "$TG_CHAT_UPD" =~ ^YOUR_ ]] || [[ "$TG_TOKEN_REP" =~ ^YOUR_ ]] || [[ "$TG_CHAT_REP" =~ ^YOUR_ ]]; then
    echo "Chua nhap token/chat that - chinh: sudo nano /etc/server-telegram-update.conf"
    echo "                                      sudo nano /etc/server-telegram-report.conf"
    echo "                                      sudo nano /etc/ltm-telegram-bot.conf"
  else
    echo "Da ghi token/chat vao cac file /etc - kiem tra lai quyen: chmod 600 /etc/server-telegram-*.conf /etc/ltm-telegram-bot.conf"
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
  if _prompt_yes "Thiet lap lich cron ngay bay gio?" y; then
    local rep="15m" up="daily" uh="0" ch
    echo "  Lich bao cao (ltm-report):"
    echo "    0) off   1) 15m(default)  2) 30m  3) 1h  4) 2h  5) 4h  6) 6h  7) 12h"
    read -r -p "  Chon [0-7], Enter = 1: " ch </dev/tty || true
    case "${ch:-1}" in
      0) rep="off" ;;
      1) rep="15m" ;;
      2) rep="30m" ;;
      3) rep="1h" ;;
      4) rep="2h" ;;
      5) rep="4h" ;;
      6) rep="6h" ;;
      7) rep="12h" ;;
      *) rep="15m" ;;
    esac

    echo "  Lich cap nhat (ltm-update):"
    echo "    0) off   1) daily (default, 00:00)   2) weekly (Sunday)"
    read -r -p "  Chon [0-2], Enter = 1: " ch </dev/tty || true
    case "${ch:-1}" in
      0) up="off" ;;
      2)
        up="weekly"
        read -r -p "  Gio chay CN (0-23), Enter = 0: " uh </dev/tty || true
        uh="${uh:-0}"
        ;;
      1|*)
        up="daily"
        read -r -p "  Gio chay moi ngay (0-23), Enter = 0: " uh </dev/tty || true
        uh="${uh:-0}"
        ;;
    esac
    "$BIN/ltm-schedule" apply --report "$rep" --update "$up" --update-hour "$uh" </dev/null || true
  fi
}

interactive_configure
_maybe_cron_schedule
install_compat_links

cat <<EOF
Ngon ngu bao cao Telegram: ${INSTALL_LANG} (vi = co dau tren Telegram)

Da cai:
  $BIN/server-telegram-update   (ltm-update)
  $BIN/server-telegram-report   (ltm-report)
  $BIN/ltm-bot                 - bot lenh Telegram (can jq, xem README)
  $BIN/ltm-schedule           - ghi lich cron bao/cap nhat
  $BIN/ltm-watch              - canh bao theo nguong (xem ltm-watch.conf.example)

Mau tham chieu (neu khong dung file da tao):
  $SHARE/server-telegram-update.conf.example
  $SHARE/server-telegram-report.conf.example
  $SHARE/ltm-telegram-bot.conf.example
  $SHARE/ltm-watch.conf.example
  $SHARE/ltm-allowed-*.conf.example  # whitelist hanh dong bot

Chay:
  sudo server-telegram-update   hoac   sudo ltm-update
  sudo server-telegram-report  hoac   sudo ltm-report
  sudo ltm-bot                  - lenh tu Telegram (/report, /help, ...)
  sudo ltm-schedule             - hoac: sudo ltm-schedule defaults
  sudo ltm-watch                - mot lan; systemd: ltm-watch --loop

Sau khi git pull ban moi:  SKIP_INSTALL_PROMPTS=1 sudo bash install.sh
  (ghi de lenh + mau share, giu /etc; systemd: systemctl restart ltm-bot neu co)

Tuy chon moi truong:
  SKIP_INSTALL_PROMPTS=1        - khong hoi, chi cai binary (cron: co the dat LTM_INSTALL_CRON=default)
  LTM_INSTALL_CRON=default      - chi co nghia khi kem SKIP_INSTALL_PROMPTS=1: ghi mac dinh report=15m, update=daily 00:00
  LTM_INSTALL_REPORT_LANG=vi|en - vi/en cho tin Telegram (menu cai dat luon khong dau)
  LTM_INSTALL_PROFILE=basic     - cau hinh tuong tac ngan (bo qua menu 1/2)
  LTM_INSTALL_PROFILE=advanced  - hoi day du nhu chon "2" tren menu
EOF
