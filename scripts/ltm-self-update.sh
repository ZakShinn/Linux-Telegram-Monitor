#!/usr/bin/env bash
# ltm-self-update.sh — Tu cap nhat Linux-Telegram-Monitor tu git + chay lai install.sh
#
#   sudo ltm-self-update              # git pull neu co ban moi
#   sudo ltm-self-update --force      # cai lai du co thay doi commit
#   sudo ltm-self-update --check-only # chi kiem tra, khong cai
#
# Cau hinh: /etc/ltm-self-update.conf

set -euo pipefail

readonly CONF_SYSTEM="/etc/ltm-self-update.conf"
readonly CONF_REPORT="/etc/server-telegram-report.conf"
readonly CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/ltm-self-update.conf"
readonly LOCK_FILE="/var/run/ltm-self-update.lock"
readonly LOG_FILE="/var/log/ltm-self-update.log"
readonly SHARE_VERSION="/usr/local/share/linux-telegram-monitor/VERSION"

FORCE=0
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
  --force | -f) FORCE=1 ;;
  --check-only | --check) CHECK_ONLY=1 ;;
  -h | --help)
    head -n 12 "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  esac
done

# shellcheck source=/dev/null
[[ -f "$CONF_SYSTEM" ]] && source "$CONF_SYSTEM"
# shellcheck source=/dev/null
[[ -f "$CONF_USER" ]] && source "$CONF_USER"

LTM_REPO_DIR="${LTM_REPO_DIR:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
LTM_INSTALL_REPORT_LANG="${LTM_INSTALL_REPORT_LANG:-vi}"
AUTO_INSTALL="${AUTO_INSTALL:-1}"
NOTIFY_TELEGRAM="${NOTIFY_TELEGRAM:-1}"
RESTART_LTM_BOT="${RESTART_LTM_BOT:-1}"
SYNC_BOT_COMMANDS="${SYNC_BOT_COMMANDS:-1}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-install.sh}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

acquire_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      log "Dang chay (pid $pid) — bo qua."
      exit 0
    fi
  fi
  echo $$ >"$LOCK_FILE"
}

release_lock() { rm -f -- "$LOCK_FILE" 2>/dev/null || true; }
trap release_lock EXIT

tg_notify() {
  [[ "$NOTIFY_TELEGRAM" == "1" ]] || return 0
  local msg=$1
  # shellcheck source=/dev/null
  [[ -f "$CONF_REPORT" ]] && source "$CONF_REPORT"
  local token="${TELEGRAM_BOT_TOKEN:-${TOKEN:-}}"
  local chat="${TELEGRAM_CHAT_ID:-${CHAT_ID:-}}"
  [[ -n "$token" && -n "$chat" ]] || return 0
  local cid
  IFS=',' read -ra _c <<< "${chat// /,}"
  for cid in "${_c[@]}"; do
    cid="${cid//[[:space:]]/}"
    [[ -z "$cid" ]] && continue
    curl -fsS --max-time 20 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
      --data-urlencode "chat_id=${cid}" \
      --data-urlencode "parse_mode=HTML" \
      --data-urlencode "text=${msg}" >/dev/null 2>&1 || true
  done
}

installed_version() {
  [[ -f "$SHARE_VERSION" ]] && tr -d '[:space:]' <"$SHARE_VERSION" || echo "unknown"
}

run_install() {
  local repo=$1
  [[ "$AUTO_INSTALL" == "1" ]] || {
    log "AUTO_INSTALL=0 — chi git pull, khong chay install.sh"
    return 0
  }
  [[ -f "${repo}/${INSTALL_SCRIPT}" ]] || {
    log "Khong thay ${repo}/${INSTALL_SCRIPT}"
    return 1
  }
  log "Chay install.sh (SKIP_INSTALL_PROMPTS=1, lang=${LTM_INSTALL_REPORT_LANG})..."
  (
    cd "$repo"
    SKIP_INSTALL_PROMPTS=1 \
      LTM_INSTALL_REPORT_LANG="${LTM_INSTALL_REPORT_LANG}" \
      bash "./${INSTALL_SCRIPT}"
  )
}

restart_bot_if_needed() {
  [[ "$RESTART_LTM_BOT" == "1" ]] || return 0
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files ltm-bot.service >/dev/null 2>&1; then
    systemctl restart ltm-bot 2>/dev/null && log "Da restart ltm-bot (systemd)." && return 0
  fi
  if pgrep -f '[l]tm-bot' >/dev/null 2>&1; then
    log "ltm-bot dang chay (khong phai systemd) — restart thu cong neu can."
  fi
}

sync_commands_if_needed() {
  [[ "$SYNC_BOT_COMMANDS" == "1" ]] || return 0
  command -v ltm-bot-sync-commands >/dev/null 2>&1 || return 0
  ltm-bot-sync-commands >>"$LOG_FILE" 2>&1 || true
  log "Da goi ltm-bot-sync-commands."
}

main() {
  [[ "$(id -u)" -eq 0 ]] || {
    echo "Can chay voi sudo." >&2
    exit 1
  }
  command -v git >/dev/null 2>&1 || {
    echo "Can cai git." >&2
    exit 1
  }

  if [[ -z "${LTM_REPO_DIR// }" ]]; then
    echo "Thieu LTM_REPO_DIR trong $CONF_SYSTEM" >&2
    echo "Vi du: LTM_REPO_DIR=/opt/Linux-Telegram-Monitor" >&2
    exit 1
  fi
  if [[ ! -d "${LTM_REPO_DIR}/.git" ]]; then
    echo "Khong phai git repo: ${LTM_REPO_DIR}" >&2
    echo "Clone: git clone https://github.com/ZakShinn/Linux-Telegram-Monitor.git ${LTM_REPO_DIR}" >&2
    exit 1
  fi

  acquire_lock
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="${TMPDIR:-/tmp}/ltm-self-update.log"

  local before after remote_sha local_sha
  before=$(installed_version)
  log "Bat dau ltm-self-update (da cai: ${before}) — repo=${LTM_REPO_DIR} branch=${GIT_BRANCH}"

  (
    cd "$LTM_REPO_DIR"
    git remote get-url "$GIT_REMOTE" >/dev/null 2>&1 || git remote add "$GIT_REMOTE" https://github.com/ZakShinn/Linux-Telegram-Monitor.git 2>/dev/null || true
    git fetch "$GIT_REMOTE" "$GIT_BRANCH" --quiet 2>>"$LOG_FILE" || git fetch "$GIT_REMOTE" --quiet 2>>"$LOG_FILE" || true
    remote_sha=$(git rev-parse "${GIT_REMOTE}/${GIT_BRANCH}" 2>/dev/null || git rev-parse "origin/${GIT_BRANCH}" 2>/dev/null || true)
    local_sha=$(git rev-parse HEAD 2>/dev/null || true)
  )

  if [[ -z "$remote_sha" || -z "$local_sha" ]]; then
    log "Khong doc duoc git SHA — thu pull truc tiep."
  elif [[ "$remote_sha" == "$local_sha" && "$FORCE" != "1" ]]; then
    log "Da la ban moi nhat (${local_sha:0:8})."
    tg_notify "ℹ️ <b>ltm-self-update</b>: da moi nhat (<code>${before}</code>) — <code>$(hostname -s)</code>"
    exit 0
  fi

  if [[ "$CHECK_ONLY" == "1" ]]; then
    log "Co ban moi: ${local_sha:0:8} -> ${remote_sha:0:8} (chi kiem tra)."
    exit 0
  fi

  (
    cd "$LTM_REPO_DIR"
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
      log "Canh bao: repo co thay doi local — van pull (co the conflict)."
    fi
    git pull "$GIT_REMOTE" "$GIT_BRANCH" --ff-only 2>>"$LOG_FILE" || git pull "$GIT_REMOTE" "$GIT_BRANCH" 2>>"$LOG_FILE"
  )

  run_install "$LTM_REPO_DIR"
  after=$(installed_version)
  restart_bot_if_needed
  sync_commands_if_needed

  log "Hoan tat: ${before} -> ${after} (commit ${remote_sha:0:8})"
  tg_notify "✅ <b>ltm-self-update</b> — <code>$(hostname -s)</code>
• Phien ban: <code>${before}</code> → <code>${after}</code>
• Git: <code>${local_sha:0:8}</code> → <code>${remote_sha:0:8}</code>"
}

main "$@"
