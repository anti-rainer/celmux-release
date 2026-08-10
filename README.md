# Celmux

Celmux 的公开二进制发布入口。源码由维护者在私有仓库中管理，本仓库保留发布说明、静态安装/卸载脚本、安全策略和法律文件。

## 下载

历史版本和发布说明见 [Releases](https://github.com/anti-rainer/celmux-release/releases)。每个 Release 只包含两个无版本号二进制：

| 平台 | 文件 |
| --- | --- |
| Linux amd64 / x86_64 | `celmux_linux_amd64` |
| Linux arm64 / aarch64 | `celmux_linux_arm64` |

最新版本可直接下载：

- [celmux_linux_amd64](https://github.com/anti-rainer/celmux-release/releases/latest/download/celmux_linux_amd64)
- [celmux_linux_arm64](https://github.com/anti-rainer/celmux-release/releases/latest/download/celmux_linux_arm64)

下载后赋予执行权限，并指定配置文件运行：

```sh
chmod +x celmux_linux_amd64
./celmux_linux_amd64 -c /path/to/celmux.yaml
```

ARM64 主机将文件名替换为 `celmux_linux_arm64`。

## 一键安装

支持 Linux `amd64`、`arm64`，以及 systemd、OpenRC、OpenWrt 25.12+ procd、SysVinit 和 Android root service.d。默认安装路径为 `/opt/celmux`。安装器直连 GitHub Release API 获取版本和 SHA-256，下载二进制时默认先尝试 `gh-proxy.org`，失败后自动回退 GitHub 直连，并写入对应系统的服务入口。安装脚本是本仓库维护的静态文件，不属于 Release 资产。

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh
```

安装指定版本：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh -s -- --version 0.0.2
```

OpenWrt 25.12+ 请使用 root shell 执行（系统通常只有 BusyBox `sh`，不需要 `sudo`）：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sh
```

OpenWrt 安装器会生成 `/etc/init.d/celmux`，通过 procd 管理自启动、崩溃重启和日志；运行目录为安装目录（默认 `/opt/celmux`），因此 `data/`、`logs/` 等相对路径可正常工作。服务常用命令：

```sh
/etc/init.d/celmux status
/etc/init.d/celmux restart
logread -e celmux -f
```

可设置 `CELMUX_GITHUB_ACCELERATOR=` 禁用二进制下载加速。首次启动由二进制创建 `celmux.yaml`；同目录存在旧 `config.yaml` 时，只导入支持的可见配置。全新安装完成时，脚本会显示安装路径、`http://0.0.0.0:7575`、`admin` 和初始密码 `admin`；已有配置时密码沿用原值，不会被脚本覆盖或回显。

## 一键卸载

普通卸载会停止并移除 Celmux 服务和二进制，保留配置、数据库和日志：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh
```

确认删除 `/opt/celmux` 下全部配置和数据：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh -s -- --purge --yes
```

OpenWrt root shell 的卸载命令（普通卸载或彻底清理）不需要 `sudo`：

```sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sh
curl -fsSL https://gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sh -s -- --purge --yes
```

## 发布标签

新发布使用数字 `X.Y.Z` 标签；发布仓库只在 Release 中保存两个二进制资产，安装/卸载脚本和文档由本仓库分支单独维护。

## 安全与许可

请勿在公开 issue 中提交凭据或未经脱敏的日志。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

原 VoHive 部分版权归 `iniwex5`；Celmux 新增和修改部分版权归 `anti-rainer`。

使用前请阅读 [DISCLAIMER.md](DISCLAIMER.md)、[LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
