# xboard-one-click

![Platform](https://img.shields.io/badge/platform-Debian%20%2F%20Ubuntu-blue)
![Docker](https://img.shields.io/badge/docker-required-2496ED)
![License](https://img.shields.io/badge/license-MIT-green)

一键部署 **Xboard + Nginx Proxy Manager**，适合需要快速完成面板部署、端口自定义、域名反代与 HTTPS 配置的场景。

## 适合谁

适合希望尽量减少手动步骤的用户：
- 快速部署 Xboard
- 同时部署 Nginx Proxy Manager（NPM）
- 使用自定义端口
- 后续通过 NPM 配置域名和 HTTPS

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
chmod +x install.sh update.sh uninstall.sh menu.sh
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
- 更新 Xboard / NPM
- 启动 / 重启 / 停止 NPM
- 启动 / 重启 / 停止 Xboard
- 重启 xboard-node 节点
- 查看 NPM / Xboard 日志
- 放行当前配置端口或手动放行额外端口
- 查看访问信息与常用命令

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

## 适用环境

- Debian / Ubuntu
- 建议使用 `root` 或具备 `sudo` 权限的用户执行

## 相关项目

- Xboard: <https://github.com/cedar2025/Xboard>
