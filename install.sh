#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="xboard-one-click"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
NPM_HTTP_PORT="${NPM_HTTP_PORT:-80}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-443}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-81}"
XBOARD_PORT="${XBOARD_PORT:-7001}"
XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-admin@demo.com}"
XBOARD_REPO="${XBOARD_REPO:-https://github.com/cedar2025/Xboard}"
XBOARD_BRANCH="${XBOARD_BRANCH:-compose}"
ENABLE_FIREWALL_OPEN="${ENABLE_FIREWALL_OPEN:-1}"
FORCE_XBOARD_INSTALL="${FORCE_XBOARD_INSTALL:-0}"

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

check_env() {
  need_cmd git
  need_cmd docker
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

  python3 - "$XBOARD_DIR/.env" <<'PY'
from pathlib import Path
import os
import sys
path = Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines()
updates = {
    'APP_URL': f'http://localhost:{os.environ.get("XBOARD_PORT", "7001")}',
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
  python3 - "$XBOARD_DIR/compose.yaml" <<'PY'
from pathlib import Path
import os
import re
import sys
path = Path(sys.argv[1])
text = path.read_text()
port = os.environ.get('XBOARD_PORT', '7001')
text_new = re.sub(r'-\s*"\d+:7001"', f'- "{port}:7001"', text, count=1)
if text_new == text and '7001:7001' not in text:
    raise SystemExit('未在 compose.yaml 中找到 Xboard 端口映射，已停止以避免误改。')
path.write_text(text_new)
PY
}

should_install_xboard() {
  [ "$FORCE_XBOARD_INSTALL" = "1" ] && return 0
  [ ! -s "$XBOARD_DIR/.docker/.data/database.sqlite" ] && return 0
  return 1
}

install_xboard() {
  clone_or_update_xboard
  ensure_xboard_port_mapping
  prepare_xboard_env

  if should_install_xboard; then
    log "执行 Xboard 初始化（SQLite + 内置 Redis）"
    run_compose "$XBOARD_DIR" run --rm \
      -e ENABLE_SQLITE=true \
      -e ENABLE_REDIS=true \
      -e ADMIN_ACCOUNT="$XBOARD_ADMIN_EMAIL" \
      xboard php artisan xboard:install
  else
    log "检测到现有 SQLite 数据，跳过 Xboard 初始化。如需强制重装可传入 FORCE_XBOARD_INSTALL=1"
  fi

  log "启动 Xboard"
  run_compose "$XBOARD_DIR" up -d
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

print_summary() {
  cat <<EOF

部署完成。

目录：
- NPM: ${NPM_DIR}
- Xboard: ${XBOARD_DIR}

访问入口：
- NPM 管理后台: http://服务器IP:${NPM_ADMIN_PORT}
- Xboard 直连地址: http://服务器IP:${XBOARD_PORT}

已尝试放行端口：
- ${NPM_HTTP_PORT}/tcp
- ${NPM_HTTPS_PORT}/tcp
- ${NPM_ADMIN_PORT}/tcp
- ${XBOARD_PORT}/tcp

NPM 默认初始账号：
- Email: admin@example.com
- Password: changeme

建议下一步：
1. 登录 NPM 后立即修改默认账号密码
2. 在 NPM 中新增 Proxy Host，把你的域名反代到 `http://服务器IP:${XBOARD_PORT}`
3. 如果公网和 DNS 已就绪，再在 NPM 中申请 Let's Encrypt 证书

常用命令：
- 启动 NPM:    cd "${NPM_DIR}" && ${COMPOSE_CMD[*]} up -d
- 启动 Xboard: cd "${XBOARD_DIR}" && ${COMPOSE_CMD[*]} up -d
- 查看 Xboard 日志: cd "${XBOARD_DIR}" && ${COMPOSE_CMD[*]} logs -f
EOF
}

main() {
  check_env
  prepare_dirs
  install_npm
  install_xboard
  open_firewall_ports
  print_summary
}

main "$@"
