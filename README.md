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

## 发布（GitHub Actions）

二进制由本仓库的 Actions 直接从私有源码仓库构建并发布，构建机不保留任何产物：

- `Actions -> release -> Run workflow`：填分支 / tag / commit，构建并发布一个 release；
- 或往本仓库推一个 tag，用同名 tag 构建发布。

工作流用环境密钥 `celmux_pat`（需可读 `anti-rainer/celmux`）拉源码，产出
`celmux_windows_amd64.exe`、`celmux_linux_amd64`、`celmux_linux_arm64` 与 `SHA256SUMS`，
Windows 桌面端能编出来时一并附上。两个安装脚本都取 `releases/latest`，所以发布一次就换掉了
新装用户拿到的版本。
