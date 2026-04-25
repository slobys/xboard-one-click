# xboard-one-click

![Platform](https://img.shields.io/badge/platform-Debian%20%2F%20Ubuntu-blue)
![Docker](https://img.shields.io/badge/docker-required-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

一键部署 **Xboard + Nginx Proxy Manager**，适合需要快速完成面板部署、端口自定义与 HTTPS 管理的场景。

## 特性

- 基于 Xboard 官方 `compose` 分支
- 默认 SQLite + 内置 Redis
- 自动部署 NPM
- 支持自定义端口
- 自动识别服务器 IP
- 自动放行防火墙端口（云平台安全组/防火墙 + `ufw` / `firewalld`）
- Debian / Ubuntu 支持自动安装 Docker 相关依赖

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/slobys/xboard-one-click/main/bootstrap.sh)
```

这条命令会自动：
- 拉取 / 更新项目到 `/root/xboard-one-click`
- 补齐脚本执行权限
- 启动交互式安装

安装过程中会提示输入：
- NPM HTTP / HTTPS 端口
- NPM 管理后台端口
- Xboard 对外端口
- Xboard 管理员邮箱

## 管理菜单

安装完成后，可以随时调出菜单：

```bash
xb
```

如果你当前就在项目目录里，也可以直接运行：

```bash
./menu.sh
```

安装脚本和更新脚本会自动安装快捷命令：

```bash
/usr/local/bin/xb
```

菜单内已集成：
- 安装 / 重新配置
- 更新环境
- 查看服务状态与访问信息
- 手动放行额外端口
- 重启服务
- 启动服务
- 查看日志
- 卸载（保留数据 / 删除数据）

## 云平台防火墙（重要）

很多云服务器上，**面板打不开的常见原因不是安装失败，而是云平台安全组 / 防火墙没有放行端口**。

脚本会尝试处理本机防火墙，但如果你使用的是：
- 阿里云
- 腾讯云
- AWS
- GCP
- OCI

仍然建议你到对应云平台后台，手动检查并放行端口。

通常至少需要放行：
- `80/tcp`
- `443/tcp`
- `NPM 管理后台端口`
- `Xboard 面板端口`
- 以及你后续手动添加的额外 HTTPS 映射端口

如果服务器本机可以访问，但公网打不开，优先检查云平台安全组 / VPC 防火墙规则。

## 云控制台手动放行端口（很常见）

很多云服务器上，**面板打不开的真实原因不是容器没启动，而是云平台安全组没有放行端口**。

如果你已经确认：
- `ss -ltnp` 能看到端口在监听
- `curl http://127.0.0.1:端口` 能访问
- 本机 `ufw` / `firewalld` 已放行

但公网还是打不开，那么基本就是 **云平台安全组 / VPC 防火墙** 问题。

### 需要放行哪些端口

以一套常见部署为例：
- `80/tcp`：HTTP
- `443/tcp`：HTTPS
- `NPM_ADMIN_PORT/tcp`：NPM 管理后台
- `XBOARD_PORT/tcp`：Xboard 面板
- 以及你后续手动添加的额外 HTTPS 映射端口

例如：
- `80`
- `443`
- `36331`
- `36338`

### 阿里云 / 腾讯云 / AWS / GCP / OCI 控制台怎么放

在对应云平台控制台里，找到这台机器绑定的：
- 安全组
- 或 VPC 防火墙 / NSG / Firewall Rules

然后添加 **入方向 TCP 规则**，先临时允许：

```text
来源: 0.0.0.0/0
协议: TCP
端口: 80, 443, NPM_ADMIN_PORT, XBOARD_PORT
```

### 如何快速判断是不是云安全组问题

在服务器上执行：

```bash
ss -ltnp | grep -E ':(80|443|你的NPM端口|你的Xboard端口)\b'
curl -I http://127.0.0.1:你的NPM端口
curl -I http://127.0.0.1:你的Xboard端口
```

如果本机访问正常，但公网 IP 访问失败，基本就是云安全组没有放行。

## 安装完成后

脚本会输出：
- **Xboard 首页**
- **Xboard 管理面板**
- **NPM 管理后台**

> 注意：Xboard 后台不是根路径，请以脚本输出的 **Xboard 管理面板** 链接为准。

## 适用环境

- Debian / Ubuntu
- 建议使用 `root` 或具备 `sudo` 权限的用户执行

## 相关项目

- Xboard: <https://github.com/cedar2025/Xboard>
