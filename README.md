# xboard-one-click

一键部署 **Xboard + Nginx Proxy Manager**。

## 特性

- 基于 Xboard 官方 `compose` 分支
- 默认 SQLite + 内置 Redis
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
- NPM HTTP / HTTPS 端口
- NPM 管理后台端口
- Xboard 对外端口
- Xboard 管理员邮箱

## 安装完成后

脚本会输出：
- **Xboard 首页**
- **Xboard 管理面板**
- **NPM 管理后台**

> 注意：Xboard 后台不是根路径，请以脚本输出的 **Xboard 管理面板** 链接为准。

## NPM 反向代理

安装完成后会生成：

```bash
npm-proxy-template.txt
```

查看：

```bash
cat npm-proxy-template.txt
```

NPM 反代的核心参数：
- **Scheme**: `http`
- **Forward Hostname / IP**: 服务器 IP
- **Forward Port**: 你设置的 `XBOARD_PORT`

如果使用域名访问，Xboard 后台地址仍然是：

```text
https://你的域名/安全路径
```

而不是只访问域名根路径。

## 常用命令

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

### 打不开 Xboard 后台
请确认访问的是脚本输出的 **Xboard 管理面板** 地址，而不是：

```text
http://IP:XBOARD_PORT/
```

### 自定义端口后无法访问
执行：

```bash
cd ~/xboard-one-click/runtime/Xboard
docker compose port xboard 7001
docker compose ps
```

### 域名访问返回 404
通常表示反代已通，但访问的不是后台安全路径。

正确方式：

```text
https://你的域名/安全路径
```

## 适用环境

- Debian / Ubuntu
- 建议使用 `root` 或具备 `sudo` 权限的用户执行

## 相关项目

- Xboard: <https://github.com/cedar2025/Xboard>
