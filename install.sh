#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="xboard-one-click"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
DEPLOY_ENV_FILE="${SCRIPT_DIR}/deploy.env"
NPM_PROXY_TEMPLATE_FILE="${SCRIPT_DIR}/npm-proxy-template.txt"

DEFAULT_NPM_HTTP_PORT=80
DEFAULT_NPM_HTTPS_PORT=443
DEFAULT_NPM_ADMIN_PORT=81
DEFAULT_XBOARD_PORT=7001
DEFAULT_XBOARD_ADMIN_EMAIL="admin@demo.com"
DEFAULT_XBOARD_REPO="https://github.com/cedar2025/Xboard"
DEFAULT_XBOARD_BRANCH="compose"
DEFAULT_ENABLE_FIREWALL_OPEN=1
DEFAULT_FORCE_XBOARD_INSTALL=0
DEFAULT_INTERACTIVE_CONFIG=0
DEFAULT_AUTO_WRITE_DEPLOY_ENV=1
DEFAULT_AUTO_INSTALL_DEPS=1

INPUT_SERVER_IP="${SERVER_IP:-}"
DETECTED_SERVER_IP=""
XBOARD_ADMIN_PATH=""

INPUT_NPM_HTTP_PORT="${NPM_HTTP_PORT:-}"
INPUT_NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-}"
INPUT_NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-}"
INPUT_XBOARD_PORT="${XBOARD_PORT:-}"
INPUT_XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-}"
INPUT_XBOARD_REPO="${XBOARD_REPO:-}"
INPUT_XBOARD_BRANCH="${XBOARD_BRANCH:-}"
INPUT_ENABLE_FIREWALL_OPEN="${ENABLE_FIREWALL_OPEN:-}"
INPUT_FORCE_XBOARD_INSTALL="${FORCE_XBOARD_INSTALL:-}"
INPUT_INTERACTIVE_CONFIG="${INTERACTIVE_CONFIG:-}"
INPUT_AUTO_WRITE_DEPLOY_ENV="${AUTO_WRITE_DEPLOY_ENV:-}"
INPUT_AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-}"

SERVER_IP="${SERVER_IP:-}"
NPM_HTTP_PORT="${NPM_HTTP_PORT:-}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-}"
XBOARD_PORT="${XBOARD_PORT:-}"
XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-}"
XBOARD_REPO="${XBOARD_REPO:-}"
XBOARD_BRANCH="${XBOARD_BRANCH:-}"
ENABLE_FIREWALL_OPEN="${ENABLE_FIREWALL_OPEN:-}"
FORCE_XBOARD_INSTALL="${FORCE_XBOARD_INSTALL:-}"
INTERACTIVE_CONFIG="${INTERACTIVE_CONFIG:-}"
AUTO_WRITE_DEPLOY_ENV="${AUTO_WRITE_DEPLOY_ENV:-}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-}"

COMPOSE_CMD=()
SUDO_CMD=()

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

warn() {
  printf '[%s][WARN] %s\n' "$PROJECT_NAME" "$*" >&2
}

die() {
  warn "$*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

run_compose() {
  local dir="$1"
  shift
  (cd "$dir" && "${COMPOSE_CMD[@]}" "$@")
}

run_privileged() {
  "${SUDO_CMD[@]}" "$@"
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

first_nonempty_line() {
  awk 'NF {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit}'
}

fetch_public_ip() {
  local value
  if command -v curl >/dev/null 2>&1; then
    for url in \
      "https://api.ipify.org" \
      "https://ipv4.icanhazip.com" \
      "https://ifconfig.me/ip"
    do
      value="$(curl -4fsSL --max-time 5 "$url" 2>/dev/null | first_nonempty_line || true)"
      if is_ipv4 "$value"; then
        printf '%s' "$value"
        return 0
      fi
    done
  fi

  if command -v wget >/dev/null 2>&1; then
    for url in \
      "https://api.ipify.org" \
      "https://ipv4.icanhazip.com" \
      "https://ifconfig.me/ip"
    do
      value="$(wget -4qO- --timeout=5 "$url" 2>/dev/null | first_nonempty_line || true)"
      if is_ipv4 "$value"; then
        printf '%s' "$value"
        return 0
      fi
    done
  fi

  return 1
}

fetch_local_ip() {
  local value
  if command -v ip >/dev/null 2>&1; then
    value="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
    if is_ipv4 "$value"; then
      printf '%s' "$value"
      return 0
    fi
  fi

  value="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if is_ipv4 "$value"; then
    printf '%s' "$value"
    return 0
  fi

  return 1
}

resolve_server_ip() {
  if is_ipv4 "$SERVER_IP"; then
    DETECTED_SERVER_IP="$SERVER_IP"
    return 0
  fi

  DETECTED_SERVER_IP="$(fetch_public_ip || true)"
  if is_ipv4 "$DETECTED_SERVER_IP"; then
    return 0
  fi

  DETECTED_SERVER_IP="$(fetch_local_ip || true)"
  if is_ipv4 "$DETECTED_SERVER_IP"; then
    return 0
  fi

  DETECTED_SERVER_IP="服务器IP"
}

restore_input_overrides() {
  [ -z "$INPUT_NPM_HTTP_PORT" ] || NPM_HTTP_PORT="$INPUT_NPM_HTTP_PORT"
  [ -z "$INPUT_NPM_HTTPS_PORT" ] || NPM_HTTPS_PORT="$INPUT_NPM_HTTPS_PORT"
  [ -z "$INPUT_NPM_ADMIN_PORT" ] || NPM_ADMIN_PORT="$INPUT_NPM_ADMIN_PORT"
  [ -z "$INPUT_XBOARD_PORT" ] || XBOARD_PORT="$INPUT_XBOARD_PORT"
  [ -z "$INPUT_XBOARD_ADMIN_EMAIL" ] || XBOARD_ADMIN_EMAIL="$INPUT_XBOARD_ADMIN_EMAIL"
  [ -z "$INPUT_XBOARD_REPO" ] || XBOARD_REPO="$INPUT_XBOARD_REPO"
  [ -z "$INPUT_XBOARD_BRANCH" ] || XBOARD_BRANCH="$INPUT_XBOARD_BRANCH"
  [ -z "$INPUT_ENABLE_FIREWALL_OPEN" ] || ENABLE_FIREWALL_OPEN="$INPUT_ENABLE_FIREWALL_OPEN"
  [ -z "$INPUT_FORCE_XBOARD_INSTALL" ] || FORCE_XBOARD_INSTALL="$INPUT_FORCE_XBOARD_INSTALL"
  [ -z "$INPUT_INTERACTIVE_CONFIG" ] || INTERACTIVE_CONFIG="$INPUT_INTERACTIVE_CONFIG"
  [ -z "$INPUT_AUTO_WRITE_DEPLOY_ENV" ] || AUTO_WRITE_DEPLOY_ENV="$INPUT_AUTO_WRITE_DEPLOY_ENV"
  [ -z "$INPUT_AUTO_INSTALL_DEPS" ] || AUTO_INSTALL_DEPS="$INPUT_AUTO_INSTALL_DEPS"
  [ -z "$INPUT_SERVER_IP" ] || SERVER_IP="$INPUT_SERVER_IP"
}

load_deploy_env() {
  if [ -f "$DEPLOY_ENV_FILE" ]; then
    log "加载本地配置文件: $DEPLOY_ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    . "$DEPLOY_ENV_FILE"
    set +a
  fi

  restore_input_overrides
}

apply_defaults() {
  NPM_HTTP_PORT="${NPM_HTTP_PORT:-${DEFAULT_NPM_HTTP_PORT}}"
  NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-${DEFAULT_NPM_HTTPS_PORT}}"
  NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-${DEFAULT_NPM_ADMIN_PORT}}"
  XBOARD_PORT="${XBOARD_PORT:-${DEFAULT_XBOARD_PORT}}"
  XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-${DEFAULT_XBOARD_ADMIN_EMAIL}}"
  XBOARD_REPO="${XBOARD_REPO:-${DEFAULT_XBOARD_REPO}}"
  XBOARD_BRANCH="${XBOARD_BRANCH:-${DEFAULT_XBOARD_BRANCH}}"
  ENABLE_FIREWALL_OPEN="${ENABLE_FIREWALL_OPEN:-${DEFAULT_ENABLE_FIREWALL_OPEN}}"
  FORCE_XBOARD_INSTALL="${FORCE_XBOARD_INSTALL:-${DEFAULT_FORCE_XBOARD_INSTALL}}"
  INTERACTIVE_CONFIG="${INTERACTIVE_CONFIG:-${DEFAULT_INTERACTIVE_CONFIG}}"
  AUTO_WRITE_DEPLOY_ENV="${AUTO_WRITE_DEPLOY_ENV:-${DEFAULT_AUTO_WRITE_DEPLOY_ENV}}"
  AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-${DEFAULT_AUTO_INSTALL_DEPS}}"
}

print_usage() {
  cat <<EOF
用法：
  ./install.sh [--interactive|-i] [--non-interactive]

说明：
  --interactive      交互式填写端口和管理员邮箱，并写入 deploy.env
  --non-interactive  完全按环境变量 / deploy.env / 默认值执行

优先级：
  shell 环境变量 > deploy.env > 脚本默认值

补充：
  AUTO_INSTALL_DEPS=1 时，会在 Debian/Ubuntu 上自动安装缺失依赖（如 docker）
EOF
}

print_startup_notice() {
  if [ "$AUTO_INSTALL_DEPS" = "1" ]; then
    log "AUTO_INSTALL_DEPS=1：若检测到 Debian/Ubuntu 缺少 Docker / Compose / git / python3，将自动尝试安装"
  else
    log "AUTO_INSTALL_DEPS=0：已关闭自动安装依赖，请确保系统已手动安装 Docker / Compose / git / python3"
  fi

  log "访问地址将优先自动识别公网 IP；识别不到则回退到本机 IP，也可用 SERVER_IP=1.2.3.4 手动指定"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --interactive|-i)
        INTERACTIVE_CONFIG=1
        ;;
      --non-interactive)
        INTERACTIVE_CONFIG=0
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        die "不支持的参数: $1"
        ;;
    esac
    shift
  done
}

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

validate_email() {
  [[ "$1" == *"@"* ]]
}

validate_config() {
  local port
  for port in "$NPM_HTTP_PORT" "$NPM_HTTPS_PORT" "$NPM_ADMIN_PORT" "$XBOARD_PORT"; do
    is_valid_port "$port" || die "端口无效: $port"
  done

  [ "$NPM_HTTP_PORT" != "$NPM_HTTPS_PORT" ] || die "NPM_HTTP_PORT 与 NPM_HTTPS_PORT 不能相同"
  [ "$NPM_HTTP_PORT" != "$NPM_ADMIN_PORT" ] || die "NPM_HTTP_PORT 与 NPM_ADMIN_PORT 不能相同"
  [ "$NPM_HTTP_PORT" != "$XBOARD_PORT" ] || die "NPM_HTTP_PORT 与 XBOARD_PORT 不能相同"
  [ "$NPM_HTTPS_PORT" != "$NPM_ADMIN_PORT" ] || die "NPM_HTTPS_PORT 与 NPM_ADMIN_PORT 不能相同"
  [ "$NPM_HTTPS_PORT" != "$XBOARD_PORT" ] || die "NPM_HTTPS_PORT 与 XBOARD_PORT 不能相同"
  [ "$NPM_ADMIN_PORT" != "$XBOARD_PORT" ] || die "NPM_ADMIN_PORT 与 XBOARD_PORT 不能相同"

  validate_email "$XBOARD_ADMIN_EMAIL" || die "XBOARD_ADMIN_EMAIL 格式看起来不对: $XBOARD_ADMIN_EMAIL"
}

prompt_value() {
  local label="$1"
  local current="$2"
  local answer
  printf '%s [%s]: ' "$label" "$current" >&2
  read -r answer || true
  if [ -n "$answer" ]; then
    printf '%s' "$answer"
  else
    printf '%s' "$current"
  fi
}

prompt_port() {
  local label="$1"
  local current="$2"
  local value
  while true; do
    value="$(prompt_value "$label" "$current")"
    if is_valid_port "$value"; then
      printf '%s' "$value"
      return
    fi
    warn "请输入 1-65535 之间的端口号"
  done
}

configure_interactively() {
  [ "$INTERACTIVE_CONFIG" = "1" ] || return 0
  [ -t 0 ] || die "交互模式需要 TTY。请在终端执行，或改用环境变量 / deploy.env。"

  log "进入交互式配置"
  printf '%s\n' '提示：80/443 推荐保留给 NPM，后续申请证书更省事。' >&2

  NPM_HTTP_PORT="$(prompt_port 'NPM HTTP 端口' "$NPM_HTTP_PORT")"
  NPM_HTTPS_PORT="$(prompt_port 'NPM HTTPS 端口' "$NPM_HTTPS_PORT")"
  NPM_ADMIN_PORT="$(prompt_port 'NPM 管理后台端口' "$NPM_ADMIN_PORT")"
  XBOARD_PORT="$(prompt_port 'Xboard 对外端口' "$XBOARD_PORT")"
  XBOARD_ADMIN_EMAIL="$(prompt_value 'Xboard 管理员邮箱' "$XBOARD_ADMIN_EMAIL")"

  validate_config
}

write_deploy_env() {
  [ "$AUTO_WRITE_DEPLOY_ENV" = "1" ] || return 0

  cat >"$DEPLOY_ENV_FILE" <<EOF
# xboard-one-click local config
# 由 install.sh 自动生成/更新
NPM_HTTP_PORT=${NPM_HTTP_PORT}
NPM_HTTPS_PORT=${NPM_HTTPS_PORT}
NPM_ADMIN_PORT=${NPM_ADMIN_PORT}
XBOARD_PORT=${XBOARD_PORT}
XBOARD_ADMIN_EMAIL=${XBOARD_ADMIN_EMAIL}
XBOARD_REPO=${XBOARD_REPO}
XBOARD_BRANCH=${XBOARD_BRANCH}
ENABLE_FIREWALL_OPEN=${ENABLE_FIREWALL_OPEN}
FORCE_XBOARD_INSTALL=${FORCE_XBOARD_INSTALL}
EOF

  log "已写入配置文件: $DEPLOY_ENV_FILE"
}

init_privilege_helper() {
  if [ "$(id -u)" -eq 0 ]; then
    SUDO_CMD=()
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD=(sudo)
    return
  fi

  SUDO_CMD=()
}

can_use_apt() {
  command -v apt-get >/dev/null 2>&1 && [ -f /etc/os-release ]
}

install_missing_dependencies() {
  [ "$AUTO_INSTALL_DEPS" = "1" ] || return 0
  can_use_apt || return 0

  local missing=()
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v python3 >/dev/null 2>&1 || missing+=(python3)
  command -v docker >/dev/null 2>&1 || missing+=(docker)

  [ ${#missing[@]} -gt 0 ] || return 0

  log "检测到缺失依赖: ${missing[*]}"
  log "尝试在 Debian/Ubuntu 上自动安装依赖"

  local packages=(ca-certificates curl)
  command -v git >/dev/null 2>&1 || packages+=(git)
  command -v python3 >/dev/null 2>&1 || packages+=(python3)

  if ! command -v docker >/dev/null 2>&1; then
    packages+=(docker.io)
    if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
      packages+=(docker-compose-plugin)
    elif apt-cache show docker-compose-v2 >/dev/null 2>&1; then
      packages+=(docker-compose-v2)
    elif apt-cache show docker-compose >/dev/null 2>&1; then
      packages+=(docker-compose)
    fi
  fi

  run_privileged apt-get update
  run_privileged apt-get install -y "${packages[@]}"

  if command -v systemctl >/dev/null 2>&1; then
    run_privileged systemctl enable --now docker || true
  elif command -v service >/dev/null 2>&1; then
    run_privileged service docker start || true
  fi
}

check_env() {
  need_cmd git
  command -v docker >/dev/null 2>&1 || die "缺少命令: docker。若是 Debian/Ubuntu，可保持 AUTO_INSTALL_DEPS=1 重试；否则请先手动安装 Docker。"
  need_cmd python3

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    die "未找到 docker compose / docker-compose"
  fi

  if ! docker info >/dev/null 2>&1; then
    die "当前用户无法访问 Docker daemon。请先确保 Docker 已启动，并让当前用户具备 docker 权限后重试。"
  fi

  init_privilege_helper
}

prepare_dirs() {
  mkdir -p "$WORK_DIR" "$NPM_DIR/data" "$NPM_DIR/letsencrypt"
}

write_npm_compose() {
  cat >"$NPM_DIR/compose.yaml" <<EOF
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "${NPM_HTTP_PORT}:80"
      - "${NPM_HTTPS_PORT}:443"
      - "${NPM_ADMIN_PORT}:81"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
}

install_npm() {
  log "写入 Nginx Proxy Manager compose 配置"
  write_npm_compose
  log "启动 Nginx Proxy Manager"
  run_compose "$NPM_DIR" up -d
}

install_menu_shortcut() {
  local target="/usr/local/bin/xb"

  if [ ! -f "$SCRIPT_DIR/menu.sh" ]; then
    warn "未找到 menu.sh，已跳过安装 xb 快捷命令。"
    return 0
  fi

  log "安装快捷命令: xb -> ${SCRIPT_DIR}/menu.sh"
  run_privileged tee "$target" >/dev/null <<EOF
#!/usr/bin/env bash
exec bash "${SCRIPT_DIR}/menu.sh" "\$@"
EOF
  run_privileged chmod +x "$target"
}

clone_or_update_xboard() {
  if [ ! -d "$XBOARD_DIR/.git" ]; then
    log "拉取 Xboard (${XBOARD_BRANCH} 分支)"
    git clone -b "$XBOARD_BRANCH" --depth 1 "$XBOARD_REPO" "$XBOARD_DIR"
  else
    log "检测到已存在 Xboard 仓库，执行更新"
    git -C "$XBOARD_DIR" fetch origin "$XBOARD_BRANCH" --depth 1
    git -C "$XBOARD_DIR" checkout "$XBOARD_BRANCH"
    git -C "$XBOARD_DIR" reset --hard "origin/$XBOARD_BRANCH"
  fi
}

prepare_xboard_env() {
  mkdir -p "$XBOARD_DIR/.docker/.data" "$XBOARD_DIR/storage/logs" "$XBOARD_DIR/storage/theme" "$XBOARD_DIR/plugins"

  if [ -f "$XBOARD_DIR/.env.example" ] && [ ! -f "$XBOARD_DIR/.env" ]; then
    cp "$XBOARD_DIR/.env.example" "$XBOARD_DIR/.env"
  fi

  if [ ! -f "$XBOARD_DIR/.env" ]; then
    cat >"$XBOARD_DIR/.env" <<EOF
APP_NAME=XBoard
APP_ENV=local
APP_KEY=
APP_DEBUG=false
APP_URL=http://localhost

APP_RUNNING_IN_CONSOLE=true

LOG_CHANNEL=stack

DB_CONNECTION=sqlite
DB_DATABASE=/www/.docker/.data/database.sqlite

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis

MAIL_DRIVER=smtp
MAIL_HOST=
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=
MAIL_FROM_NAME=

ENABLE_AUTO_BACKUP_AND_UPDATE=false
INSTALLED=false
EOF
  fi

  python3 - "$XBOARD_DIR/.env" "$XBOARD_PORT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
port = sys.argv[2]
text = path.read_text()
lines = text.splitlines()
updates = {
    'APP_URL': f'http://localhost:{port}',
    'DB_CONNECTION': 'sqlite',
    'DB_DATABASE': '/www/.docker/.data/database.sqlite',
    'REDIS_HOST': '127.0.0.1',
    'REDIS_PASSWORD': 'null',
    'REDIS_PORT': '6379',
    'BROADCAST_DRIVER': 'log',
    'CACHE_DRIVER': 'redis',
    'QUEUE_CONNECTION': 'redis',
}
seen = set()
out = []
for line in lines:
    if '=' in line and not line.lstrip().startswith('#'):
        key = line.split('=', 1)[0]
        if key in updates:
            out.append(f'{key}={updates[key]}')
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f'{key}={value}')
path.write_text('\n'.join(out) + '\n')
PY

  if [ ! -f "$XBOARD_DIR/.docker/.data/database.sqlite" ]; then
    : > "$XBOARD_DIR/.docker/.data/database.sqlite"
  fi
}

ensure_xboard_port_mapping() {
  python3 - "$XBOARD_DIR/compose.yaml" "$XBOARD_PORT" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
port = sys.argv[2]
text = path.read_text()
text_new = text.replace('"7001:7001"', f'"{port}:7001"', 1)
if text_new == text:
    text_new = re.sub(r'-\s*"\d+:7001"', f'- "{port}:7001"', text, count=1)
if text_new == text:
    raise SystemExit('未在 compose.yaml 中找到可替换的 Xboard 端口映射，已停止以避免误改。')
path.write_text(text_new)
PY

  if ! grep -Fq "\"${XBOARD_PORT}:7001\"" "$XBOARD_DIR/compose.yaml"; then
    die "compose.yaml 端口映射校验失败，未发现 ${XBOARD_PORT}:7001"
  fi

  log "compose.yaml 端口映射已更新为 ${XBOARD_PORT}:7001"
}

should_install_xboard() {
  [ "$FORCE_XBOARD_INSTALL" = "1" ] && return 0
  [ ! -s "$XBOARD_DIR/.docker/.data/database.sqlite" ] && return 0
  return 1
}

wait_for_xboard_redis() {
  local attempt=1
  local max_attempts=30

  while [ "$attempt" -le "$max_attempts" ]; do
    if run_compose "$XBOARD_DIR" exec -T xboard sh -lc 'test -S /data/redis.sock'; then
      log "检测到 Xboard 内置 Redis 已就绪"
      return 0
    fi

    sleep 2
    attempt=$((attempt + 1))
  done

  warn "等待 Xboard 内置 Redis 就绪超时，输出最近日志供排查"
  run_compose "$XBOARD_DIR" logs --tail=80 xboard || true
  die "Xboard 内置 Redis 未能及时启动，已停止安装。"
}

install_xboard() {
  clone_or_update_xboard
  ensure_xboard_port_mapping
  prepare_xboard_env

  log "先启动 Xboard 容器，确保内置 Redis 正常就绪"
  run_compose "$XBOARD_DIR" up -d
  wait_for_xboard_redis

  if should_install_xboard; then
    log "在已启动的 Xboard 容器内执行初始化（SQLite + 内置 Redis）"
    run_compose "$XBOARD_DIR" exec -T \
      -e ENABLE_SQLITE=true \
      -e ENABLE_REDIS=true \
      -e ADMIN_ACCOUNT="$XBOARD_ADMIN_EMAIL" \
      xboard php artisan xboard:install
  else
    log "检测到现有 SQLite 数据，跳过 Xboard 初始化。如需强制重装可传入 FORCE_XBOARD_INSTALL=1"
  fi

  log "确认 Xboard 维持启动状态"
  run_compose "$XBOARD_DIR" up -d

  log "验证 Xboard 实际对外端口映射"
  run_compose "$XBOARD_DIR" port xboard 7001
}

resolve_xboard_admin_path() {
  if [ ! -f "$XBOARD_DIR/.env" ]; then
    XBOARD_ADMIN_PATH=""
    return 0
  fi

  XBOARD_ADMIN_PATH="$(python3 - "$XBOARD_DIR/.env" <<'PY'
from pathlib import Path
import binascii
import sys
path = Path(sys.argv[1])
app_key = ""
for line in path.read_text().splitlines():
    if line.startswith("APP_KEY="):
        app_key = line.split("=", 1)[1].strip()
        break
if app_key:
    print(f"{binascii.crc32(app_key.encode()) & 0xffffffff:08x}")
PY
)"
}

open_port_once() {
  local port="$1"
  local opened_list="$2"
  case ",${opened_list}," in
    *",${port},"*) return 1 ;;
    *) return 0 ;;
  esac
}

open_firewall_ports() {
  [ "$ENABLE_FIREWALL_OPEN" = "1" ] || {
    log "已跳过防火墙放行（ENABLE_FIREWALL_OPEN=${ENABLE_FIREWALL_OPEN}）"
    return
  }

  local ports=()
  local opened=""
  local port
  for port in "$NPM_HTTP_PORT" "$NPM_HTTPS_PORT" "$NPM_ADMIN_PORT" "$XBOARD_PORT"; do
    if open_port_once "$port" "$opened"; then
      ports+=("$port")
      opened="${opened},${port}"
    fi
  done

  if command -v ufw >/dev/null 2>&1; then
    log "检测到 UFW，开始放行端口: ${ports[*]}"
    for port in "${ports[@]}"; do
      run_privileged ufw allow "${port}/tcp"
    done
    return
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    log "检测到 firewalld，开始放行端口: ${ports[*]}"
    for port in "${ports[@]}"; do
      run_privileged firewall-cmd --permanent --add-port="${port}/tcp"
    done
    run_privileged firewall-cmd --reload
    return
  fi

  warn "未检测到可管理的 UFW / firewalld，已跳过防火墙放行。"
}

write_npm_proxy_template() {
  cat >"$NPM_PROXY_TEMPLATE_FILE" <<EOF
Nginx Proxy Manager 反代模板
============================

建议填写：
- Domain Names: xboard.example.com
- Scheme: http
- Forward Hostname / IP: ${DETECTED_SERVER_IP}
- Forward Port: ${XBOARD_PORT}
- Cache Assets: 按需，默认可不开
- Block Common Exploits: 开启
- Websockets Support: 开启

SSL 建议：
- 如果域名已解析到服务器，并且 ${NPM_HTTP_PORT}/tcp 与 ${NPM_HTTPS_PORT}/tcp 已放行
- 可以在 NPM 中勾选申请 Let's Encrypt 证书
- Force SSL: 建议开启
- HTTP/2 Support: 建议开启
- HSTS Enabled: 按需

访问参考：
- NPM 后台: http://${DETECTED_SERVER_IP}:${NPM_ADMIN_PORT}
- Xboard 首页: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}
- Xboard 管理面板: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}/${XBOARD_ADMIN_PATH}
EOF
}

print_summary() {
  cat <<EOF

部署完成。

当前配置：
- NPM HTTP 端口: ${NPM_HTTP_PORT}
- NPM HTTPS 端口: ${NPM_HTTPS_PORT}
- NPM 管理后台端口: ${NPM_ADMIN_PORT}
- Xboard 对外端口: ${XBOARD_PORT}
- Xboard 管理员邮箱: ${XBOARD_ADMIN_EMAIL}

目录：
- NPM: ${NPM_DIR}
- Xboard: ${XBOARD_DIR}
- 配置文件: ${DEPLOY_ENV_FILE}
- 管理菜单: ${SCRIPT_DIR}/menu.sh
- 菜单快捷命令: /usr/local/bin/xb
- NPM 反代模板: ${NPM_PROXY_TEMPLATE_FILE}

访问入口：
- NPM 管理后台: http://${DETECTED_SERVER_IP}:${NPM_ADMIN_PORT}
- Xboard 首页: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}
- Xboard 管理面板: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}/${XBOARD_ADMIN_PATH}

已尝试放行端口：
- ${NPM_HTTP_PORT}/tcp
- ${NPM_HTTPS_PORT}/tcp
- ${NPM_ADMIN_PORT}/tcp
- ${XBOARD_PORT}/tcp

NPM 首次访问：
- 新版 NPM 请按页面引导完成初始化，不再使用旧版默认账号密码提示

建议下一步：
1. 打开 Xboard 管理面板：http://${DETECTED_SERVER_IP}:${XBOARD_PORT}/${XBOARD_ADMIN_PATH}
2. 登录 NPM 后按页面引导完成初始化
3. 在 NPM 中新增 Proxy Host，把你的域名反代到 http://${DETECTED_SERVER_IP}:${XBOARD_PORT}
4. 如果公网和 DNS 已就绪，再在 NPM 中申请 Let's Encrypt 证书

NPM 反代填写模板：
- Domain Names: xboard.example.com
- Scheme: http
- Forward Hostname / IP: ${DETECTED_SERVER_IP}
- Forward Port: ${XBOARD_PORT}
- Block Common Exploits: 开启
- Websockets Support: 开启
- SSL: 域名解析和端口放通后，在 NPM 中申请 Let's Encrypt
- 反代完成后，Xboard 管理面板路径仍然是：/${XBOARD_ADMIN_PATH}

常用命令：
- 打开菜单:     xb
- 菜单原路径:   bash "${SCRIPT_DIR}/menu.sh"
- 启动 NPM:     cd "${NPM_DIR}" && ${COMPOSE_CMD[*]} up -d
- 重启 NPM:     cd "${NPM_DIR}" && ${COMPOSE_CMD[*]} restart
- 启动 Xboard:  cd "${XBOARD_DIR}" && ${COMPOSE_CMD[*]} up -d
- 重启 Xboard:  cd "${XBOARD_DIR}" && ${COMPOSE_CMD[*]} restart
- 重启 Node 节点: systemctl restart xboard-node
- 查看 Xboard 日志: cd "${XBOARD_DIR}" && ${COMPOSE_CMD[*]} logs -f
EOF
}

main() {
  load_deploy_env
  parse_args "$@"
  apply_defaults
  print_startup_notice
  configure_interactively
  validate_config
  write_deploy_env
  resolve_server_ip
  init_privilege_helper
  install_missing_dependencies
  check_env
  prepare_dirs
  install_npm
  install_xboard
  install_menu_shortcut
  resolve_xboard_admin_path
  write_npm_proxy_template
  open_firewall_ports
  print_summary
}

main "$@"
