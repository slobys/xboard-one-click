# xboard-one-click

一键部署 **Xboard + Nginx Proxy Manager**。

适合希望快速完成以下流程的用户：
- 部署 Xboard
- 部署 Nginx Proxy Manager（NPM）
- 使用自定义端口
- 后续通过 NPM 配置域名反代和 HTTPS

## 特性

- 基于 Xboard 官方 `compose` 分支
- 默认使用 SQLite + 内置 Redis
- 自动部署 NPM
- 支持自定义端口
- 自动识别服务器 IP
- 自动放行防火墙端口（`ufw` / `firewalld`）
- Debian / Ubuntu 支持自动安装 Docker 相关依赖

## 快速开始

```bash
git clone https://github.com/slobys/xboard-one-click.git
cd xboard-one-click
chmod +x install.sh update.sh uninstall.sh
./install.sh --interactive
```

安装过程中会提示输入：
- NPM HTTP 端口
- NPM HTTPS 端口
- NPM 管理后台端口
- Xboard 对外端口
- Xboard 管理员邮箱

## 安装完成后

脚本会直接输出：
- **Xboard 首页**
- **Xboard 管理面板**
- **NPM 管理后台**

> 注意：Xboard 后台不是根路径，请以脚本输出的 **Xboard 管理面板** 链接为准。

## NPM 反向代理

安装完成后，脚本会生成：

```bash
npm-proxy-template.txt
```

可直接查看：

```bash
cat npm-proxy-template.txt
```

在 NPM 中配置反代时，核心参数如下：
- **Scheme**: `http`
- **Forward Hostname / IP**: 服务器 IP
- **Forward Port**: 你设置的 `XBOARD_PORT`

如果使用域名访问，Xboard 后台地址仍然是：

```text
https://你的域名/安全路径
```

而不是仅访问域名根路径。

## 常用方式

### 交互式安装（推荐）

```bash
./install.sh --interactive
```

### 使用固定配置

```bash
cp deploy.env.example deploy.env
nano deploy.env
./install.sh
```

### 强制重新安装

```bash
FORCE_XBOARD_INSTALL=1 ./install.sh --interactive
```

## 更新与卸载

更新：

```bash
./update.sh
```

停止容器但保留数据：

```bash
./uninstall.sh
```

彻底删除运行目录和数据：

```bash
PURGE_DATA=1 ./uninstall.sh
```

## 常见问题

### 1. 打不开 Xboard 后台
请确认访问的是脚本输出的 **Xboard 管理面板** 地址，而不是：

```text
http://IP:XBOARD_PORT/
```

### 2. 自定义端口后无法访问
执行：

```bash
cd ~/xboard-one-click/runtime/Xboard
docker compose port xboard 7001
docker compose ps
```

用于确认 Xboard 实际映射到的宿主机端口。

### 3. 域名访问返回 404
通常表示反代已通，但访问的不是后台安全路径。

正确方式应为：

```text
https://你的域名/安全路径
```

## 适用环境

- Debian / Ubuntu
- 已开放所需端口
- 建议使用 `root` 或具备 `sudo` 权限的用户执行

## 相关项目

- Xboard: <https://github.com/cedar2025/Xboard>
