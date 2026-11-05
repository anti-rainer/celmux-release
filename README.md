# Celmux

## 安装（Linux服务端）

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.sh | sudo sh
```

## 卸载（Linux服务端）

```sh
curl -fsSL https://v6.gh-proxy.org/https://raw.githubusercontent.com/anti-rainer/celmux-release/main/uninstall.sh | sudo sh
```

## 安装（Windows服务端）

在一个准备用作运行目录的文件夹里打开 PowerShell，执行：

```powershell
curl.exe -fsSL -o install.ps1 https://raw.githubusercontent.com/anti-rainer/celmux-release/main/install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

## 安装Windows桌面端

在release中下载带有desktop的exe文件进行安装
安装完成第一步是在软件的系统设置里点击安装驱动
此驱动功能是将模块的qmi接口绑定到winusb上，可供软件使用qmi功能，此驱动没有绑定AT接口的能力，如需AT操作能力，请安装移远官方驱动
