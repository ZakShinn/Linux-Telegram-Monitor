#!/usr/bin/env bash
# Gỡ cài linux-telegram-monitor (đảo ngược install.sh vào PREFIX mặc định).
#
#   sudo bash uninstall.sh              # xoá binary + share; có TTY → hỏi xoá /etc hay không [y/N]
#   sudo bash uninstall.sh --purge      # xoá luôn cấu hình trong /etc (không hỏi)
#   sudo bash uninstall.sh --keep-config # chỉ binary + share, không đụng /etc
#
# Đóng góp DESTDIR như install: PREFIX/DESTDIR cùng quy luật install.sh — không đụng /etc trên máy chủ nếu dùng DESTDIR.
#
# Cron / systemd / log: không tự sửa — xem nhắc cuối script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
BIN="${DESTDIR}${PREFIX}/bin"
SHARE="${DESTDIR}${PREFIX}/share/linux-telegram-monitor"

PURGE_ETC=0
KEEP_ETC=0
for arg in "$@"; do
  case "$arg" in
  --purge) PURGE_ETC=1 ;;
  --keep-config) KEEP_ETC=1 ;;
  -h|--help)
    grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "Tham số không rõ: $arg — dùng --help." >&2
    exit 1
    ;;
  esac
done

if [[ "$PURGE_ETC" == "1" ]] && [[ "$KEEP_ETC" == "1" ]]; then
  echo "--purge và --keep-config không dùng cùng lúc." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]] && [[ -z "$DESTDIR" ]]; then
  echo "Chạy với sudo để xoá dưới ${PREFIX}/bin (hoặc đặt DESTDIR khi đóng gói)." >&2
  exit 1
fi

_prompt_n() {
  local msg=$1
  local a
  read -r -p "$msg [y/N]: " a </dev/tty || true
  [[ "$a" =~ ^[Yy] ]]
}

remove_etc_confs() {
  local f
  for f in \
    /etc/server-telegram-update.conf \
    /etc/server-telegram-report.conf \
    /etc/ltm-telegram-bot.conf; do
    if [[ -e "$f" ]] || [[ -L "$f" ]]; then
      rm -f -- "$f"
      echo "Đã xoá: $f"
    fi
  done
}

echo "→ Xoá lệnh cài và symlink…"

# Symlink trước để không còn tham chiếu tới target
rm -f -- "$BIN/ltm-update" "$BIN/ltm-report" 2>/dev/null || true
rm -f -- \
  "$BIN/server-telegram-update" \
  "$BIN/server-telegram-report" \
  "$BIN/ltm-bot" \
  2>/dev/null || true

echo "→ Xoá thư mục mẫu cấu hình (${SHARE})…"
rm -rf -- "$SHARE" 2>/dev/null || true

if [[ -z "$DESTDIR" ]]; then
  if [[ "$KEEP_ETC" == "1" ]]; then
    echo "→ Giữ nguyên /etc (theo --keep-config)."
  elif [[ "$PURGE_ETC" == "1" ]]; then
    echo "→ --purge: xoá file cấu hình trong /etc (nếu có)…"
    remove_etc_confs
  elif [[ -t 0 ]] && [[ -c /dev/tty ]]; then
    if _prompt_n "Xoá luôn cấu hình /etc/server-telegram-*.conf và /etc/ltm-telegram-bot.conf?"; then
      remove_etc_confs
    else
      echo "→ Giữ /etc — xoá thủ công nếu cần hoặc: sudo bash $SCRIPT_DIR/uninstall.sh --purge"
    fi
  else
    echo "→ Không phải TTY: không tự xoá /etc. Muốn xoá hẳn: sudo bash uninstall.sh --purge hoặc PURGE_ETC=1"
  fi
else
  echo "→ DESTDIR đang đặt: chỉ giả lập PREFIX trong DESTDIR — không chỉnh /etc trên máy này."
fi

echo ""
echo "Đã gỡ (trong PREFIX=${PREFIX}${DESTDIR:+(DESTDIR)}) phần cài từ install.sh."
echo "Nhớ tự tay:"
echo "  • Cron: bỏ dòng server-telegram-report / ltm-report / …"
echo "  • systemd: sudo systemctl disable --now ltm-bot  &&  sudo rm -f /etc/systemd/system/ltm-bot.service  &&  sudo systemctl daemon-reload"
echo "  • Log: /var/log/server-telegram-update*.log (tuỳ bạn)"
