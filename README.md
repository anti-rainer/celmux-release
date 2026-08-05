# Celmux

Celmux 的公开发布与安装入口。

## 安装

支持 Linux amd64 和 arm64，适用于 Debian/systemd 与 OpenWrt/procd。安装时需要 `curl` 和 `sudo`。

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh
```

## 更新

重新执行安装命令即可更新到最新稳定版本。历史版本与发布说明见 [Releases](https://github.com/anti-rainer/celmux-release/releases)。

## 卸载

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh
```

## 安全与许可

请勿在公开 issue 中提交凭据或未经脱敏的日志。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

使用前请阅读 [DISCLAIMER.md](DISCLAIMER.md)、[LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
