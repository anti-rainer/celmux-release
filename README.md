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

脚本把当前目录作为运行目录，创建 `bin`/`config`/`data`/`logs`，下载 Windows 服务端到
`bin\celmux.exe`、驱动安装程序 `celmux-driver-installer.exe` 到根目录，并生成
`start.bat`、`stop.bat`、`restart.bat`。首次启动会写出 `config\celmux.yaml`（含随机 web 密码），
网页界面在 `https://127.0.0.1:7575`。

模组的 QMI 功能若尚未绑定到 WinUSB，双击根目录的 `celmux-driver-installer.exe`：它会显示
协议与影响说明，勾选同意后请求一次管理员授权，自动识别模组的 QMI 功能并完成绑定。
撤销绑定请以管理员运行 `uninstall-qmi-binding.ps1`。

`install.ps1` 与 `celmux-driver-installer.exe` 由 `anti-rainer/celmux` 的
`packaging/desktop/windows/` 发布到这里；二进制来自本仓库的 Release 资产。
