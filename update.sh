#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="xboard-one-click-update"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
DEPLOY_ENV_FILE="${SCRIPT_DIR}/deploy.env"

DEFAULT_XBOARD_BRANCH="compose"
DEFAULT_XBOARD_PORT=7001

INPUT_XBOARD_BRANCH="${XBOARD_BRANCH:-}"
INPUT_XBOARD_PORT="${XBOARD_PORT:-}"

XBOARD_BRANCH="${XBOARD_BRANCH:-}"
XBOARD_PORT="${XBOARD_PORT:-}"
COMPOSE_CMD=()

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

die() {
  printf '[%s][WARN] %s\n' "$PROJECT_NAME" "$*" >&2
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

install_menu_shortcut() {
  local target="/usr/local/bin/xb"

  if [ ! -f "$SCRIPT_DIR/menu.sh" ]; then
    log "未找到 menu.sh，跳过安装 xb 快捷命令"
    return 0
  fi

  cat >"$target" <<EOF
#!/usr/bin/env bash
exec bash "${SCRIPT_DIR}/menu.sh" "\$@"
EOF
  chmod +x "$target"

  log "已安装快捷命令: xb -> ${SCRIPT_DIR}/menu.sh"
}

load_deploy_env() {
  if [ -f "$DEPLOY_ENV_FILE" ]; then
    log "加载本地配置文件: $DEPLOY_ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    . "$DEPLOY_ENV_FILE"
    set +a
  fi

  [ -z "$INPUT_XBOARD_BRANCH" ] || XBOARD_BRANCH="$INPUT_XBOARD_BRANCH"
  [ -z "$INPUT_XBOARD_PORT" ] || XBOARD_PORT="$INPUT_XBOARD_PORT"
}

apply_defaults() {
  XBOARD_BRANCH="${XBOARD_BRANCH:-${DEFAULT_XBOARD_BRANCH}}"
  XBOARD_PORT="${XBOARD_PORT:-${DEFAULT_XBOARD_PORT}}"
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

  docker info >/dev/null 2>&1 || die "当前用户无法访问 Docker daemon。"
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

main() {
  load_deploy_env
  apply_defaults
  check_env

  [ -f "$NPM_DIR/compose.yaml" ] || die "未找到 NPM 部署目录，请先执行 ./install.sh"
  [ -d "$XBOARD_DIR/.git" ] || die "未找到 Xboard 运行目录，请先执行 ./install.sh"

  log "更新 Nginx Proxy Manager 镜像"
  run_compose "$NPM_DIR" pull
  run_compose "$NPM_DIR" up -d

  log "更新 Xboard 仓库代码"
  git -C "$XBOARD_DIR" fetch origin "$XBOARD_BRANCH" --depth 1
  git -C "$XBOARD_DIR" checkout "$XBOARD_BRANCH"
  git -C "$XBOARD_DIR" reset --hard "origin/$XBOARD_BRANCH"
  ensure_xboard_port_mapping

  log "更新 Xboard 镜像并重建容器"
  run_compose "$XBOARD_DIR" pull
  run_compose "$XBOARD_DIR" up -d
  run_compose "$XBOARD_DIR" port xboard 7001

  install_menu_shortcut

  log "更新完成（当前 Xboard 对外端口: $XBOARD_PORT）"
}

main "$@"
