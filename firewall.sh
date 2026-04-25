#!/usr/bin/env bash

: "${CLOUD_FIREWALL_PROVIDER:=auto}"
: "${CLOUD_FIREWALL_REGION:=}"
: "${CLOUD_FIREWALL_GROUP_ID:=}"
: "${CLOUD_FIREWALL_PROJECT_ID:=}"
: "${CLOUD_FIREWALL_NETWORK:=}"
: "${CLOUD_FIREWALL_TARGET_TAGS:=}"
: "${CLOUD_FIREWALL_NSG_ID:=}"
: "${CLOUD_FIREWALL_SOURCE_CIDR:=0.0.0.0/0}"
: "${CLOUD_FIREWALL_RULE_PREFIX:=xboard-one-click}"

firewall_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$*"
  elif declare -F info >/dev/null 2>&1; then
    info "$*"
  else
    printf '[firewall] %s\n' "$*"
  fi
}

firewall_warn() {
  if declare -F warn >/dev/null 2>&1; then
    warn "$*"
  else
    printf '[firewall][WARN] %s\n' "$*" >&2
  fi
}

firewall_run_privileged() {
  if declare -F run_privileged >/dev/null 2>&1; then
    run_privileged "$@"
  else
    "$@"
  fi
}

firewall_unique_ports() {
  printf '%s\n' "$@" | awk 'NF && !seen[$0]++'
}

firewall_provider_enabled() {
  local provider="$1"
  case "${CLOUD_FIREWALL_PROVIDER:-auto}" in
    auto|"$provider") return 0 ;;
    *) return 1 ;;
  esac
}

firewall_duplicate_or_exists() {
  case "$1" in
    *InvalidPermission.Duplicate*|*Duplicate*|*duplicate*|*AlreadyExists*|*already\ exists*|*Conflict*|*conflict* )
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

firewall_open_aws_port() {
  local port="$1"
  local cmd=(aws ec2 authorize-security-group-ingress --group-id "$CLOUD_FIREWALL_GROUP_ID" --protocol tcp --port "$port" --cidr "$CLOUD_FIREWALL_SOURCE_CIDR")
  local output

  if [ -n "$CLOUD_FIREWALL_REGION" ]; then
    cmd+=(--region "$CLOUD_FIREWALL_REGION")
  fi

  output="$("${cmd[@]}" 2>&1)" && {
    firewall_log "AWS 安全组已放行端口 ${port}/tcp"
    return 0
  }

  if firewall_duplicate_or_exists "$output"; then
    firewall_log "AWS 安全组端口 ${port}/tcp 已存在，跳过"
    return 0
  fi

  firewall_warn "AWS 安全组放行 ${port}/tcp 失败: $output"
  return 1
}

firewall_open_aliyun_port() {
  local port="$1"
  local output

  output="$(aliyun ecs AuthorizeSecurityGroup \
    --RegionId "$CLOUD_FIREWALL_REGION" \
    --SecurityGroupId "$CLOUD_FIREWALL_GROUP_ID" \
    --IpProtocol tcp \
    --PortRange "${port}/${port}" \
    --SourceCidrIp "$CLOUD_FIREWALL_SOURCE_CIDR" \
    --Policy accept \
    --Priority 1 \
    --NicType internet 2>&1)" && {
    firewall_log "阿里云安全组已放行端口 ${port}/tcp"
    return 0
  }

  if firewall_duplicate_or_exists "$output"; then
    firewall_log "阿里云安全组端口 ${port}/tcp 已存在，跳过"
    return 0
  fi

  firewall_warn "阿里云安全组放行 ${port}/tcp 失败: $output"
  return 1
}

firewall_open_gcp_port() {
  local port="$1"
  local rule_name="${CLOUD_FIREWALL_RULE_PREFIX}-tcp-${port}"
  local cmd=(gcloud compute firewall-rules create "$rule_name" "--project=${CLOUD_FIREWALL_PROJECT_ID}" "--network=${CLOUD_FIREWALL_NETWORK}" "--allow=tcp:${port}" "--direction=INGRESS" "--source-ranges=${CLOUD_FIREWALL_SOURCE_CIDR}")
  local output

  if [ -n "$CLOUD_FIREWALL_TARGET_TAGS" ]; then
    cmd+=("--target-tags=${CLOUD_FIREWALL_TARGET_TAGS}")
  fi

  if gcloud compute firewall-rules describe "$rule_name" --project="$CLOUD_FIREWALL_PROJECT_ID" >/dev/null 2>&1; then
    firewall_log "GCP 防火墙规则 ${rule_name} 已存在，跳过"
    return 0
  fi

  output="$("${cmd[@]}" 2>&1)" && {
    firewall_log "GCP 防火墙已放行端口 ${port}/tcp（规则: ${rule_name}）"
    return 0
  }

  if firewall_duplicate_or_exists "$output"; then
    firewall_log "GCP 防火墙规则 ${rule_name} 已存在，跳过"
    return 0
  fi

  firewall_warn "GCP 防火墙放行 ${port}/tcp 失败: $output"
  return 1
}

firewall_open_tencent_port() {
  local port="$1"
  local cmd=(tccli vpc CreateSecurityGroupPolicies --SecurityGroupId "$CLOUD_FIREWALL_GROUP_ID" --SecurityGroupPolicySet "{\"Ingress\":[{\"Protocol\":\"TCP\",\"Port\":\"${port}\",\"CidrBlock\":\"${CLOUD_FIREWALL_SOURCE_CIDR}\",\"Action\":\"ACCEPT\",\"PolicyDescription\":\"xboard-one-click\"}]}")
  local output

  if [ -n "$CLOUD_FIREWALL_REGION" ]; then
    cmd+=(--Region "$CLOUD_FIREWALL_REGION")
  fi

  output="$("${cmd[@]}" 2>&1)" && {
    firewall_log "腾讯云安全组已放行端口 ${port}/tcp"
    return 0
  }

  if firewall_duplicate_or_exists "$output"; then
    firewall_log "腾讯云安全组端口 ${port}/tcp 已存在，跳过"
    return 0
  fi

  firewall_warn "腾讯云安全组放行 ${port}/tcp 失败: $output"
  return 1
}

firewall_open_oci_port() {
  local port="$1"
  local rules_json
  local output

  printf -v rules_json '[{"direction":"INGRESS","protocol":"6","source":"%s","sourceType":"CIDR_BLOCK","description":"xboard-one-click tcp %s","tcpOptions":{"destinationPortRange":{"min":%s,"max":%s}}}]' "$CLOUD_FIREWALL_SOURCE_CIDR" "$port" "$port" "$port"

  output="$(oci network nsg rules add --nsg-id "$CLOUD_FIREWALL_NSG_ID" --security-rules "$rules_json" 2>&1)" && {
    firewall_log "OCI NSG 已放行端口 ${port}/tcp"
    return 0
  }

  if firewall_duplicate_or_exists "$output"; then
    firewall_log "OCI NSG 端口 ${port}/tcp 已存在，跳过"
    return 0
  fi

  firewall_warn "OCI NSG 放行 ${port}/tcp 失败: $output"
  return 1
}

firewall_try_cloud_provider() {
  local provider="$1"
  shift
  local ports=("$@")
  local port

  case "$provider" in
    aws)
      command -v aws >/dev/null 2>&1 || return 1
      [ -n "$CLOUD_FIREWALL_GROUP_ID" ] || return 1
      firewall_log "检测到 AWS 云防火墙配置，开始处理安全组端口"
      for port in "${ports[@]}"; do
        firewall_open_aws_port "$port" || true
      done
      return 0
      ;;
    aliyun)
      command -v aliyun >/dev/null 2>&1 || return 1
      [ -n "$CLOUD_FIREWALL_REGION" ] || return 1
      [ -n "$CLOUD_FIREWALL_GROUP_ID" ] || return 1
      firewall_log "检测到阿里云安全组配置，开始处理安全组端口"
      for port in "${ports[@]}"; do
        firewall_open_aliyun_port "$port" || true
      done
      return 0
      ;;
    gcp)
      command -v gcloud >/dev/null 2>&1 || return 1
      [ -n "$CLOUD_FIREWALL_PROJECT_ID" ] || return 1
      [ -n "$CLOUD_FIREWALL_NETWORK" ] || return 1
      firewall_log "检测到 GCP 防火墙配置，开始处理 VPC 防火墙规则"
      for port in "${ports[@]}"; do
        firewall_open_gcp_port "$port" || true
      done
      return 0
      ;;
    tencent)
      command -v tccli >/dev/null 2>&1 || return 1
      [ -n "$CLOUD_FIREWALL_GROUP_ID" ] || return 1
      firewall_log "检测到腾讯云安全组配置，开始处理安全组端口"
      for port in "${ports[@]}"; do
        firewall_open_tencent_port "$port" || true
      done
      return 0
      ;;
    oci)
      command -v oci >/dev/null 2>&1 || return 1
      [ -n "$CLOUD_FIREWALL_NSG_ID" ] || return 1
      firewall_log "检测到 OCI NSG 配置，开始处理网络安全组端口"
      for port in "${ports[@]}"; do
        firewall_open_oci_port "$port" || true
      done
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

firewall_print_cloud_hint() {
  local ports_csv
  ports_csv="$(printf '%s,' "$@")"
  ports_csv="${ports_csv%,}"

  firewall_warn "如果你使用云服务器，除了本机防火墙外，还需要在云平台安全组/防火墙放行这些 TCP 端口: ${ports_csv}"
  firewall_warn "可在 deploy.env 中配置 CLOUD_FIREWALL_PROVIDER 及对应参数，让脚本自动处理常见云平台防火墙。"
}

open_cloud_firewall_ports() {
  local ports=("$@")
  local handled=0
  local provider

  for provider in aws aliyun gcp tencent oci; do
    if firewall_provider_enabled "$provider" && firewall_try_cloud_provider "$provider" "${ports[@]}"; then
      handled=1
      break
    fi
  done

  if [ "$handled" -eq 0 ]; then
    firewall_print_cloud_hint "${ports[@]}"
  fi
}

open_local_firewall_ports() {
  local ports=("$@")
  local port

  if command -v ufw >/dev/null 2>&1; then
    firewall_log "检测到 UFW，开始放行端口: ${ports[*]}"
    for port in "${ports[@]}"; do
      firewall_run_privileged ufw allow "${port}/tcp"
    done
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall_log "检测到 firewalld，开始放行端口: ${ports[*]}"
    for port in "${ports[@]}"; do
      firewall_run_privileged firewall-cmd --permanent --add-port="${port}/tcp"
    done
    firewall_run_privileged firewall-cmd --reload
    return 0
  fi

  firewall_warn "未检测到可管理的 UFW / firewalld，已跳过本机防火墙放行。"
}

open_all_firewall_ports() {
  local ports=()
  local port

  while IFS= read -r port; do
    [ -n "$port" ] || continue
    ports+=("$port")
  done < <(firewall_unique_ports "$@")

  [ ${#ports[@]} -gt 0 ] || return 0

  open_cloud_firewall_ports "${ports[@]}"
  open_local_firewall_ports "${ports[@]}"
}
