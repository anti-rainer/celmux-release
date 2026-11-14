# Plugin

Plugin development for Celmux.

## Structure

```json
{
  "id": "demo",
  "name": "Demo",
  "version": "1.0.0",
  "description": "One line for the plugin card",
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

### Fields

#### id

Required. Stable identifier, also the directory name under the plugin root and the API path.

Lowercase letters, digits and hyphens.

The executable name is derived from it:

```rust
format!("celmux-plugin-{}", record.id)
```

#### name

Required. Display name.

#### version

Required. Semantic version, used for the update check.

#### description

One line for the plugin card.

#### repository

`owner/name` of the releasing repository, used to check for updates.

Empty means installed from a file, which leaves no place to look for a newer one.

#### settings

Configuration form fields. An empty array means the plugin has none.

#### permissions

Requested permissions. A request, not a grant: the operator approves the set at install time and only the granted set is enforced.

## Setting

### Structure

```json
{
  "key": "port",
  "label": "Listen port",
  "kind": "number",
  "default": "43769",
  "hint": "Shown under the field"
}
```

### Fields

#### key

Required. Source of the environment variable name; uppercased and prefixed with `CELMUX_PLUGIN_`.

#### label

Required. Field label.

#### kind

`string`, `number`, `boolean` or `secret`. Default `string`.

#### default

Default value.

#### hint

Text shown under the field.

## Permission

Only the permissions in this table can be requested.

| Permission | Description | Sensitive |
| --- | --- | --- |
| `lines_read` | Read the line list | |
| `calls_read` | Read call state and history | |
| `calls_control` | Place, answer, reject and hang up calls | |
| `media_audio` | Take and write call audio | Yes |
| `auto_answer` | Set a line's automatic answering | Yes |
| `sms_read` | Read conversations | |
| `sms_send` | Send SMS | |
| `devices_read` | Read device and card inventory | |
| `devices_add` | Add a device or card | Yes |
| `devices_remove` | Remove a device or card | Yes |
| `sip_manage` | Manage SIP accounts | Yes |
| `system_read` | Read system status and traffic | |

Installation merges with the previous grant, then keeps only what the new manifest still requests.

## Environment

| Variable | Description |
| --- | --- |
| `CELMUX_PLUGIN_ID` | Plugin id |
| `CELMUX_PLUGIN_VERSION` | Plugin version |
| `CELMUX_PLUGIN_CELMUX_URL` | Celmux address, e.g. `http://127.0.0.1:8080` |
| `CELMUX_PLUGIN_CELMUX_TOKEN` | Bearer token |
| `CELMUX_PLUGIN_AUDIO_URL` | Audio socket, e.g. `tcp://127.0.0.1:8081` |
| `CELMUX_PLUGIN_<KEY>` | Value of each `settings[].key`, uppercased |

The token is rotated on every launch and only its hash is stored.

## Authorization

```http
Authorization: Bearer <CELMUX_PLUGIN_CELMUX_TOKEN>
```

An unknown plugin and a wrong token answer identically:

```json
{
  "status": "error",
  "code": "unauthorized",
  "message": "插件令牌无效"
}
```

## API

Prefix: `/api/plugin-api/<id>/<action>`. Answered before the session gate.

### Configuration

| Method | Action | Permission |
| --- | --- | --- |
| `GET` | `config` | |
| `PUT` | `config` | |
| `POST` | `config` | |

### Events

| Method | Action | Permission |
| --- | --- | --- |
| `GET` | `events` | `lines_read` |
| `GET` | `events/once` | `lines_read` |

`events` is a long-lived SSE stream. `events/once` is a snapshot for a plugin that just started.

### Resources

| Method | Action | Permission |
| --- | --- | --- |
| `GET` | `lines` | `lines_read` |
| `GET` | `devices` | `devices_read` |
| `GET` | `calls` | `calls_read` |
| `GET` | `sms` | `sms_read` |
| `POST` | `sms` | `sms_send` |
| `POST` | `auto-answer` | `auto_answer` |

### Call

| Method | Action | Permission |
| --- | --- | --- |
| `POST` | `dial` | `calls_control` |
| `POST` | `answer` | `calls_control` |
| `POST` | `hangup` | `calls_control` |
| `POST` | `reject` | `calls_control` |
| `POST` | `dtmf` | `calls_control` |

Missing permission:

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

Required. Call id, decimal string.

#### digits

Required. `0-9`, `*`, `#`, `A-D`. 1 to 32 characters.

A sequence, not one key: the IMS path plays multiple RFC 4733 events from one request.

`digit` (singular) belongs to the client-to-plugin layer, not to this API.

#### duration_ms

Tone length, 40 to 2000. Default 200.

#### gap_ms

Gap between tones, 0 to 2000. Default 100.

Answer: `202 Accepted`.

## Install

### Directory

Place the directory under `<installation root>/plugin/`.

### Upload

```http
POST /api/plugins/install-from-upload
```

Body is the archive itself, not JSON.

### Catalog

The catalog reads the latest release of the registered repository and selects the asset for the running platform.

| Platform | Asset name |
| --- | --- |
| Linux aarch64 | Contains `aarch64`, ends with `.tar.gz` |
| Linux x86_64 | Contains `x86_64`, ends with `.tar.gz` |
| Windows | Contains `win_amd64`, ends with `.zip` |

Both the platform and the archive format are matched: architecture alone selects a Linux binary on Windows, which installs and then fails to run.

### Result

| Behaviour | Detail |
| --- | --- |
| Token | Returned in the install response, once |
| Reinstall | Keeps the configuration and the original install time |
| Permissions | Merged with the previous grant, then filtered by the new manifest |
| Restart | Restarted so the process picks up the rotated token |

## Process

| Behaviour | Value |
| --- | --- |
| Restart on exit | Yes, exponential backoff from 2s, capped at 60s |
| Crash window | 120 seconds |
| Restarts within window | 5 |
| After the limit | Retries stop, the error is recorded |
| Stop grace | 5 seconds |

`enabled` is a stored flag and does not report whether the process is up. The plugin list carries `running`, `pid`, `restarts` and `last_error`.

The executable bit is set before `exec` if the archive did not carry it. Linux only.

## Log

```
<installation root>/plugin/<id>/logs/supervisor.log
```

A `spawn` failure names the absolute path and the error kind: `No such file or directory` usually means a missing executable bit or a wrong architecture rather than an absent file.

## Example

[celmux-plugin-airsim](https://github.com/anti-rainer/celmux-plugin-airsim)
