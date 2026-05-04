# Linux Telegram Monitor

**Repository:** [github.com/ZakShinn/Linux-Telegram-Monitor](https://github.com/ZakShinn/Linux-Telegram-Monitor)

Bộ script chạy trên Linux (chuẩn **Debian/Ubuntu**) để: **nhận cập nhật gói** (APT), **báo cáo tài nguyên server + Docker**, và **gửi kết quả lên Telegram**. Cấu hình đơn giản bằng file và vài lệnh.

---

## Có những gì?

### Cập nhật hệ thống (`ltm-update`)

Chạy cập nhật package kiểu Ubuntu/Debian, gửi tóm tắt lên Telegram, có log trên máy. Có thể bật cập nhật firmware và tự reboot sau cập nhật (tuỳ cấu hình — reboot thường để **tắt**).

### Báo cáo định kỳ (`ltm-report`)

Một báo cáo gửi Telegram: máy chủ đang làm việc thế nào (đĩa, RAM, tải, mạng, top tiến trình…), có thêm phần **Docker** nếu máy có Docker và bạn đã cho phép.

### Bot Telegram (`ltm-bot`)

Gõ lệnh trong chat để lấy **báo cáo nhanh** hoặc **báo cáo đầy đủ** như `ltm-report`. Còn nhiều lệnh phụ như xem Docker, đĩa, RAM… Gõ **`/help`** khi bot đã chạy để xem đủ. Lệnh **`/update`** từ Telegram mặc định **tắt** vì nhạy cảm — chỉ bật nếu bạn hiểu rủi ro.

Để bot chạy nền, dùng **systemd** (ví dụ service chạy `ltm-bot`, chạy lại khi tắt). Cần cài **`jq`** trước khi chạy bot.

---

## Cài đặt (lược đồ thường dùng)

### 1. Chuẩn bị Telegram

- Tạo bot với [@BotFather](https://t.me/BotFather), lưu **token**.
- Nhắn bot một câu trong đúng chat (hoặc nhóm) bạn muốn nhận tin.
- Mở trên trình duyệt `https://api.telegram.org/bot<TOKEN>/getUpdates` và tìm số **chat id** của bạn trong kết quả (thêm tin rồi tải lại trang nếu không thấy).

### 2. Cài vào máy chủ

```bash
git clone https://github.com/ZakShinn/Linux-Telegram-Monitor.git
cd Linux-Telegram-Monitor
sudo bash install.sh
```

Script sẽ hỏi vài điều: **cấu hình ngắn** hoặc **đầy đủ**, rồi có thể ghi file dưới **`/etc`** và hỏi nhập token + chat id (hoặc bạn sửa file sau bằng `nano`).

### 3. Thử báo cáo

```bash
sudo ltm-report
```

Nếu Telegram nhận được báo cáo là ổn. **Docker** không hiện nếu tài khoản chạy lệnh không có quyền với Docker — thường chạy bằng **root** hoặc thêm user vào nhóm **docker**.

### 4. Lịch tự động (tuỳ nhu cầu)

```bash
sudo crontab -e
```

Ví dụ: **mỗi 6 giờ** báo cáo, **mỗi tuần** chạy cập nhật (chỉ khi bạn muốn tự động cập nhật):

```cron
0 3 * * 0 /usr/local/bin/ltm-update >> /var/log/server-telegram-update.cron.log 2>&1
0 */6 * * * /usr/local/bin/ltm-report >> /var/log/server-telegram-report.cron.log 2>&1
```

### 5. Bot lệnh (tuỳ chọn)

```bash
sudo apt install -y jq
sudo cp /usr/local/share/linux-telegram-monitor/ltm-telegram-bot.conf.example /etc/ltm-telegram-bot.conf
sudo chmod 600 /etc/ltm-telegram-bot.conf
sudo nano /etc/ltm-telegram-bot.conf
```

Điền **token** và **chat id** giống báo cáo (file mẫu có gợi ý dùng chung với file báo cáo). Chạy **`sudo ltm-bot`** hoặc tạo **service systemd** trỏ tới `ltm-bot` để chạy nền.

**Lưu ý:** chỉ chạy **một** bot lắng nghe lệnh với **cùng** token Telegram.

---

## Gỡ cài

```bash
sudo bash uninstall.sh
```

Có phiên bản **xoá luôn file cấu hình trong `/etc`** hoặc **giữ nguyên** — xem `./uninstall.sh --help`. Cron và service systemd **cần tự tay** xóa/ghi đè vì không nằm trong script repo.

---

## File cần biết

| File | Vai trò |
|------|---------|
| `/etc/server-telegram-update.conf` | Token Telegram + tùy chọn cập nhật/reboot/log |
| `/etc/server-telegram-report.conf` | Token Telegram + bật/tắt từng phần trong báo cáo |
| `/etc/ltm-telegram-bot.conf` | Bot lệnh (tự tạo nếu dùng bot) |

File mẫu nằm trong **`/usr/local/share/linux-telegram-monitor/`** sau khi cài. Chi tiết từng dòng trong mẫu **`.conf.example`** — không cần nhớ hết trong README.

Lệnh tương đương:

```bash
sudo ltm-update     # hay: sudo server-telegram-update
sudo ltm-report      # hay: sudo server-telegram-report
```

---

## Không hoạt động?

- **Không có tin Telegram:** Sai token hoặc chat id; máy chủ không ra internet.
- **Bot không đáp:** Thiếu **jq**, sai chat id, hoặc đang có **hai** chỗ cùng bắt tin của một bot.
- **`install.sh` không hỏi gì:** Thường do chạy không qua terminal thật — bạn chỉnh file trong **`/etc`** thủ công và copy từ mẫu.

---

## Nâng cao (ích khi làm máy chủ/DevOps)

Biến môi trường khi cài: **`SKIP_INSTALL_PROMPTS`**, **`LTM_INSTALL_PROFILE`**, **`PREFIX`**, **`DESTDIR`**… xem trong **`install.sh`**. Bot có thêm **`REMOTE_CMD_TIMEOUT`** trong file cấu hình.

Trên Telegram có thể dùng **BotFather → Edit Commands** để nhập danh sách lệnh gợi ý (định dạng theo [tài liệu Telegram](https://core.telegram.org/bots/api#setmycommands)).

---

## Giấy phép

Xem [LICENSE](LICENSE).
