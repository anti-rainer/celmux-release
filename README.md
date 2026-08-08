# Celmux

Celmux 的公开二进制发布入口。源码由维护者在私有仓库中管理，本仓库分支只保留发布说明、安全策略和法律文件。

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

ARM64 主机将文件名替换为 `celmux_linux_arm64`。本仓库不提供安装、卸载或在线更新脚本。

## 发布标签

新发布使用 `release-*` 标签；后缀由维护者自行定义，不采用自动递增的语义版本号。

## 安全与许可

请勿在公开 issue 中提交凭据或未经脱敏的日志。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

原 VoHive 部分版权归 `iniwex5`；Celmux 新增和修改部分版权归 `anti-rainer`。

使用前请阅读 [DISCLAIMER.md](DISCLAIMER.md)、[LICENSE](LICENSE)、[NOTICE.md](NOTICE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
