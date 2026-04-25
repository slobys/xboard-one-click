#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/slobys/xboard-one-click.git}"
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/root/xboard-one-click}"
SUDO_CMD=()

log() {
  printf '[xboard-one-click-bootstrap] %s\n' "$*"
}

die() {
  printf '[xboard-one-click-bootstrap][WARN] %s\n' "$*" >&2
  exit 1
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

  die "请使用 root 运行，或先安装 sudo。"
}

run_privileged() {
  "${SUDO_CMD[@]}" "$@"
}

ensure_git() {
  command -v git >/dev/null 2>&1 && return 0

  if command -v apt-get >/dev/null 2>&1; then
    log "未检测到 git，尝试自动安装"
    run_privileged apt-get update
    run_privileged apt-get install -y git
    command -v git >/dev/null 2>&1 && return 0
  fi

  die "缺少 git，请先手动安装后重试。"
}

prepare_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    log "检测到已有目录，更新到最新代码: $INSTALL_DIR"
    run_privileged git -C "$INSTALL_DIR" fetch origin "$BRANCH" --depth 1
    run_privileged git -C "$INSTALL_DIR" checkout "$BRANCH"
    run_privileged git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
    return 0
  fi

  if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR/.git" ]; then
    die "目标目录已存在但不是 git 仓库: $INSTALL_DIR"
  fi

  log "克隆项目到: $INSTALL_DIR"
  run_privileged mkdir -p "$(dirname "$INSTALL_DIR")"
  run_privileged git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
}

main() {
  init_privilege_helper
  ensure_git
  prepare_repo

  log "开始执行交互式安装"
  run_privileged chmod +x "$INSTALL_DIR/install.sh" "$INSTALL_DIR/update.sh" "$INSTALL_DIR/uninstall.sh" "$INSTALL_DIR/menu.sh" "$INSTALL_DIR/bootstrap.sh" "$INSTALL_DIR/firewall.sh"

  if [ "$(id -u)" -eq 0 ]; then
    exec bash "$INSTALL_DIR/install.sh" --interactive
  fi

  exec "${SUDO_CMD[@]}" bash "$INSTALL_DIR/install.sh" --interactive
}

main "$@"
