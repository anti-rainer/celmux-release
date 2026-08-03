# celmux

Celmux 的公开发布与部署入口。这里提供稳定版本、安装入口、升级说明和法律文件，不包含开发资料。

## 安装

以 root 执行以下命令。安装前确保系统已有 `curl`；支持 Debian/systemd 与 OpenWrt/procd。缺少 `sha256sum` 或 `od` 时，安装器会按 amd64/arm64 下载固定版本并校验过的静态辅助工具到临时目录，不依赖目标机软件源。

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sh
```

普通 Debian 用户将末尾的 `sh` 改为 `sudo sh`。

固定版本安装：

```sh
CELMUX_VERSION=v0.0.1 sh install.sh
```

已有本地二进制时，可直接运行：

```sh
sh install-local.sh /path/to/celmux
```

## 更新与卸载

重新执行安装命令即可检查并安装最新稳定版本。卸载：

```sh
sh uninstall.sh
```

## 支持

每个 Release 只提供两个二进制资产：`linux/amd64` 与 `linux/arm64`。安装脚本、校验清单和法律文件保留在本仓库源码中，由安装器按版本读取。具体版本请以 [Releases](https://github.com/anti-rainer/celmux-release/releases) 页面为准，校验值见 [`sha256sums.txt`](sha256sums.txt)。

## 安全与合规

请勿公开管理密码、SIM/eSIM 凭据、网络凭据、手机号或完整日志。短信、语音、网络接入及设备管理功能必须遵守所在地法律法规、运营商条款和设备许可条件。

使用前请阅读 [DISCLAIMER.md](DISCLAIMER.md)、[LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。安全问题请通过 GitHub 私密渠道提交。
