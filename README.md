# xboard-one-click

Xboard 一键部署脚本项目，默认走稳妥方案：

- **Nginx Proxy Manager 使用 Docker Compose 部署**
- **Xboard 使用官方 compose 分支部署**
- **Xboard 默认使用 SQLite + 内置 Redis**
- **安装脚本自动尝试放行对应防火墙端口**
- **Debian/Ubuntu 上缺失 Docker 时可自动安装依赖**
- **自动识别服务器公网 IP，并用于访问入口与反代模板展示**
- **端口支持自定义，并可持久化到本地 `deploy.env`**
- **安装完成后自动打印 NPM 反代填写模板，并写入 `npm-proxy-template.txt`**
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
├── deploy.env.example
├── install.sh
├── update.sh
├── uninstall.sh
├── README.md
├── npm-proxy-template.txt   # 安装后生成
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

> 如果是 Debian/Ubuntu，且你使用 `root`（或可用 `sudo` 的用户）执行，脚本会在 `AUTO_INSTALL_DEPS=1` 时自动安装缺失依赖，比如 Docker。

如果你希望脚本自动放行防火墙端口，建议用 `root` 执行，或确保当前用户可用 `sudo`。

## 推荐用法：先定好端口

### 方式 1：交互式配置（推荐）

```bash
chmod +x install.sh update.sh uninstall.sh
./install.sh --interactive
```

脚本启动后会先提示：如果当前是 Debian/Ubuntu，且缺少 Docker 等依赖，会自动尝试安装。
同时会优先自动识别服务器公网 IP；如果识别不到，则回退到本机 IP。

脚本会询问：

- NPM HTTP 端口
- NPM HTTPS 端口
- NPM 管理后台端口
- Xboard 对外端口
- Xboard 管理员邮箱

然后自动保存到本地 `deploy.env`，后续更新时会继续沿用。

### 方式 2：先编辑 `deploy.env`

```bash
cp deploy.env.example deploy.env
nano deploy.env
./install.sh
```

示例：

```env
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=20881
XBOARD_PORT=27001
XBOARD_ADMIN_EMAIL=admin@example.com
```

### 方式 3：临时环境变量

```bash
NPM_ADMIN_PORT=20881 XBOARD_PORT=27001 XBOARD_ADMIN_EMAIL=you@example.com ./install.sh
```

## 配置优先级

```text
shell 环境变量 > deploy.env > 脚本默认值
```

如果你想手动指定展示 IP，也可以这样：

```bash
SERVER_IP=1.2.3.4 ./install.sh --interactive
```

## install.sh 会做什么

1. 加载 `deploy.env`（如果存在）
2. 写入或更新本地配置文件
3. 自动安装缺失依赖（Debian/Ubuntu，默认开启）
4. 创建独立运行目录 `runtime/`
5. 写入 Nginx Proxy Manager 的 `compose.yaml`
6. 启动 NPM
7. 拉取 Xboard 官方 `compose` 分支
8. 准备 `.env`、SQLite 数据目录、日志目录等
9. 执行官方安装命令（SQLite + 内置 Redis）
10. 启动 Xboard
11. 自动尝试放行以下端口：
    - `NPM_HTTP_PORT/tcp`
    - `NPM_HTTPS_PORT/tcp`
    - `NPM_ADMIN_PORT/tcp`
    - `XBOARD_PORT/tcp`
12. 自动按当前配置生成 NPM 反代模板：
    - 终端直接打印
    - 同时写入 `npm-proxy-template.txt`

支持的防火墙：

- `ufw`
- `firewalld`

如果系统没有检测到这两种防火墙工具，脚本会跳过放行步骤并给出提示。

## 默认端口

- NPM HTTP：`80`
- NPM HTTPS：`443`
- NPM 管理后台：`81`
- Xboard：`7001`

> 建议：`80/443` 通常保留给 NPM，真正建议自定义的是 **NPM 管理后台端口** 和 **Xboard 对外端口**。

## 可选环境变量

- `NPM_HTTP_PORT`
- `NPM_HTTPS_PORT`
- `NPM_ADMIN_PORT`
- `XBOARD_PORT`
- `XBOARD_ADMIN_EMAIL`
- `XBOARD_REPO`
- `XBOARD_BRANCH`
- `ENABLE_FIREWALL_OPEN`
- `FORCE_XBOARD_INSTALL`
- `INTERACTIVE_CONFIG`
- `AUTO_WRITE_DEPLOY_ENV`
- `AUTO_INSTALL_DEPS`
- `SERVER_IP`

### 变量说明

- `ENABLE_FIREWALL_OPEN=0`：跳过防火墙放行
- `FORCE_XBOARD_INSTALL=1`：即使检测到已有 SQLite 数据，也强制重新执行 Xboard 安装流程
- `INTERACTIVE_CONFIG=1`：效果等同于 `./install.sh --interactive`
- `AUTO_WRITE_DEPLOY_ENV=0`：不自动写入 `deploy.env`
- `AUTO_INSTALL_DEPS=0`：禁用自动安装依赖（默认开启）
- `SERVER_IP=1.2.3.4`：手动指定显示在访问入口和 NPM 模板中的服务器 IP

## 更新项目

```bash
./update.sh
```

会自动读取 `deploy.env`，然后：

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

后台地址会自动按识别到的 IP 显示，例如：

```text
http://自动识别出的服务器IP:你设置的NPM_ADMIN_PORT
```

NPM 默认初始账号通常是：

```text
Email: admin@example.com
Password: changeme
```

首次登录后请立即修改。

### 2) 在 NPM 里添加反向代理

安装完成后，脚本会直接打印一份模板，你也可以打开：

```bash
cat npm-proxy-template.txt
```

建议这样填：

- **Domain Names**: 你的面板域名，例如 `xboard.example.com`
- **Scheme**: `http`
- **Forward Hostname / IP**: 自动识别出的服务器 IP
- **Forward Port**: 你设置的 `XBOARD_PORT`
- **Block Common Exploits**: 建议开启
- **Websockets Support**: 建议开启

最简单的转发方式：

```text
http://宿主机IP:XBOARD_PORT
```

### 3) 证书

如果你的域名解析已经到服务器，且 80/443 端口通畅，就可以在 NPM 中申请 Let's Encrypt。

## 适合你的测试流程

```bash
git clone https://github.com/slobys/xboard-one-click.git
cd xboard-one-click
chmod +x install.sh update.sh uninstall.sh
./install.sh --interactive
```

## 关于“改端口是否更安全”

适度改端口是有帮助的，但它不是核心安全措施。真正更重要的是：

- 修改 NPM 默认账号密码
- 只开放必要端口
- 尽量使用 HTTPS
- 定期更新镜像和上游代码
- 把管理端口放在高位端口，避免长期默认暴露

## 参考来源

- Xboard 官方仓库：<https://github.com/cedar2025/Xboard>
- 参考文章：<https://naiyous.com/9014.html>

## 说明

保留了你原来想要的逻辑：

1. 先装 NPM
2. 再装 Xboard
3. 再去做反代

只是把实现方式换成了更可审计、也更适合长期维护的 Docker Compose 方案。
