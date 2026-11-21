# OmniBox Desktop（Flutter + Rust FFI 版）

桌面端：Flutter（仅 Windows），播放器 media_kit；Rust 内核编译为 **cdylib**，由 Flutter 通过 `dart:ffi` 原生调用，**无 HTTP 服务、无网页面板、无 Rust 子进程**。

> 服务器版 `/workspace/filmbox` 保持不动。本项目是独立的新工程。

## 目录结构

```
omnibox-desktop/
├── rust_core/                  Rust cdylib（无 axum）
│   ├── Cargo.toml              crate-type = ["cdylib"]
│   ├── src/lib.rs              FFI 入口 + dispatch 表
│   └── src/{vod,spider,registry,node,history,douban,img,cache}.rs
└── flutter_app/                Flutter Windows 工程
    ├── lib/ffi_client.dart     Dart FFI 绑定（Isolate.spawn 异步化，等价 compute）
    ├── lib/app_core.dart       Api 单例 / Vod 模型 / NetImage(FFI 取图)
    ├── lib/main.dart           底部导航主壳（首页/搜索/历史/源管理）
    ├── lib/pages/              5 个页面：home/search/detail(播放)/history/spiders
    ├── lib/player/media_player.dart       播放器占位实现（默认，保证可编译）
    ├── lib/player/media_player_mpv.dart.txt  media_kit 版（启用时去 .txt，见环境要求）
    └── bin/verify*.dart        命令行验证脚本
```

## ⚠️ 环境要求（重要）

| 组件 | 要求 | 说明 |
|---|---|---|
| Flutter | **≥ 3.7** | media_kit_video 硬要求；本沙箱是 Flutter 3.0，故 media_kit 依赖默认注释 |
| Rust | 1.70+ | 编译 cdylib |
| Node.js | 18+（可选） | 仅 node 运行时脚本需要，多路径探测复用系统已装 Node |

**启用 media_kit**（目标环境 Flutter ≥3.7，三步）：
1. `flutter_app/pubspec.yaml` 取消这两行注释并 `flutter pub get`：
   ```yaml
     media_kit: ^1.2.6
     media_kit_video: ^2.0.1
   ```
2. 把 `lib/player/media_player_mpv.dart.txt` 改名为 `media_player_mpv.dart`（去掉 `.txt`）。
3. 把 `lib/pages/detail.dart` 的 `import '../player/media_player.dart';` 改为 `import '../player/media_player_mpv.dart';`。

两个文件都导出同名 `MpvPlayer`、接口一致，切换只改 import 一行。默认占位版保证 Flutter 3.0 环境 `dart analyze` 零 error；media_kit 版按标准 API 编写，待目标环境启用。

## FFI 契约

| 导出函数 | 签名 | 说明 |
|---|---|---|
| `ob_init` | `(data_dir, admin_token) -> i32` | 初始化数据目录/口令，须最先调用 |
| `ob_hello` | `() -> *mut c_char` | 连通性测试 |
| `ob_call` | `(method, params_json) -> *mut c_char` | 通用 RPC，返回 JSON 字符串 |
| `ob_img` | `(url, *out_len, *out_ctype) -> *mut u8` | 取图片字节（带防盗链 Referer） |
| `ob_free` / `ob_free_bytes` | `(ptr)` / `(ptr, len)` | 释放上述返回值（必须调用） |

`ob_call` methods：`health`、`douban_home`、`douban_category`、`search`、`detail`、`play`、`spiders_list`、`spiders_add`、`spiders_toggle`、`spiders_set_runtime`、`spiders_remove`、`spiders_source`、`spiders_test`、`history_list/add/remove/clear`。

## 关键技术点

1. **异步→同步**：Rust 常驻 4 线程 tokio runtime，`ob_call` 内 `block_on(async)`；Dart 侧 `Isolate.spawn + ReceivePort` 把阻塞 FFI 移出 UI 主线程（Dart 2.17 无 `Isolate.run`）。
2. **内存**：Rust `CString::into_raw` / `Box::into_raw` 分配，Dart 复制后调 `ob_free`/`ob_free_bytes`；`catch_unwind` 兜 panic 不跨 FFI 边界。
3. **播放**：media_kit 原生 header，`play()` 返回 `{url, header}` → `Media(url, httpHeaders: header)`；个别 m3u8 分片丢 header 时可加极简本地流代理兜底。
4. **图片**：`ob_img` 返回裸字节 + MIME，Flutter `Image.memory`；豆瓣自动带 `m.douban.com` Referer，内网地址拦截。
5. **Node 多路径探测**：`PATH(where/which)` → 注册表 `SOFTWARE\Node.js\InstallPath` → `Program Files` → `LOCALAPPDATA\Programs\nodejs` → nvm，绕过 GUI 进程 PATH 快照滞后。
6. **数据目录**：Windows `%APPDATA%\omnibox\data`，其它 `./data`；由 `main()` 调 `ob_init` 设置，脚本/历史/node_modules 都在其中。

## 验证结果（Linux 上以 .so 验证，机制与 Windows .dll 一致）

```
ob_init / ob_hello / health          => OK（engines: quickjs+node v22.13.1）
导入如意脚本(quickjs) + search 西游记 => 20 条真实结果, ~2s
douban_home                          => banners=5, movies=20（首部"可能的爱"）
ob_img(百度logo.png)                  => 6617 字节 PNG, magic 正确, ctype=image/png
history add/list/clear               => OK
Isolate.spawn 反复调用 FFI           => 8+ 次无崩溃，指针释放正常
Flutter dart analyze                 => 除 media_player.dart(环境缺包) 外 0 error
```

**结论**：Dart ↔ Rust cdylib FFI 全链路（含异步隔离、图片字节、豆瓣、脚本搜索、历史、内存释放）验证通过；media_kit 播放代码按标准 API 编写，待目标环境编译。

## CI 自动构建（GitHub Actions，推荐）

拆成**两个 workflow**，产物走 **Release** 中转（不提交二进制进 git）：

```
build-rust.yml  ──编译──▶ omnibox_core.dll ──发布到 Release tag: core-latest
                                                      │
build-flutter.yml ─ workflow_run 自动触发 ─▶ 下载 DLL ─▶ 启用 media_kit ─▶ flutter build windows
                                                      └─▶ 打包 omnibox-windows-x64.zip ─▶ Release tag: app-latest
```

| workflow | 触发 | 产物 |
|---|---|---|
| `.github/workflows/build-rust.yml` | 手动 / push 到 `rust_core/**` | DLL artifact + Release `core-latest` |
| `.github/workflows/build-flutter.yml` | Rust 构建成功后自动 / 手动 | 完整 zip artifact + Release `app-latest` |

- `build-flutter` 产物目录内的 `omnibox_core.dll` 已放到 `omnibox_app.exe` 同目录，FFI 开箱即用。
- CI 用 Flutter `3.24.5`（在 workflow env 里可改），自动放宽 Dart SDK 约束并切换 mpv 播放器，无需本地改代码。
- 两个 Release 都是 `prerelease` + 固定 tag，重复构建覆盖同名资源，不会堆积。
- 首次使用：先手动跑 `build-rust`，成功后 `build-flutter` 会自动接着跑；也可直接分别手动触发。

## 本地手动构建（Windows，Flutter ≥3.7）

```bash
# 1) Rust DLL
cd rust_core && cargo build --release        # target/release/omnibox_core.dll
# 2) 复制到 Flutter 产物目录（exe 同目录）
cp target/release/omnibox_core.dll ../flutter_app/build/windows/x64/runner/Release/
# 3) 启用 media_kit（见"环境要求"）后
cd ../flutter_app && flutter pub get && flutter build windows
```

## 已知限制 / 后续

- 源管理目前支持「粘贴源码」导入；文件上传（file_picker）、URL 拉取界面可在后续补（Rust 侧 `spiders_add` 已支持源码导入）。
- media_kit 需 Flutter ≥3.7；本沙箱 3.0 无法本地编译播放页，属环境限制。
- Node 加密源（瓜子等）能否出片取决于网络出口 IP 是否被上游风控。
