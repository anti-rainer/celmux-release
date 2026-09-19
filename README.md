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

脚本把当前目录作为运行目录，创建 `bin`/`config`/`data`/`logs`/`driver`：Windows 服务端
下载到 `bin\celmux.exe`，驱动资源放进 `driver\`，根目录生成 `start.bat`、`stop.bat`、
`restart.bat` 与 `install-driver.bat`。首次启动会写出 `config\celmux.yaml`（含随机 web 密码），
网页界面在 `https://127.0.0.1:7575`。

模组的 QMI 功能若尚未绑定到 WinUSB，双击根目录的 `install-driver.bat`：它请求一次管理员
授权，在提权窗口里自动识别模组的 QMI 功能、现场自签一张证书并完成绑定，不需要证书机构，
也不需要 Windows SDK。撤销绑定请以管理员运行 `driver\uninstall-qmi-binding.ps1`。

`install.ps1`、`install-driver.bat` 与 `driver\` 里的驱动资源来自 `anti-rainer/celmux` 的
`packaging/desktop/windows/`；服务端二进制来自本仓库的 Release 资产。
