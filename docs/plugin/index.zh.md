# 插件

Celmux 插件开发。

## 结构

```json
{
  "id": "demo",
  "name": "Demo",
  "version": "1.0.0",
  "description": "插件卡片上的一行说明",
  "repository": "owner/name",
  "settings": [],
  "permissions": ["lines_read", "calls_control"]
}
```

```
celmux-plugin-<id>/
  celmux-plugin-<id>
  plugin.json
  ui/
    index.html
```

### 字段

#### id

必填。稳定标识，同时是插件根目录下的目录名与 API 路径。

小写字母、数字、连字符。

可执行文件名由它推导：

```rust
format!("celmux-plugin-{}", record.id)
```

#### name

必填。显示名称。

#### version

必填。语义化版本，用于检查更新。

#### description

插件卡片上的一行说明。

#### repository

发布仓库的 `owner/name`，用于检查更新。

为空表示从文件安装，没有可查询的来源。

#### settings

配置表单字段。空数组表示无需配置。

#### permissions

申请的权限。是请求而非授权：安装时由操作者批准，只有被授予的部分生效。

## 配置项

### 结构

```json
{
  "key": "port",
  "label": "监听端口",
  "kind": "number",
  "default": "43769",
  "hint": "显示在字段下方"
}
```

### 字段

#### key

必填。环境变量名来源，转大写并加 `CELMUX_PLUGIN_` 前缀。

#### label

必填。字段标签。

#### kind

`string`、`number`、`boolean` 或 `secret`。默认 `string`。

#### default

默认值。

#### hint

显示在字段下方的说明。

## 权限

只能申请下表列出的权限。

| 权限 | 说明 | 敏感 |
| --- | --- | --- |
| `lines_read` | 读取线路列表 | |
| `calls_read` | 读取通话状态与记录 | |
| `calls_control` | 拨号、接听、拒接、挂断 | |
| `media_audio` | 获取与写入通话音频 | 是 |
| `auto_answer` | 设置线路自动接听 | 是 |
| `sms_read` | 读取会话 | |
| `sms_send` | 发送短信 | |
| `devices_read` | 读取设备与卡片清单 | |
| `devices_add` | 添加设备或卡片 | 是 |
| `devices_remove` | 删除设备或卡片 | 是 |
| `sip_manage` | 管理 SIP 账户 | 是 |
| `system_read` | 读取系统状态与流量 | |

安装时与已有授权合并，再保留新清单仍然申请的项。

## 环境变量

| 变量 | 说明 |
| --- | --- |
| `CELMUX_PLUGIN_ID` | 插件 id |
| `CELMUX_PLUGIN_VERSION` | 插件版本 |
| `CELMUX_PLUGIN_CELMUX_URL` | Celmux 地址，如 `http://127.0.0.1:8080` |
| `CELMUX_PLUGIN_CELMUX_TOKEN` | 鉴权令牌 |
| `CELMUX_PLUGIN_AUDIO_URL` | 音频 socket，如 `tcp://127.0.0.1:8081` |
| `CELMUX_PLUGIN_<KEY>` | 每个 `settings[].key` 转大写后的值 |

令牌每次启动轮换，只保存哈希。

## 鉴权

```http
Authorization: Bearer <CELMUX_PLUGIN_CELMUX_TOKEN>
```

插件不存在与令牌错误返回相同响应：

```json
{
  "status": "error",
  "code": "unauthorized",
  "message": "插件令牌无效"
}
```

## 接口

前缀 `/api/plugin-api/<id>/<action>`。在会话校验之前处理。

### 配置

| 方法 | 动作 | 权限 |
| --- | --- | --- |
| `GET` | `config` | |
| `PUT` | `config` | |
| `POST` | `config` | |

### 事件

| 方法 | 动作 | 权限 |
| --- | --- | --- |
| `GET` | `events` | `lines_read` |
| `GET` | `events/once` | `lines_read` |

`events` 是长连接 SSE 流，`events/once` 供刚启动的插件取一次快照。

### 资源

| 方法 | 动作 | 权限 |
| --- | --- | --- |
| `GET` | `lines` | `lines_read` |
| `GET` | `devices` | `devices_read` |
| `GET` | `calls` | `calls_read` |
| `GET` | `sms` | `sms_read` |
| `POST` | `sms` | `sms_send` |
| `POST` | `auto-answer` | `auto_answer` |

### 通话

| 方法 | 动作 | 权限 |
| --- | --- | --- |
| `POST` | `dial` | `calls_control` |
| `POST` | `answer` | `calls_control` |
| `POST` | `hangup` | `calls_control` |
| `POST` | `reject` | `calls_control` |
| `POST` | `dtmf` | `calls_control` |

缺少权限：

```json
{
  "status": "error",
  "code": "permission_denied",
  "message": "插件缺少控制通话（拨号/接听/挂断）权限",
  "required": "calls_control"
}
```

### DTMF

```json
{
  "call_id": "12",
  "digits": "5"
}
```

#### call_id

必填。通话 id，十进制字符串。

#### digits

必填。`0-9`、`*`、`#`、`A-D`。1 到 32 个字符。

是序列而非单键：IMS 路径从一次请求播放多个 RFC 4733 事件。

`digit`（单数）属于客户端到插件这一层，不属于本接口。

#### duration_ms

音长，40 到 2000。默认 200。

#### gap_ms

音间隔，0 到 2000。默认 100。

响应：`202 Accepted`。

## 安装

### 目录

放入 `<安装根>/plugin/`。

### 上传

```http
POST /api/plugins/install-from-upload
```

请求体是归档本身，不是 JSON。

### 插件中心

插件中心读取已登记仓库的最新 release，按运行平台选择资产。

| 平台 | 资产名 |
| --- | --- |
| Linux aarch64 | 含 `aarch64`，以 `.tar.gz` 结尾 |
| Linux x86_64 | 含 `x86_64`，以 `.tar.gz` 结尾 |
| Windows | 含 `win_amd64`，以 `.zip` 结尾 |

平台与归档格式都是匹配条件：只匹配架构会在 Windows 上选中 Linux 二进制，安装成功但无法运行。

### 行为

| 行为 | 说明 |
| --- | --- |
| 令牌 | 在安装响应中返回一次 |
| 重装 | 保留配置与原始安装时间 |
| 权限 | 与已有授权合并，再按新清单过滤 |
| 重启 | 重启插件，使进程取得轮换后的令牌 |

## 进程

| 行为 | 值 |
| --- | --- |
| 退出后重启 | 是，指数退避从 2 秒起，上限 60 秒 |
| 崩溃窗口 | 120 秒 |
| 窗口内重启次数 | 5 |
| 超限后 | 停止重试，记录错误 |
| 停止宽限 | 5 秒 |

`enabled` 是存储标记，不反映进程是否运行。插件列表携带 `running`、`pid`、`restarts`、`last_error`。

`exec` 之前会补上执行位。仅 Linux。

## 日志

```
<安装根>/plugin/<id>/logs/supervisor.log
```

`spawn` 失败会给出绝对路径与错误类型：`No such file or directory` 通常表示缺少执行位或架构不符，而不是文件不存在。

## 示例

[celmux-plugin-airsim](https://github.com/anti-rainer/celmux-plugin-airsim)
