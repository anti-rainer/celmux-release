# Celmux

面向高通 4G/LTE/5G 模组（Quectel EC20/EC25/EC21/EG25/EM20 等）的综合管理与代理服务平台。

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm--Noncommercial--1.0.0-blue.svg)](https://polyformproject.org/licenses/noncommercial/1.0.0)
[![Rust](https://img.shields.io/badge/Rust-1.97.1-000000?logo=rust)](https://github.com/anti-rainer/celmux)
[![Vue 3](https://img.shields.io/badge/Vue-3-42b883?logo=vue.js)](https://github.com/anti-rainer/celmux)

## 文档

| 文档 | |
| --- | --- |
| [插件开发](docs/plugin/index.zh.md) | [Plugin](docs/plugin/index.md) |
| [免责声明](DISCLAIMER.md) | [安全策略](SECURITY.md) |
| [第三方声明](THIRD_PARTY_NOTICES.md) | [许可证](LICENSE) |

## 安装

### Linux

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh
```

卸载：

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh
```

### Windows

在一个准备用作运行目录的文件夹里打开 PowerShell，执行：

```powershell
curl.exe -fsSL -o install.ps1 https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

### Windows 桌面端

在 [Releases](../../releases) 中下载带 `desktop` 的 exe 安装。

安装后第一步：在软件的系统设置里点击安装驱动。

该驱动将模组的 qmi 接口绑定到 winusb，供软件使用 qmi 功能。此驱动不具备 AT 接口绑定能力，如需 AT 操作，请安装移远官方驱动。

## License

PolyForm Noncommercial License 1.0.0，详见 [LICENSE](LICENSE)。
