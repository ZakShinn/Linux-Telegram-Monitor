#!/usr/bin/env bash
# linux-telegram-monitor - ghi /etc/cron.d/linux-telegram-monitor cho ltm-report / ltm-update
#
#   sudo ltm-schedule                 # wizard tuy chon gio
#   sudo ltm-schedule defaults        # bao 15 phut/lan + cap nhat hang ngay 00:00
#   sudo ltm-schedule apply --report 15m --update daily [--update-hour 0]
#   sudo ltm-schedule apply --self-update weekly [--self-update-hour 4]
#   sudo ltm-schedule apply --report-off --update off --self-update off
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

resolve_self_update_bin() {
  command -v ltm-self-update 2>/dev/null || echo "${PREFIX:-/usr/local}/bin/ltm-self-update"
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Chay voi sudo (can ghi $CROND)." >&2
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
    echo "--report chi nhan: off | 15m | 30m | 1h | ... | 12h | daily:H ($rep)." >&2
    exit 1
    ;;
  esac
}

# weekly:hod - CN=0; daily:hod
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
    echo "--update chi nhan: off | weekly | daily." >&2
    exit 1
    ;;
  esac
}

# giong update_to_cron — cap nhat script LTM tu git
self_update_to_cron() {
  local mode=${1,,} hod=$2
  hod="${hod//[^0-9]/}"
  [[ -z "$hod" ]] && hod=4
  [[ "$hod" -gt 23 ]] && hod=4
  case "$mode" in
  off | none | '') printf '%s' "" ;;
  weekly) printf '0 %s * * 0' "$hod" ;;
  daily) printf '0 %s * * *' "$hod" ;;
  *)
    echo "--self-update chi nhan: off | weekly | daily." >&2
    exit 1
    ;;
  esac
}

write_crond() {
  local rex=$1 uex=$2 sex=$3 rb ub sb tf
  rb="$(resolve_report_bin)"
  ub="$(resolve_update_bin)"
  sb="$(resolve_self_update_bin)"

  if [[ -z "${rex//[:space:]/}" ]] && [[ -z "${uex//[:space:]/}" ]] && [[ -z "${sex//[:space:]/}" ]]; then
    rm -f -- "$CROND"
    echo "Khong con tac vu - da xoa $CROND (neu co)."
    return 0
  fi

  tf="$(mktemp "${TMPDIR:-/tmp}/ltm-cron.XXXXXX")"

  {
    cat <<-'CRONEOF'
# linux-telegram-monitor - dat bang: sudo ltm-schedule ...
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
SHELL=/bin/bash

CRONEOF
    if [[ -n "${rex//[:space:]/}" ]]; then
      printf '%s root %s >> /var/log/ltm-report.cron.log 2>&1\n' "$rex" "$rb"
    fi
    if [[ -n "${uex//[:space:]/}" ]]; then
      printf '%s root %s >> /var/log/ltm-update.cron.log 2>&1\n' "$uex" "$ub"
    fi
    if [[ -n "${sex//[:space:]/}" ]]; then
      printf '%s root %s >> /var/log/ltm-self-update.log 2>&1\n' "$sex" "$sb"
    fi
  } >"$tf"
  printf '\n' >>"$tf"
  chmod 0644 "$tf"
  mv -f -- "$tf" "$CROND"
  echo "Da ghi $CROND"
}

wizard() {
  require_root
  local rex="" uex="" ch hh rep up_rep opt

  echo "== Bao cao (ltm-report) =="
  echo "  0 - Tat"
  echo "  1 - 15 phut (mac dinh)"
  echo "  2 - 30 phut"
  echo "  3 - Moi gio"
  echo "  4 - Moi 6 gio"
  echo "  5 - Moi 12 gio"
  echo "  6 - Moi ngay mot lan"
  read -r -p "Chon [0-6], Enter = 1: " ch </dev/tty || true
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
    read -r -p "Gio (0-23), Enter = 8: " hh </dev/tty || true
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
  echo "== Cap nhat goi (ltm-update) =="
  echo "  0 - Tat (chay tay khi can)"
  echo "  1 - Moi ngay (mac dinh)"
  echo "  2 - Tuan: Chu Nhat"
  read -r -p "Chon [0-2], Enter = 1: " ch </dev/tty || true
  ch="${ch:-1}"

  uex=""
  case "${ch:-1}" in
  0) uex="" ;;
  1)
    read -r -p "Gio moi ngay (0-23), Enter = 0: " opt </dev/tty || true
    opt="${opt:-0}"
    uex="$(update_to_cron daily "${opt}")"
    ;;
  2)
    read -r -p "Gio CN (0-23), Enter = 3: " opt </dev/tty || true
    opt="${opt:-3}"
    uex="$(update_to_cron weekly "${opt}")"
    ;;
  *)
    read -r -p "Gio moi ngay (0-23), Enter = 0: " opt </dev/tty || true
    opt="${opt:-0}"
    uex="$(update_to_cron daily "${opt}")"
    ;;
  esac

  write_crond "$rex" "$uex" ""
  echo "Xem: sudo ltm-schedule show - Xoa lich: sudo ltm-schedule remove"
}

cmd_defaults() {
  require_root
  write_crond "$(report_to_cron 15m)" "$(update_to_cron daily 0)" ""
}

cmd_show() {
  if [[ ! -f "$CROND" ]]; then
    echo "(chua co lich) Chay: sudo ltm-schedule hoac sudo ltm-schedule defaults"
    return 0
  fi
  cat "$CROND"
}

cmd_remove() {
  require_root
  rm -f -- "$CROND"
  echo "Da xoa $CROND."
}

usage() {
  echo "sudo ltm-schedule              Wizard chon kieu gui bao/cap nhat"
  echo "sudo ltm-schedule defaults     Goi y: bao 15 phut, cap nhat moi ngay 00:00"
  echo "sudo ltm-schedule apply --report 15m ... --update weekly|daily|off [--update-hour H]"
  echo "  --self-update weekly|daily|off [--self-update-hour H]  (can /etc/ltm-self-update.conf)"
  echo "sudo ltm-schedule show | remove"
}

cmd_apply() {
  require_root
  local rep=15m up=daily uh=0 su=off suh=4
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --report)
      [[ $# -lt 2 ]] && {
        echo "Thieu gia tri sau --report" >&2
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
        echo "Thieu gia tri sau --update" >&2
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
        echo "Thieu gia tri sau --update-hour" >&2
        exit 1
      }
      uh=$2
      shift 2
      ;;
    --self-update)
      [[ $# -lt 2 ]] && {
        echo "Thieu gia tri sau --self-update" >&2
        exit 1
      }
      su=$2
      shift 2
      ;;
    --self-update-off)
      su=off
      shift
      ;;
    --self-update-hour)
      [[ $# -lt 2 ]] && {
        echo "Thieu gia tri sau --self-update-hour" >&2
        exit 1
      }
      suh=$2
      shift 2
      ;;
    *)
      echo "Khong nhan: $1 - sudo ltm-schedule help" >&2
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
    echo "--update chi: off | weekly | daily ($up)." >&2
    exit 1
    ;;
  esac
  case "${su,,}" in
  off | none | '') sx="" ;;
  weekly) sx="$(self_update_to_cron weekly "$suh")" ;;
  daily) sx="$(self_update_to_cron daily "$suh")" ;;
  *)
    echo "--self-update chi: off | weekly | daily ($su)." >&2
    exit 1
    ;;
  esac
  write_crond "$rx" "$ux" "$sx"
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
    echo "Lenh khong ro: ${1:-}. Go: sudo ltm-schedule help" >&2
    exit 1
    ;;
  esac
}

main "$@"
