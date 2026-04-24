#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="xboard-one-click-uninstall"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
PURGE_DATA="${PURGE_DATA:-0}"

COMPOSE_CMD=()

log() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$*"
}

warn() {
  printf '[%s][WARN] %s\n' "$PROJECT_NAME" "$*" >&2
}

check_env() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    warn "未找到 docker compose / docker-compose，只执行目录级清理判断。"
  fi
}

compose_down_if_exists() {
  local dir="$1"
  if [ ${#COMPOSE_CMD[@]} -gt 0 ] && [ -f "$dir/compose.yaml" ]; then
    (cd "$dir" && "${COMPOSE_CMD[@]}" down || true)
  fi
}

main() {
  check_env
  compose_down_if_exists "$NPM_DIR"
  compose_down_if_exists "$XBOARD_DIR"

  if [ "$PURGE_DATA" = "1" ]; then
    log "PURGE_DATA=1，删除运行目录: $WORK_DIR"
    rm -rf "$WORK_DIR"
  else
    log "已停止容器，但保留数据目录。若要彻底删除，请执行: PURGE_DATA=1 ./uninstall.sh"
  fi
}

main "$@"
