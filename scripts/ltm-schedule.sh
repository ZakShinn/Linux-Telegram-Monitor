#!/usr/bin/env bash
# linux-telegram-monitor — ghi /etc/cron.d/linux-telegram-monitor cho ltm-report / ltm-update
#
#   sudo ltm-schedule                 # wizard tùy chọn giờ
#   sudo ltm-schedule defaults        # báo 15 phút/lần + cập nhật hằng ngày 00:00
#   sudo ltm-schedule apply --report 15m --update daily [--update-hour 0]
#   sudo ltm-schedule apply --report-off --update off
#   sudo ltm-schedule show
#   sudo ltm-schedule remove
#
set -euo pipefail

CROND="/etc/cron.d/linux-telegram-monitor"

resolve_report_bin() {
  command -v ltm-report 2>/dev/null || echo "${PREFIX:-/usr/local}/bin/ltm-report"
}

resolve_update_bin() {
  command -v ltm-update 2>/dev/null || echo "${PREFIX:-/usr/local}/bin/ltm-update"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Chạy với sudo (cần ghi $CROND)." >&2
    exit 1
  fi
}

# off | 15m | 30m | 1h | 2h | 3h | 4h | 6h | 8h | 12h | daily:N
report_to_cron() {
  local rep=${1,,}
  case "$rep" in
  off | none | '') printf '%s' "" ;;
  15m) printf '%s' '*/15 * * * *' ;;
  30m) printf '%s' '*/30 * * * *' ;;
  1h) printf '%s' '0 * * * *' ;;
  2h) printf '%s' '0 */2 * * *' ;;
  3h) printf '%s' '0 */3 * * *' ;;
  4h) printf '%s' '0 */4 * * *' ;;
  6h) printf '%s' '0 */6 * * *' ;;
  8h) printf '%s' '0 */8 * * *' ;;
  12h) printf '%s' '0 */12 * * *' ;;
  daily:*)
    local hh
    hh="${rep#daily:}"
    hh="${hh//[^0-9]/}"
    [[ -z "$hh" ]] && hh=8
    [[ "$hh" -gt 23 ]] && hh=8
    printf '0 %s * * *' "$hh"
    ;;
  *)
    echo "--report chỉ nhận: off | 30m | 1h | … | 12h | daily:H ($rep)." >&2
    exit 1
    ;;
  esac
}

# weekly:hod — CN=0; daily:hod
update_to_cron() {
  local mode=${1,,} hod=$2
  hod="${hod//[^0-9]/}"
  [[ -z "$hod" ]] && hod=3
  [[ "$hod" -gt 23 ]] && hod=3
  case "$mode" in
  off | none | '') printf '%s' "" ;;
  weekly) printf '0 %s * * 0' "$hod" ;;
  daily) printf '0 %s * * *' "$hod" ;;
  *)
    echo "--update chỉ nhận: off | weekly | daily." >&2
    exit 1
    ;;
  esac
}

write_crond() {
  local rex=$1 uex=$2 rb ub tf
  rb="$(resolve_report_bin)"
  ub="$(resolve_update_bin)"

  if [[ -z "${rex//[:space:]/}" ]] && [[ -z "${uex//[:space:]/}" ]]; then
    rm -f -- "$CROND"
    echo "Không còn tác vụ — đã xoá $CROND (nếu có)."
    return 0
  fi

  tf="$(mktemp "${TMPDIR:-/tmp}/ltm-cron.XXXXXX")"

  {
    cat <<-'CRONEOF'
# linux-telegram-monitor — đặt bằng: sudo ltm-schedule ...
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
SHELL=/bin/bash

CRONEOF
    if [[ -n "${rex//[:space:]/}" ]]; then
      printf '%s root %s >> /var/log/ltm-report.cron.log 2>&1\n' "$rex" "$rb"
    fi
    if [[ -n "${uex//[:space:]/}" ]]; then
      printf '%s root %s >> /var/log/ltm-update.cron.log 2>&1\n' "$uex" "$ub"
    fi
  } >"$tf"
  printf '\n' >>"$tf"
  chmod 0644 "$tf"
  mv -f -- "$tf" "$CROND"
  echo "Đã ghi $CROND"
}

wizard() {
  require_root
  local rex="" uex="" ch hh rep up_rep opt

  echo "══ Báo cáo (ltm-report) ══"
  echo "  0 — Tắt"
  echo "  1 — 15 phút (mặc định)"
  echo "  2 — 30 phút"
  echo "  3 — Mỗi giờ"
  echo "  4 — Mỗi 6 giờ"
  echo "  5 — Mỗi 12 giờ"
  echo "  6 — Mỗi ngày một lần"
  read -r -p "Chọn [0–6], Enter = 1: " ch </dev/tty || true
  ch="${ch:-1}"

  rep=15m
  case "${ch:-1}" in
  0) rep="off" ;;
  1) rep="15m" ;;
  2) rep="30m" ;;
  3) rep="1h" ;;
  4) rep="6h" ;;
  5) rep="12h" ;;
  6)
    read -r -p "Giờ (0–23), Enter = 8: " hh </dev/tty || true
    hh="${hh:-8}"
    hh="${hh//[^0-9]/}"
    [[ -z "$hh" ]] && hh=8
    [[ "$hh" -gt 23 ]] && hh=8
    rep="daily:${hh}"
    ;;
  *) rep="15m" ;;
  esac

  rex=$(report_to_cron "$rep")

  echo ""
  echo "══ Cập nhật gói (ltm-update) ══"
  echo "  0 — Tắt (chạy tay khi cần)"
  echo "  1 — Mỗi ngày (mặc định)"
  echo "  2 — Tuần: Chủ Nhật"
  read -r -p "Chọn [0–2], Enter = 1: " ch </dev/tty || true
  ch="${ch:-1}"

  uex=""
  case "${ch:-1}" in
  0) uex="" ;;
  1)
    read -r -p "Giờ mỗi ngày (0–23), Enter = 0: " opt </dev/tty || true
    opt="${opt:-0}"
    uex="$(update_to_cron daily "${opt}")"
    ;;
  2)
    read -r -p "Giờ CN (0–23), Enter = 3: " opt </dev/tty || true
    opt="${opt:-3}"
    uex="$(update_to_cron weekly "${opt}")"
    ;;
  *)
    read -r -p "Giờ mỗi ngày (0–23), Enter = 4: " opt </dev/tty || true
    opt="${opt:-0}"
    uex="$(update_to_cron daily "${opt}")"
    ;;
  esac

  write_crond "$rex" "$uex"
  echo "Xem: sudo ltm-schedule show — Xóa lịch: sudo ltm-schedule remove"
}

cmd_defaults() {
  require_root
  write_crond "$(report_to_cron 15m)" "$(update_to_cron daily 0)"
}

cmd_show() {
  if [[ ! -f "$CROND" ]]; then
    echo "(chưa có lịch) Chạy: sudo ltm-schedule hoặc sudo ltm-schedule defaults"
    return 0
  fi
  cat "$CROND"
}

cmd_remove() {
  require_root
  rm -f -- "$CROND"
  echo "Đã xoá $CROND."
}

usage() {
  echo "sudo ltm-schedule              Wizard chọn kiểu gửi báo/cập nhật"
  echo "sudo ltm-schedule defaults     Gợi ý: báo 15 phút, cập nhật mỗi ngày 00:00"
  echo "sudo ltm-schedule apply --report 15m|6h|30m|12h|off|daily:N --update weekly|daily|off [--update-hour H]"
  echo "sudo ltm-schedule show | remove"
}

cmd_apply() {
  require_root
  local rep=15m up=daily uh=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --report)
      [[ $# -lt 2 ]] && {
        echo "Thiếu giá trị sau --report" >&2
        exit 1
      }
      rep=$2
      shift 2
      ;;
    --report-off)
      rep=off
      shift
      ;;
    --update)
      [[ $# -lt 2 ]] && {
        echo "Thiếu giá trị sau --update" >&2
        exit 1
      }
      up=$2
      shift 2
      ;;
    --update-off)
      up=off
      shift
      ;;
    --update-hour | --hour)
      [[ $# -lt 2 ]] && {
        echo "Thiếu giá trị sau --update-hour" >&2
        exit 1
      }
      uh=$2
      shift 2
      ;;
    *)
      echo "Không nhận: $1 — sudo ltm-schedule help" >&2
      exit 1
      ;;
    esac
  done

  rx=$(report_to_cron "${rep,,}")
  case "${up,,}" in
  off | none | '') ux="" ;;
  weekly) ux="$(update_to_cron weekly "$uh")" ;;
  daily) ux="$(update_to_cron daily "$uh")" ;;
  *)
    echo "--update chỉ: off | weekly | daily ($up)." >&2
    exit 1
    ;;
  esac
  write_crond "$rx" "$ux"
}

main() {
  case "${1:-}" in
  '' | wizard)
    wizard
    ;;
  defaults | default)
    cmd_defaults
    ;;
  apply)
    shift
    cmd_apply "$@"
    ;;
  show | cat | status)
    cmd_show
    ;;
  rm | delete | disable | remove)
    cmd_remove
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    echo "Lệnh không rõ: ${1:-}. Gõ: sudo ltm-schedule help" >&2
    exit 1
    ;;
  esac
}

main "$@"
