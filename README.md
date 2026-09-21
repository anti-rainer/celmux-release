# Celmux

## 安装（Linux）

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh
```

## 卸载（Linux）

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh
```

## 安装（Windows）

在一个准备用作运行目录的文件夹里打开 PowerShell，执行：

```powershell
curl.exe -fsSL -o install.ps1 https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

脚本把当前目录作为运行目录：

下载完成后 `install.ps1` 会先把这个可执行文件的 SHA-256 与本次发布的
`SHA256SUMS.txt` 比对（旧发布没有这个文件时改用 GitHub 记录的资产摘要），
不一致就直接中止并删除文件。桌面端的 `celmux_win_amd64_desktop.exe` 可以
用同样的清单手工核对：

```powershell
certutil -hashfile celmux_win_amd64_desktop.exe SHA256
```

校验和只证明"下载到的就是这次发布上传的文件"，并不等于 Windows 的
Authenticode 签名——本项目没有付费代码签名证书，所以安装时仍会显示未知
发布者。

```text
运行目录/
├── bin/
│   └── celmux.exe                  服务端
├── config/
│   └── celmux.yaml                 首次启动生成，含随机 web 密码
├── data/
├── driver/
│   ├── celmux-qmi.inf
│   ├── install-qmi-binding.ps1
│   └── uninstall-qmi-binding.ps1
├── logs/
│   └── app.log
├── install-driver.bat              绑定模组的 QMI 功能到 WinUSB
├── start.bat
├── stop.bat
└── restart.bat
```

网页界面在 `https://127.0.0.1:7575`。模组的 QMI 功能若尚未绑定到 WinUSB，双击
`install-driver.bat` 即可（现场自签证书，不需要证书机构或 Windows SDK），撤销绑定用
`driver\uninstall-qmi-binding.ps1`。脚本与驱动资源来自
[`anti-rainer/celmux`](https://github.com/anti-rainer/celmux)，服务端二进制取本仓库的最新
Release。
