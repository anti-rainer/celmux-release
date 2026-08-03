# 第三方版权与许可证

Celmux 的发布二进制由多个模块、嵌入资源和前端依赖组成。以下是直接集成或随二进制分发的主要组件索引；每项的原始许可证文本仍以对应路径为准。

| 组件 | 来源/版本 | 许可证 | 随源文件位置 |
| --- | --- | --- | --- |
| VoHive 原始部分 | `iniwex5/vohive` 派生代码 | PolyForm Noncommercial 1.0.0 | `LICENSE`、`NOTICE.md` |
| `qmi-go` | `iniwex5/qmi-go` 的维护分支 | MIT | `../qmi-go/LICENSE`、`../qmi-go/NOTICE.md` |
| `sipgo` | `emiago/sipgo` 的维护分支 | BSD 2-Clause | `../sipgo/LICENSE`、`../sipgo/NOTICE.md` |
| `euicc-go` | `damonto/euicc-go` | MIT | `third_party/euicc-go/LICENSE` |
| `uicc-go` | `damonto/uicc-go` | MIT | `third_party/uicc-go/LICENSE` |
| `netlink` | `vishvananda/netlink` 维护分支 | Apache-2.0 | `third_party/netlink/LICENSE` |
| `qqbot` | 嵌入的 QQ Bot 库 | Apache-2.0 | `third_party/qqbot/LICENSE` |
| PC/SC Lite 客户端代码 | `pcsc-lite` 相关源文件 | BSD 风格多版权声明 | `third_party/pcsc-lite-COPYING` |
| AMR-NB/AMR-WB WASM | OpenCORE、VisualOn 等 | Apache-2.0 及上游通知 | `web/public/codecs/LICENSE-APACHE-2.0.txt`、`web/public/codecs/NOTICE.txt` |
| Swagger UI | SmartBear Software | Apache-2.0 | `internal/api/docs_assets/swagger-ui/LICENSE`、`NOTICE` |
| 前端生产依赖 | `web/package-lock.json` 中锁定的 npm 包 | 以各包许可证为准 | 构建产物附带的 `.LICENSE.txt` 与上游包元数据 |

主项目自身的新增和修改部分不改变上述许可证，也不删除任何原始版权或免责声明。构建时使用的 Go 模块和 npm 包可能包含更多传递依赖；发布包中的本文件是索引，不替代这些依赖各自的完整许可证文本。

如果需要对二进制进行再分发，请同时保留本文件、`LICENSE`、`NOTICE.md`、`DISCLAIMER.md` 以及所需的第三方许可证文本。
