# Linux Telegram Monitor

**Repository:** [github.com/ZakShinn/Linux-Telegram-Monitor](https://github.com/ZakShinn/Linux-Telegram-Monitor)

- [Tiếng Việt](#tieng-viet)
- [English](#english)

---

## Tiếng Việt

[Jump to English](#english)

### Giới thiệu

Bộ script cho **Debian/Ubuntu** để:
- cập nhật hệ thống bằng **APT**,
- gửi báo cáo tài nguyên server (kèm Docker nếu bật),
- điều khiển nhanh qua Telegram bot.

### Tính năng chính

- **`ltm-update`**: `apt-get update/upgrade/full-upgrade`, `autoremove`, `autoclean`, tùy chọn `fwupdmgr`, gửi báo cáo Telegram, có thể tự reboot khi `/var/run/reboot-required`.
- **`ltm-report`**: báo cáo tài nguyên hệ thống, Docker, và các khối theo dõi mở rộng cho Debian/Ubuntu.
- **Ngôn ngữ cài đặt**: chọn `vi` hoặc `en` khi cài; script chỉ cài 1 bộ ngôn ngữ tương ứng cho `ltm-update`, `ltm-report`, `ltm-bot`, `ltm-schedule`.
- **`ltm-bot`**: bot Telegram lấy báo cáo/lệnh nhanh.
- **`ltm-schedule`**: quản lý cron trong `/etc/cron.d/linux-telegram-monitor`.

### Cài đặt

#### 1) Chuẩn bị Telegram
- Tạo bot qua [@BotFather](https://t.me/BotFather), lấy token.
- Nhắn bot 1 tin trong chat/group cần nhận cảnh báo.
- Mở `https://api.telegram.org/bot<TOKEN>/getUpdates` để lấy `chat_id`.

#### 2) Cài script

```bash
git clone https://github.com/ZakShinn/Linux-Telegram-Monitor.git
cd Linux-Telegram-Monitor
sudo bash install.sh
```

Wizard cài đặt sẽ hỏi:
- ngôn ngữ mặc định cho `ltm-report` (**Việt** hoặc **Anh**),
- profile `basic/advanced`,
- dùng **cùng bot/chat** cho update + report hay tách riêng,
- bật điều khiển bot từ Telegram (`/report`, `/status`) — mặc định **bật**,
- bật lệnh `/update` từ bot — mặc định **bật**,
- ghi config vào `/etc`,
- lịch chạy: mặc định `ltm-report` mỗi **15 phút**, `ltm-update` mỗi ngày **00:00** (có thể đổi ngay lúc cài).

Install script cũng tạo luôn `/etc/ltm-telegram-bot.conf` (nếu cho phép ghi), gồm `ALLOW_REMOTE_REPORT` và `ALLOW_REMOTE_UPDATE` theo lựa chọn ở wizard.

#### 3) Cài không tương tác (CI/automation)

```bash
sudo SKIP_INSTALL_PROMPTS=1 \
  LTM_INSTALL_REPORT_LANG=vi \
  LTM_INSTALL_CRON=default \
  bash install.sh
```

Biến môi trường thường dùng:
- `SKIP_INSTALL_PROMPTS=1`
- `LTM_INSTALL_REPORT_LANG=vi|en` (chọn ngôn ngữ cài đặt duy nhất)
- `LTM_INSTALL_CRON=default` (mặc định: report=15m, update=daily 00:00)
- `LTM_INSTALL_PROFILE=basic|advanced`
- `PREFIX`, `DESTDIR`

#### 4) Test nhanh

```bash
sudo ltm-report
sudo ltm-update
```

### Lệnh sử dụng

```bash
sudo ltm-update          # hoặc: sudo server-telegram-update
sudo ltm-report          # hoặc: sudo server-telegram-report
sudo ltm-bot
sudo ltm-schedule
```

### Theo dõi chi tiết Debian/Ubuntu

`ltm-report` gồm: hostname/IP/time/kernel/uptime/OS release, CPU/RAM/swap/disk/load, top CPU/MEM, bảng disk/network.

Bật/tắt qua `/etc/server-telegram-report.conf`:
- Core: `MONITOR_LAST_BOOT`, `MONITOR_SYSTEMD_FAILED`, `MONITOR_DF_ALL`, `MONITOR_INODES`, `MONITOR_MEMINFO`, `MONITOR_LISTEN_PORTS`, `MONITOR_IP_BRIEF`.
- Alert: `MONITOR_ZOMBIES`, `MONITOR_DISK_ALERT`, `DISK_ALERT_PERCENT`.
- TLS/Logs: `MONITOR_TLS_CERTS`, `CERT_WARN_DAYS`, `MONITOR_JOURNAL_ERR`.
- Docker: `MONITOR_DOCKER`, `MONITOR_DOCKER_SYSTEM_DF`, `MONITOR_DOCKER_HEALTH`, `MONITOR_DOCKER_COMPOSE`, `MONITOR_DOCKER_NETWORKS`.
- Debian/Ubuntu detail: `MONITOR_TIMEDATECTL`, `MONITOR_DPKG_AUDIT`, `MONITOR_APT_PENDING`, `APT_PENDING_LIST_LINES`, `MONITOR_REBOOT_PENDING`, `MONITOR_SYSTEMD_SUMMARY`, `MONITOR_SYSTEMD_TIMERS`, `MONITOR_IP_ROUTE`, `MONITOR_SS_CONN_STATS`, `MONITOR_PRESSURE`, `MONITOR_RESOLVECTL`, `MONITOR_UFW`, `MONITOR_UNATTENDED_UPGRADES`, `MONITOR_NEEDRESTART`, `MONITOR_APPARMOR`, `MONITOR_SNAP`, `MONITOR_FLATPAK`, `MONITOR_MDSTAT`, `MONITOR_NFS_MOUNTS`.

`ltm-update` theo dõi: gói upgradable, kernel trước/sau, disk/RAM trước cập nhật, `reboot-required`, `reboot-required.pkgs`, `needrestart` (nếu có).

### Scheduling

```bash
sudo ltm-schedule
sudo ltm-schedule defaults
sudo ltm-schedule show
sudo ltm-schedule remove
sudo ltm-schedule apply --report 4h --update weekly --update-hour 2
```

Cron logs:
- `/var/log/ltm-report.cron.log`
- `/var/log/ltm-update.cron.log`

### Bot (tùy chọn)

```bash
sudo apt install -y jq
sudo cp /usr/local/share/linux-telegram-monitor/ltm-telegram-bot.conf.example /etc/ltm-telegram-bot.conf
sudo chmod 600 /etc/ltm-telegram-bot.conf
sudo nano /etc/ltm-telegram-bot.conf
sudo ltm-bot
```

Menu lệnh Telegram (**tự cập nhật** khi `ltm-bot` khởi động qua `setMyCommands`, tiếng Việt có dấu). Cập nhật tay: `sudo ltm-bot-sync-commands` hoặc `/setcommands` (admin).

**Lệnh bot (Telegram, tiếng Việt có dấu):** `/help` · đọc: `/quick` `/report` `/apt` `/rebootcheck` `/journal` `/tls` `/ufw` `/dns` `/route` `/timers` `/version` `/cron` `/schedule` `/lastreport` + docker/* + hệ thống · hành động (cần `ALLOW_REMOTE_ACTION=1` + chat admin + `/confirm`): `/reboot_now` `/service restart|status <unit>` `/docker_restart` `/docker_logs` `/docker_prune` `/apt_security` · `/silence 2h` tắt `ltm-watch` tạm thời.

Whitelist: copy mẫu `ltm-allowed-services.conf.example`, `ltm-allowed-docker.conf.example` vào `/etc/`.

### ltm-watch (cảnh báo theo ngưỡng)

```bash
sudo cp /usr/local/share/linux-telegram-monitor/ltm-watch.conf.example /etc/ltm-watch.conf
sudo chmod 600 /etc/ltm-watch.conf
sudo ltm-watch              # một lần
sudo ltm-watch --loop       # chạy nền (systemd)
```

Kiểm tra: disk %, load, RAM %, container unhealthy, TLS sắp hết hạn, HTTP URL — chỉ gửi Telegram khi trạng thái **đổi** (tránh spam).

### Cập nhật

#### Cập nhật nhanh theo nhánh hiện tại

```bash
git pull
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
sudo systemctl restart ltm-bot   # nếu chạy bot qua systemd
```

#### Cập nhật theo tag/version

```bash
cat VERSION
cat /usr/local/share/linux-telegram-monitor/VERSION

git fetch --tags origin
git tag -l 'v*'
git checkout v1.0.0
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
```

Quay lại branch chính:

```bash
git checkout main
git pull
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
```

### Gỡ cài đặt

```bash
sudo bash uninstall.sh
sudo bash uninstall.sh --purge
sudo bash uninstall.sh --keep-config
./uninstall.sh --help
```

- `uninstall.sh`: gỡ binary + share + cron.d; hỏi xóa config `/etc` nếu có TTY.
- `--purge`: xóa luôn config `/etc/server-telegram-*.conf`, `/etc/ltm-telegram-bot.conf`.
- `--keep-config`: giữ config `/etc`.

### File quan trọng

| File | Vai trò |
|------|---------|
| `/etc/server-telegram-update.conf` | Token/chat id + tùy chọn update |
| `/etc/server-telegram-report.conf` | Token/chat id + tùy chọn report |
| `/etc/ltm-telegram-bot.conf` | Cấu hình bot |
| `/usr/local/share/linux-telegram-monitor/VERSION` | Version đã cài |

### Troubleshooting

- Không nhận được Telegram: kiểm tra token/chat id và outbound internet.
- Docker không hiện: chạy bằng root hoặc user thuộc group `docker`.
- Bot không phản hồi: thiếu `jq`, chat id sai, hoặc nhiều process cùng đọc updates cùng token.
- Cài không hỏi: có thể đang non-interactive; chỉnh `/etc/*.conf` thủ công.

---

## English

[Quay về Tiếng Việt](#tieng-viet)

### Overview

Scripts for **Debian/Ubuntu** to:
- update the system via **APT**,
- send server resource reports (with Docker when enabled),
- run Telegram bot commands for quick checks.

### Main Features

- **`ltm-update`**: runs `apt-get update/upgrade/full-upgrade`, `autoremove`, `autoclean`; optional `fwupdmgr`; sends Telegram update summary; optional reboot on `/var/run/reboot-required`.
- **`ltm-report`**: system resource reporting with optional Docker and extended Debian/Ubuntu monitoring blocks.
- **Install language**: choose `vi` or `en` during install; only one language pack is installed for `ltm-update`, `ltm-report`, `ltm-bot`, and `ltm-schedule`.
- **`ltm-bot`**: Telegram bot for quick report/diagnostic commands.
- **`ltm-schedule`**: cron manager for `/etc/cron.d/linux-telegram-monitor`.

### Installation

#### 1) Telegram setup
- Create a bot with [@BotFather](https://t.me/BotFather), save the token.
- Send one message in the target chat/group.
- Open `https://api.telegram.org/bot<TOKEN>/getUpdates` and read `chat_id`.

#### 2) Install scripts

```bash
git clone https://github.com/ZakShinn/Linux-Telegram-Monitor.git
cd Linux-Telegram-Monitor
sudo bash install.sh
```

Install wizard asks for:
- default language for `ltm-report` (**Vietnamese** or **English**),
- profile `basic/advanced`,
- whether update/report should share the same Telegram bot/chat or use separate credentials,
- whether to enable Telegram bot command control (`/report`, `/status`) — default **enabled**,
- whether to enable `/update` from Telegram bot — default **enabled**,
- write config into `/etc`,
- schedule setup: default `ltm-report` every **15 minutes**, `ltm-update` daily at **00:00** (editable during install).

Installer also generates `/etc/ltm-telegram-bot.conf` (when writing config is allowed), including `ALLOW_REMOTE_REPORT` and `ALLOW_REMOTE_UPDATE` from your wizard choices.

#### 3) Non-interactive install (CI/automation)

```bash
sudo SKIP_INSTALL_PROMPTS=1 \
  LTM_INSTALL_REPORT_LANG=en \
  LTM_INSTALL_CRON=default \
  bash install.sh
```

Common env vars:
- `SKIP_INSTALL_PROMPTS=1`
- `LTM_INSTALL_REPORT_LANG=vi|en` (single install language)
- `LTM_INSTALL_CRON=default` (default: report=15m, update=daily 00:00)
- `LTM_INSTALL_PROFILE=basic|advanced`
- `PREFIX`, `DESTDIR`

#### 4) Smoke test

```bash
sudo ltm-report
sudo ltm-update
```

### Commands

```bash
sudo ltm-update          # or: sudo server-telegram-update
sudo ltm-report          # or: sudo server-telegram-report
sudo ltm-bot
sudo ltm-schedule
```

### Detailed Monitoring (Debian/Ubuntu)

`ltm-report` includes identity/time/kernel/uptime/OS release, CPU/RAM/swap/disk/load, top CPU/MEM processes, disk/network tables.

Toggle blocks in `/etc/server-telegram-report.conf`:
- Core: `MONITOR_LAST_BOOT`, `MONITOR_SYSTEMD_FAILED`, `MONITOR_DF_ALL`, `MONITOR_INODES`, `MONITOR_MEMINFO`, `MONITOR_LISTEN_PORTS`, `MONITOR_IP_BRIEF`.
- Alerts: `MONITOR_ZOMBIES`, `MONITOR_DISK_ALERT`, `DISK_ALERT_PERCENT`.
- TLS/Logs: `MONITOR_TLS_CERTS`, `CERT_WARN_DAYS`, `MONITOR_JOURNAL_ERR`.
- Docker: `MONITOR_DOCKER`, `MONITOR_DOCKER_SYSTEM_DF`, `MONITOR_DOCKER_HEALTH`, `MONITOR_DOCKER_COMPOSE`, `MONITOR_DOCKER_NETWORKS`.
- Debian/Ubuntu detail: `MONITOR_TIMEDATECTL`, `MONITOR_DPKG_AUDIT`, `MONITOR_APT_PENDING`, `APT_PENDING_LIST_LINES`, `MONITOR_REBOOT_PENDING`, `MONITOR_SYSTEMD_SUMMARY`, `MONITOR_SYSTEMD_TIMERS`, `MONITOR_IP_ROUTE`, `MONITOR_SS_CONN_STATS`, `MONITOR_PRESSURE`, `MONITOR_RESOLVECTL`, `MONITOR_UFW`, `MONITOR_UNATTENDED_UPGRADES`, `MONITOR_NEEDRESTART`, `MONITOR_APPARMOR`, `MONITOR_SNAP`, `MONITOR_FLATPAK`, `MONITOR_MDSTAT`, `MONITOR_NFS_MOUNTS`.

`ltm-update` tracks upgradable packages, kernel before/after, pre-update disk/RAM, reboot-required hints, and `needrestart` output (if installed).

### Scheduling

```bash
sudo ltm-schedule
sudo ltm-schedule defaults
sudo ltm-schedule show
sudo ltm-schedule remove
sudo ltm-schedule apply --report 4h --update weekly --update-hour 2
```

Cron logs:
- `/var/log/ltm-report.cron.log`
- `/var/log/ltm-update.cron.log`

### Bot (Optional)

```bash
sudo apt install -y jq
sudo cp /usr/local/share/linux-telegram-monitor/ltm-telegram-bot.conf.example /etc/ltm-telegram-bot.conf
sudo chmod 600 /etc/ltm-telegram-bot.conf
sudo nano /etc/ltm-telegram-bot.conf
sudo ltm-bot
```

### Updating

#### Quick update (current branch)

```bash
git pull
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
sudo systemctl restart ltm-bot   # if using systemd
```

#### Update by tag/version

```bash
cat VERSION
cat /usr/local/share/linux-telegram-monitor/VERSION

git fetch --tags origin
git tag -l 'v*'
git checkout v1.0.0
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
```

Return to main branch:

```bash
git checkout main
git pull
sudo SKIP_INSTALL_PROMPTS=1 bash install.sh
```

### Uninstallation

```bash
sudo bash uninstall.sh
sudo bash uninstall.sh --purge
sudo bash uninstall.sh --keep-config
./uninstall.sh --help
```

- `uninstall.sh`: remove binaries/share/cron.d; asks about `/etc` config removal when running in TTY mode.
- `--purge`: also remove `/etc/server-telegram-*.conf` and `/etc/ltm-telegram-bot.conf`.
- `--keep-config`: keep `/etc` configs.

### Important Files

| File | Purpose |
|------|---------|
| `/etc/server-telegram-update.conf` | Token/chat id + update options |
| `/etc/server-telegram-report.conf` | Token/chat id + report options |
| `/etc/ltm-telegram-bot.conf` | Bot configuration |
| `/usr/local/share/linux-telegram-monitor/VERSION` | Installed version |

### Troubleshooting

- No Telegram messages: verify token/chat id and outbound network access.
- Docker block missing: run as root or a user in group `docker`.
- Bot not responding: missing `jq`, wrong chat id, or multiple listeners using the same bot token.
- No install prompts: likely non-interactive mode; edit `/etc/*.conf` manually.

---

## License

See [LICENSE](LICENSE).

