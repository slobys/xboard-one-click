#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xboard-one-click-menu"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BASE_DIR}/runtime"
NPM_DIR="${WORK_DIR}/nginx-proxy-manager"
XBOARD_DIR="${WORK_DIR}/Xboard"
DEPLOY_ENV_FILE="${BASE_DIR}/deploy.env"
XBOARD_NODE_SERVICE="xboard-node"

DEFAULT_NPM_HTTP_PORT=80
DEFAULT_NPM_HTTPS_PORT=443
DEFAULT_NPM_ADMIN_PORT=81
DEFAULT_XBOARD_PORT=7001
DEFAULT_XBOARD_ADMIN_EMAIL="admin@demo.com"
DEFAULT_EXTRA_NPM_HTTPS_PORTS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

COMPOSE_CMD=()
DETECTED_SERVER_IP=""
XBOARD_ADMIN_PATH=""

NPM_HTTP_PORT="${NPM_HTTP_PORT:-}"
NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-}"
NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-}"
EXTRA_NPM_HTTPS_PORTS="${EXTRA_NPM_HTTPS_PORTS:-}"
XBOARD_PORT="${XBOARD_PORT:-}"
XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-}"

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

pause() {
  read -r -p "按回车继续..." _
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "请使用 root 用户运行菜单脚本。"
    exit 1
  fi
}

apply_defaults() {
  NPM_HTTP_PORT="${NPM_HTTP_PORT:-${DEFAULT_NPM_HTTP_PORT}}"
  NPM_HTTPS_PORT="${NPM_HTTPS_PORT:-${DEFAULT_NPM_HTTPS_PORT}}"
  NPM_ADMIN_PORT="${NPM_ADMIN_PORT:-${DEFAULT_NPM_ADMIN_PORT}}"
  EXTRA_NPM_HTTPS_PORTS="${EXTRA_NPM_HTTPS_PORTS:-${DEFAULT_EXTRA_NPM_HTTPS_PORTS}}"
  XBOARD_PORT="${XBOARD_PORT:-${DEFAULT_XBOARD_PORT}}"
  XBOARD_ADMIN_EMAIL="${XBOARD_ADMIN_EMAIL:-${DEFAULT_XBOARD_ADMIN_EMAIL}}"
}

load_deploy_env() {
  if [[ -f "$DEPLOY_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$DEPLOY_ENV_FILE"
    set +a
  fi

  apply_defaults
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

resolve_xboard_admin_path() {
  if [[ ! -f "$XBOARD_DIR/.env" ]]; then
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

ensure_compose_ready() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
  else
    error "未找到 docker compose / docker-compose。"
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "当前用户无法访问 Docker daemon。"
    return 1
  fi

  return 0
}

has_compose_file() {
  local dir="$1"
  [[ -f "$dir/compose.yaml" || -f "$dir/docker-compose.yml" || -f "$dir/docker-compose.yaml" ]]
}

run_compose() {
  local dir="$1"
  shift

  if ! has_compose_file "$dir"; then
    warn "未找到 Compose 配置目录: $dir"
    return 1
  fi

  (cd "$dir" && "${COMPOSE_CMD[@]}" "$@")
}

is_valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

normalize_port_csv() {
  printf '%s' "$1" | tr ', ' '\n\n' | awk 'NF && !seen[$0]++ {printf("%s%s", sep, $0); sep=","}'
}

extra_https_ports_to_array() {
  local normalized
  normalized="$(normalize_port_csv "$EXTRA_NPM_HTTPS_PORTS")"
  EXTRA_NPM_HTTPS_PORTS="$normalized"

  if [[ -n "$normalized" ]]; then
    IFS=',' read -r -a EXTRA_HTTPS_PORTS_ARRAY <<< "$normalized"
  else
    EXTRA_HTTPS_PORTS_ARRAY=()
  fi
}

set_deploy_env_value() {
  local key="$1"
  local value="$2"

  python3 - "$DEPLOY_ENV_FILE" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
prefix = f"{key}="

if path.exists():
    lines = path.read_text().splitlines()
else:
    lines = [
        "# xboard-one-click local config",
        "# 由 menu.sh 自动补充/更新",
    ]

found = False
out = []
for line in lines:
    if line.startswith(prefix):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)

if not found:
    out.append(f"{key}={value}")

path.write_text("\n".join(out).rstrip("\n") + "\n")
PY
}

write_npm_compose() {
  extra_https_ports_to_array
  mkdir -p "$NPM_DIR/data" "$NPM_DIR/letsencrypt"

  {
    cat <<EOF
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "${NPM_HTTP_PORT}:80"
      - "${NPM_HTTPS_PORT}:443"
      - "${NPM_ADMIN_PORT}:81"
EOF

    if [[ ${#EXTRA_HTTPS_PORTS_ARRAY[@]} -gt 0 ]]; then
      local port
      for port in "${EXTRA_HTTPS_PORTS_ARRAY[@]}"; do
        printf '      - "%s:443"\n' "$port"
      done
    fi

    cat <<EOF
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
  } >"$NPM_DIR/compose.yaml"
}

show_extra_https_mappings() {
  extra_https_ports_to_array

  if [[ ${#EXTRA_HTTPS_PORTS_ARRAY[@]} -eq 0 ]]; then
    echo "- NPM 额外 HTTPS 端口: 无"
    return 0
  fi

  echo "- NPM 额外 HTTPS 端口:"
  local port
  for port in "${EXTRA_HTTPS_PORTS_ARRAY[@]}"; do
    echo "  - ${port} -> 443"
  done
}

ensure_npm_ready_for_changes() {
  if [[ ! -d "$NPM_DIR" ]]; then
    warn "未找到 NPM 运行目录，请先执行安装。"
    return 1
  fi

  if ! ensure_compose_ready; then
    return 1
  fi

  return 0
}

save_extra_https_ports() {
  set_deploy_env_value "EXTRA_NPM_HTTPS_PORTS" "$EXTRA_NPM_HTTPS_PORTS"
}

apply_npm_https_mapping_changes() {
  if ! ensure_npm_ready_for_changes; then
    return 1
  fi

  write_npm_compose
  run_compose "$NPM_DIR" up -d
}

port_conflicts_with_main_services() {
  local port="$1"

  [[ "$port" != "$NPM_HTTP_PORT" ]] || return 0
  [[ "$port" != "$NPM_HTTPS_PORT" ]] || return 0
  [[ "$port" != "$NPM_ADMIN_PORT" ]] || return 0
  [[ "$port" != "$XBOARD_PORT" ]] || return 0
  return 1
}

add_npm_https_mapping() {
  local port

  load_deploy_env
  extra_https_ports_to_array

  read -r -p "请输入要额外映射到 443 的主机端口（例如: 8443）: " port
  is_valid_port "$port" || {
    warn "端口无效: $port"
    return 1
  }

  if port_conflicts_with_main_services "$port"; then
    warn "端口 ${port} 与当前主配置端口冲突，请换一个端口。"
    return 1
  fi

  if [[ ",${EXTRA_NPM_HTTPS_PORTS}," == *",${port},"* ]]; then
    warn "端口 ${port} 已经存在于额外 HTTPS 映射中。"
    return 1
  fi

  EXTRA_NPM_HTTPS_PORTS="$(normalize_port_csv "${EXTRA_NPM_HTTPS_PORTS:+${EXTRA_NPM_HTTPS_PORTS},}${port}")"
  save_extra_https_ports

  if ! apply_npm_https_mapping_changes; then
    warn "NPM 额外 HTTPS 端口映射应用失败。"
    return 1
  fi

  open_ports "$port" || true
  success "已添加额外 HTTPS 端口映射：${port} -> 443，并已重建 NPM。"
}

remove_npm_https_mapping() {
  local port
  local remaining=()
  local existing

  load_deploy_env
  extra_https_ports_to_array

  if [[ ${#EXTRA_HTTPS_PORTS_ARRAY[@]} -eq 0 ]]; then
    warn "当前没有额外 HTTPS 端口映射可删除。"
    return 1
  fi

  read -r -p "请输入要删除的额外 HTTPS 主机端口: " port
  is_valid_port "$port" || {
    warn "端口无效: $port"
    return 1
  }

  if [[ ",${EXTRA_NPM_HTTPS_PORTS}," != *",${port},"* ]]; then
    warn "端口 ${port} 不在当前额外 HTTPS 映射列表中。"
    return 1
  fi

  for existing in "${EXTRA_HTTPS_PORTS_ARRAY[@]}"; do
    if [[ "$existing" != "$port" ]]; then
      remaining+=("$existing")
    fi
  done

  EXTRA_NPM_HTTPS_PORTS="$(printf '%s\n' "${remaining[@]}" | awk 'NF && !seen[$0]++ {printf("%s%s", sep, $0); sep=","}')"
  save_extra_https_ports

  if ! apply_npm_https_mapping_changes; then
    warn "NPM 额外 HTTPS 端口映射应用失败。"
    return 1
  fi

  success "已删除额外 HTTPS 端口映射：${port} -> 443，并已重建 NPM。"
}

manage_npm_https_mappings() {
  while true; do
    load_deploy_env
    extra_https_ports_to_array

    echo
    info "当前 NPM HTTPS 端口映射"
    echo "- 主 HTTPS 端口: ${NPM_HTTPS_PORT} -> 443"
    show_extra_https_mappings
    echo
    echo "1. 添加额外 HTTPS 端口映射到 443"
    echo "2. 删除额外 HTTPS 端口映射"
    echo "0. 返回上一级"

    read -r -p "请输入选项: " subchoice
    echo
    case "$subchoice" in
      1)
        add_npm_https_mapping
        pause
        ;;
      2)
        remove_npm_https_mapping
        pause
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        pause
        ;;
    esac
  done
}

unique_ports() {
  awk '!seen[$0]++'
}

open_ports_with_ufw() {
  local ports=("$@")
  local port
  info "检测到 UFW，开始放行端口: ${ports[*]}"
  for port in "${ports[@]}"; do
    ufw allow "${port}/tcp"
  done
}

open_ports_with_firewalld() {
  local ports=("$@")
  local port
  info "检测到 firewalld，开始放行端口: ${ports[*]}"
  for port in "${ports[@]}"; do
    firewall-cmd --permanent --add-port="${port}/tcp"
  done
  firewall-cmd --reload
}

open_ports() {
  local ports=("$@")

  if [[ ${#ports[@]} -eq 0 ]]; then
    warn "没有可放行的端口。"
    return 1
  fi

  if command -v ufw >/dev/null 2>&1; then
    open_ports_with_ufw "${ports[@]}"
    success "端口放行完成。"
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    open_ports_with_firewalld "${ports[@]}"
    success "端口放行完成。"
    return 0
  fi

  warn "未检测到可管理的 UFW / firewalld，请手动放行端口。"
  return 1
}

show_systemd_service_state() {
  local unit="$1"
  local label="$2"
  local load_state
  local active_state
  local enabled_state

  if ! command -v systemctl >/dev/null 2>&1; then
    warn "系统未提供 systemctl，无法查看 ${label} 状态。"
    return 1
  fi

  load_state="$(systemctl show "$unit" --property LoadState --value 2>/dev/null || true)"
  if [[ -z "$load_state" || "$load_state" == "not-found" ]]; then
    warn "${label} (${unit}) 不存在或尚未安装。"
    return 1
  fi

  active_state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled_state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  echo "- ${label}: active=${active_state:-unknown}, enabled=${enabled_state:-unknown}"
}

restart_systemd_service() {
  local unit="$1"
  local label="$2"
  local load_state

  if ! command -v systemctl >/dev/null 2>&1; then
    error "系统未提供 systemctl，无法重启 ${label}。"
    return 1
  fi

  load_state="$(systemctl show "$unit" --property LoadState --value 2>/dev/null || true)"
  if [[ -z "$load_state" || "$load_state" == "not-found" ]]; then
    warn "${label} (${unit}) 不存在或尚未安装。"
    return 1
  fi

  info "重启 ${label} (${unit}) ..."
  systemctl restart "$unit"
  success "${label} 已重启。"
}

show_service_status() {
  local compose_ready=0

  if ensure_compose_ready; then
    compose_ready=1
  fi

  if [[ "$compose_ready" -eq 1 ]]; then
    echo
    info "Nginx Proxy Manager 状态"
    if ! run_compose "$NPM_DIR" ps; then
      warn "NPM 尚未安装或运行目录不存在。"
    fi

    echo
    info "Xboard 状态"
    if ! run_compose "$XBOARD_DIR" ps; then
      warn "Xboard 尚未安装或运行目录不存在。"
    fi
  else
    warn "Docker Compose 不可用，已跳过 NPM / Xboard 容器状态检查。"
  fi

  echo
  info "xboard-node 节点状态"
  show_systemd_service_state "$XBOARD_NODE_SERVICE" "xboard-node 节点" || true
}

show_access_info() {
  load_deploy_env
  resolve_server_ip
  resolve_xboard_admin_path

  echo
  info "当前配置"
  echo "- NPM HTTP 端口: ${NPM_HTTP_PORT}"
  echo "- NPM HTTPS 端口: ${NPM_HTTPS_PORT}"
  echo "- NPM 管理后台端口: ${NPM_ADMIN_PORT}"
  show_extra_https_mappings
  echo "- Xboard 对外端口: ${XBOARD_PORT}"
  echo "- Xboard 管理员邮箱: ${XBOARD_ADMIN_EMAIL}"
  echo
  info "目录"
  echo "- 项目目录: ${BASE_DIR}"
  echo "- NPM: ${NPM_DIR}"
  echo "- Xboard: ${XBOARD_DIR}"
  echo "- 配置文件: ${DEPLOY_ENV_FILE}"
  echo
  info "访问入口"
  echo "- NPM 管理后台: http://${DETECTED_SERVER_IP}:${NPM_ADMIN_PORT}"
  echo "- Xboard 首页: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}"
  if [[ -n "$XBOARD_ADMIN_PATH" ]]; then
    echo "- Xboard 管理面板: http://${DETECTED_SERVER_IP}:${XBOARD_PORT}/${XBOARD_ADMIN_PATH}"
  else
    echo "- Xboard 管理面板: 安装完成后会自动生成安全路径"
  fi
  echo
  info "管理入口"
  echo "- 直接输入: xb"
  echo "- 菜单原路径: bash \"${BASE_DIR}/menu.sh\""
}

run_install() {
  bash "$BASE_DIR/install.sh" --interactive
}

run_update() {
  bash "$BASE_DIR/update.sh"
}

run_uninstall() {
  local purge="$1"
  if [[ "$purge" == "1" ]]; then
    warn "即将停止容器并删除运行目录数据。"
  else
    warn "即将停止容器，但保留运行目录数据。"
  fi

  read -r -p "确认继续吗？[y/N]: " confirm
  case "$confirm" in
    y|Y)
      PURGE_DATA="$purge" bash "$BASE_DIR/uninstall.sh"
      ;;
    *)
      info "已取消。"
      ;;
  esac
}

service_action() {
  local label="$1"
  local dir="$2"
  local action="$3"

  if ! ensure_compose_ready; then
    return 1
  fi

  if ! has_compose_file "$dir"; then
    warn "${label} 尚未安装。"
    return 1
  fi

  case "$action" in
    up)
      info "启动 ${label} ..."
      run_compose "$dir" up -d
      success "${label} 已启动。"
      ;;
    restart)
      info "重启 ${label} ..."
      run_compose "$dir" restart
      success "${label} 已重启。"
      ;;
    logs)
      info "查看 ${label} 日志（按 Ctrl+C 退出）"
      run_compose "$dir" logs -f --tail=100
      ;;
    *)
      error "不支持的操作: $action"
      return 1
      ;;
  esac
}

open_custom_ports() {
  local raw
  local token
  local ports=()

  read -r -p "请输入要放行的端口（空格或逗号分隔，例如: 80 443 7001）: " raw
  raw="${raw//,/ }"

  for token in $raw; do
    if ! is_valid_port "$token"; then
      warn "跳过无效端口: $token"
      continue
    fi
    ports+=("$token")
  done

  if [[ ${#ports[@]} -eq 0 ]]; then
    warn "没有可用的端口输入。"
    return 1
  fi

  mapfile -t ports < <(printf '%s\n' "${ports[@]}" | unique_ports)
  open_ports "${ports[@]}"
}

show_menu() {
  clear
  echo "=========================================="
  echo "      Xboard One Click 管理菜单"
  echo "=========================================="
  echo "1.  安装 / 重新配置（交互式）"
  echo "2.  更新 Xboard / NPM"
  echo "3.  查看服务状态"
  echo "4.  查看访问信息"
  echo "5.  放行额外端口"
  echo "6.  添加 NPM 额外 HTTPS 端口映射"
  echo "7.  重启 NPM"
  echo "8.  重启 Xboard"
  echo "9.  重启 xboard-node 节点"
  echo "10. 启动 NPM"
  echo "11. 启动 Xboard"
  echo "12. 查看 NPM 日志"
  echo "13. 查看 Xboard 日志"
  echo "14. 卸载（保留数据）"
  echo "15. 卸载（删除数据）"
  echo "0.  退出"
  echo "=========================================="
}

main() {
  require_root

  while true; do
    load_deploy_env
    show_menu
    read -r -p "请输入选项: " choice
    echo
    case "$choice" in
      1)
        run_install
        pause
        ;;
      2)
        run_update
        pause
        ;;
      3)
        show_service_status
        pause
        ;;
      4)
        show_access_info
        pause
        ;;
      5)
        open_custom_ports
        pause
        ;;
      6)
        manage_npm_https_mappings
        ;;
      7)
        service_action "NPM" "$NPM_DIR" restart
        pause
        ;;
      8)
        service_action "Xboard" "$XBOARD_DIR" restart
        pause
        ;;
      9)
        restart_systemd_service "$XBOARD_NODE_SERVICE" "xboard-node 节点"
        pause
        ;;
      10)
        service_action "NPM" "$NPM_DIR" up
        pause
        ;;
      11)
        service_action "Xboard" "$XBOARD_DIR" up
        pause
        ;;
      12)
        service_action "NPM" "$NPM_DIR" logs
        pause
        ;;
      13)
        service_action "Xboard" "$XBOARD_DIR" logs
        pause
        ;;
      14)
        run_uninstall 0
        pause
        ;;
      15)
        run_uninstall 1
        pause
        ;;
      0)
        success "已退出。"
        exit 0
        ;;
      *)
        warn "无效选项，请重新输入。"
        pause
        ;;
    esac
  done
}

main "$@"
