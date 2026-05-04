#!/usr/bin/env bash
# Cài script vào PREFIX/bin (mặc định /usr/local/bin) để gọi trực tiếp tên lệnh.
# Chạy trên máy Linux: bash install.sh   hoặc   sudo bash install.sh
#
# Tuỳ chọn môi trường:
#   PREFIX=/usr/local          # thư mục gốc (bin = $PREFIX/bin)
#   DESTDIR=/tmp/stage         # tiền tố đường dẫn (đóng gói .deb/.rpm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
BIN="${DESTDIR}${PREFIX}/bin"
SHARE="${DESTDIR}${PREFIX}/share/linux-telegram-monitor"

if [[ "$(id -u)" -ne 0 ]] && [[ -z "$DESTDIR" ]]; then
  echo "Chạy với sudo để ghi vào ${PREFIX}/bin (hoặc đặt DESTDIR để chỉ tạo cây thư mục trong DESTDIR)." >&2
  exit 1
fi

install -d -m 755 "$BIN"
install -d -m 755 "$SHARE"

install -m 755 "$SCRIPT_DIR/scripts/ubuntu-telegram-update.sh" "$BIN/ubuntu-telegram-update"
install -m 755 "$SCRIPT_DIR/scripts/server-telegram-report.sh" "$BIN/server-telegram-report"

install -m 644 "$SCRIPT_DIR/scripts/ubuntu-telegram-update.conf.example" "$SHARE/"
install -m 644 "$SCRIPT_DIR/scripts/server-telegram-report.conf.example" "$SHARE/"

cat <<EOF
Đã cài lệnh:
  $BIN/ubuntu-telegram-update
  $BIN/server-telegram-report

File cấu hình mẫu:
  $SHARE/ubuntu-telegram-update.conf.example
  $SHARE/server-telegram-report.conf.example

Thiết lập (ví dụ):
  sudo cp $SHARE/ubuntu-telegram-update.conf.example /etc/ubuntu-telegram-update.conf
  sudo chmod 600 /etc/ubuntu-telegram-update.conf
  sudo nano /etc/ubuntu-telegram-update.conf

  sudo cp $SHARE/server-telegram-report.conf.example /etc/server-telegram-report.conf
  sudo chmod 600 /etc/server-telegram-report.conf
  sudo nano /etc/server-telegram-report.conf

Chạy thử:
  sudo ubuntu-telegram-update
  sudo server-telegram-report
EOF
