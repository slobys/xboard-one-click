# xboard-one-click

一键部署 **Xboard + Nginx Proxy Manager**。

默认方案：
- Xboard 使用官方 `compose` 分支
- 默认 SQLite + 内置 Redis
- NPM 使用 Docker Compose 部署
- 支持自定义端口
- Debian/Ubuntu 可自动安装 Docker 相关依赖
- 自动识别服务器 IP
- 自动放行防火墙端口（`ufw` / `firewalld`）

## 快速开始

```bash
git clone https://github.com/slobys/xboard-one-click.git
cd xboard-one-click
chmod +x install.sh update.sh uninstall.sh
./install.sh --interactive
```

推荐直接用交互模式，脚本会询问：
- NPM HTTP 端口
- NPM HTTPS 端口
- NPM 管理后台端口
- Xboard 对外端口
- Xboard 管理员邮箱

## 安装完成后你会拿到

脚本会直接输出：
- `Xboard 首页`
- `Xboard 管理面板`
- `NPM 管理后台`

**注意：Xboard 后台不是根路径。**
请打开脚本输出的 **`Xboard 管理面板`** 链接，不要只访问 `/`。

## 常用方式

### 1) 交互式安装

```bash
./install.sh --interactive
```

### 2) 用 `deploy.env` 固定配置

```bash
cp deploy.env.example deploy.env
nano deploy.env
./install.sh
```

### 3) 临时环境变量

```bash
NPM_ADMIN_PORT=20881 XBOARD_PORT=27001 XBOARD_ADMIN_EMAIL=you@example.com ./install.sh
```

配置优先级：

```text
shell 环境变量 > deploy.env > 脚本默认值
```

## 推荐端口策略

建议保留：
- `80` 给 NPM HTTP
- `443` 给 NPM HTTPS

更建议自定义：
- `NPM_ADMIN_PORT`
- `XBOARD_PORT`

## 关键环境变量

- `NPM_HTTP_PORT`
- `NPM_HTTPS_PORT`
- `NPM_ADMIN_PORT`
- `XBOARD_PORT`
- `XBOARD_ADMIN_EMAIL`
- `ENABLE_FIREWALL_OPEN`
- `FORCE_XBOARD_INSTALL`
- `AUTO_INSTALL_DEPS`
- `SERVER_IP`

常用示例：

```bash
FORCE_XBOARD_INSTALL=1 ./install.sh --interactive
SERVER_IP=1.2.3.4 ./install.sh --interactive
AUTO_INSTALL_DEPS=0 ./install.sh --interactive
```

## 脚本会做什么

`install.sh` 会自动完成：
- 安装缺失依赖（Debian/Ubuntu，默认开启）
- 部署 NPM
- 拉取并部署 Xboard
- 等待内置 Redis 就绪后执行安装
- 自动放行对应端口
- 自动生成 `npm-proxy-template.txt`
- 输出真实访问地址和后台路径

另外，脚本会额外输出一次：

```bash
docker compose port xboard 7001
```

用来确认 **Xboard 实际映射到哪个宿主机端口**。

## NPM 反代怎么填

安装完成后直接看：

```bash
cat npm-proxy-template.txt
```

最关键的是：
- `Scheme`: `http`
- `Forward Hostname / IP`: 服务器 IP
- `Forward Port`: 你设置的 `XBOARD_PORT`

反代完成后，Xboard 后台仍然要访问：

```text
https://你的域名/安全路径
```

不是只打开域名根路径。

## 更新

```bash
./update.sh
```

## 卸载

停止容器，保留数据：

```bash
./uninstall.sh
```

彻底删除运行目录和数据：

```bash
PURGE_DATA=1 ./uninstall.sh
```

## 常见问题

### 1) 打不开 Xboard 后台
先确认你访问的是脚本输出的：
- `Xboard 管理面板`

不要只访问：
- `http://IP:XBOARD_PORT/`

### 2) 自定义端口后打不开
检查真实映射：

```bash
cd ~/xboard-one-click/runtime/Xboard
docker compose port xboard 7001
docker compose ps
```

### 3) NPM 配好了但域名 404
大多数情况是：
- 反代通了
- 但访问的不是 Xboard 后台安全路径

应该访问：

```text
https://你的域名/安全路径
```

## 文件结构

```text
xboard-one-click/
├── install.sh
├── update.sh
├── uninstall.sh
├── deploy.env.example
├── README.md
└── runtime/
```

## 参考

- Xboard: <https://github.com/cedar2025/Xboard>
- 参考文章: <https://naiyous.com/9014.html>
