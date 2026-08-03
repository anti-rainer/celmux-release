# celmux

Celmux 的公开发布与部署入口。这里提供稳定版本、安装入口、升级说明和法律文件，不包含开发资料。

## 安装

以 root 执行以下命令。系统已有 `curl` 或 `wget` 均可，安装器会自动选择；支持 Debian/systemd 与 OpenWrt/procd。

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sh
```

普通 Debian 用户将末尾的 `sh` 改为 `sudo sh`；没有 `curl` 的 OpenWrt 可用 `wget -qO-` 替换前面的下载命令。

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

当前公开版本提供 `linux/amd64` 与 `linux/arm64` 架构包。具体版本的文件和校验值请以 [Releases](https://github.com/anti-rainer/celmux-release/releases) 页面为准。

## 安全与合规

请勿公开管理密码、SIM/eSIM 凭据、网络凭据、手机号或完整日志。短信、语音、网络接入及设备管理功能必须遵守所在地法律法规、运营商条款和设备许可条件。

使用前请阅读 [DISCLAIMER.md](DISCLAIMER.md)、[LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。安全问题请通过 GitHub 私密渠道提交。
