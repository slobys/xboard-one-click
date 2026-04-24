# xboard-one-click

Xboard 一键部署脚本项目，默认走稳妥方案：

- **Nginx Proxy Manager 使用 Docker Compose 部署**
- **Xboard 使用官方 compose 分支部署**
- **Xboard 默认使用 SQLite + 内置 Redis**
- **安装脚本自动尝试放行对应防火墙端口**
- **反向代理主机在 NPM 后台手动添加**

这样做比直接执行第三方来源不明脚本更稳，也更容易维护。

## 项目边界

本项目独立目录：`xboard-one-click/`

不要和以下现有项目混用：

- `dujiao-next-one-click/`
- `headscale-one-click/`
- `openclash-auto-installer/`

## 当前目录结构

```text
xboard-one-click/
├── .gitignore
├── install.sh
├── update.sh
├── uninstall.sh
├── README.md
└── runtime/
    ├── nginx-proxy-manager/
    └── Xboard/
```

## 依赖要求

目标机器至少需要：

- `git`
- `docker`
- `docker compose`（或 `docker-compose`）
- `python3`

并且**当前用户必须能访问 Docker daemon**。

如果你希望脚本自动放行防火墙端口，建议用 `root` 执行，或确保当前用户可用 `sudo`。

## 一键执行

```bash
chmod +x install.sh update.sh uninstall.sh
./install.sh
```

## install.sh 会做什么

1. 创建独立运行目录 `runtime/`
2. 写入 Nginx Proxy Manager 的 `compose.yaml`
3. 启动 NPM
4. 拉取 Xboard 官方 `compose` 分支
5. 准备 `.env`、SQLite 数据目录、日志目录等
6. 执行官方安装命令（SQLite + 内置 Redis）
7. 启动 Xboard
8. 自动尝试放行以下端口：
   - `80/tcp`
   - `443/tcp`
   - `81/tcp`
   - `7001/tcp`

支持的防火墙：

- `ufw`
- `firewalld`

如果系统没有检测到这两种防火墙工具，脚本会跳过放行步骤并给出提示。

## 默认端口

- NPM HTTP：`80`
- NPM HTTPS：`443`
- NPM 管理后台：`81`
- Xboard：`7001`

## 可选环境变量

如果你想改默认端口或管理员邮箱，可以这样执行：

```bash
NPM_ADMIN_PORT=8081 XBOARD_PORT=7002 XBOARD_ADMIN_EMAIL=you@example.com ./install.sh
```

支持的变量：

- `NPM_HTTP_PORT`
- `NPM_HTTPS_PORT`
- `NPM_ADMIN_PORT`
- `XBOARD_PORT`
- `XBOARD_ADMIN_EMAIL`
- `XBOARD_REPO`
- `XBOARD_BRANCH`
- `ENABLE_FIREWALL_OPEN`
- `FORCE_XBOARD_INSTALL`

### 变量说明

- `ENABLE_FIREWALL_OPEN=0`：跳过防火墙放行
- `FORCE_XBOARD_INSTALL=1`：即使检测到已有 SQLite 数据，也强制重新执行 Xboard 安装流程

## 更新项目

```bash
./update.sh
```

会做的事：

- 更新 NPM 镜像
- 更新 Xboard compose 分支代码
- 重新拉取镜像并重建容器

## 卸载项目

只停止容器，保留数据：

```bash
./uninstall.sh
```

彻底删除运行目录和数据：

```bash
PURGE_DATA=1 ./uninstall.sh
```

## 部署完成后要做的事

### 1) 登录 NPM

默认后台地址：

```text
http://你的服务器IP:81
```

NPM 默认初始账号通常是：

```text
Email: admin@example.com
Password: changeme
```

首次登录后请立即修改。

### 2) 在 NPM 里添加反向代理

建议这样填：

- **Domain Names**: 你的面板域名，例如 `xboard.example.com`
- **Scheme**: `http`
- **Forward Hostname / IP**: 服务器 IP
- **Forward Port**: `7001`（如果你改过就填你自定义的端口）
- **Block Common Exploits**: 建议开启
- **Websockets Support**: 建议开启

最简单的转发方式：

```text
http://宿主机IP:7001
```

### 3) 证书

如果你的域名解析已经到服务器，且 80/443 端口通畅，就可以在 NPM 中申请 Let's Encrypt。

## 适合你的测试流程

如果你准备在服务器上直接测，建议：

```bash
git clone <你的仓库地址>
cd xboard-one-click
chmod +x install.sh update.sh uninstall.sh
./install.sh
```

## 参考来源

- Xboard 官方仓库：<https://github.com/cedar2025/Xboard>
- 参考文章：<https://naiyous.com/9014.html>

## 说明

保留了你原来想要的逻辑：

1. 先装 NPM
2. 再装 Xboard
3. 再去做反代

只是把实现方式换成了更可审计、也更适合长期维护的 Docker Compose 方案。
