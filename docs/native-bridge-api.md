# karing-HM native 桥接 API 契约

> 版本：v0.1 · 状态：设计稿（native 库待 OpenHarmony 交叉编译工具链就绪后实现）

## 背景

Karing 的 sing-box 核心由 Go 编写（[KaringX/sing-box](https://github.com/KaringX/sing-box)，魔改自 SagerNet/sing-box）。
HarmonyOS NEXT 不支持直接运行 Go 二进制，因此需要将核心交叉编译为 `.so`，
通过 N-API 暴露 C 接口，由 ArkTS 侧 `VpnBridge` 调用。

## 编译方案

- 目标：`libsingbox.so`（arm64-v8a / armeabi-v7a）
- 工具链：OpenHarmony NDK（`ohos-sdk/native` 下的 clang 交叉编译）
- 产物位置：`harmony/entry/libs/<abi>/libsingbox.so`
- 构建脚本：`scripts/build-core.sh`（待实现）

## C 接口契约（对应 ArkTS VpnBridge）

| ArkTS 方法 | C 符号 | 说明 |
|-----------|--------|------|
| `init(ctx)` | `int sb_init(const char* work_dir, const char* cache_dir)` | 初始化核心工作目录 |
| `connect(json)` | `int sb_start(const char* config_json, char** err)` | 启动核心，传入 sing-box 配置 JSON |
| `disconnect()` | `int sb_stop(void)` | 停止核心并释放隧道 |
| `getCoreVersion()` | `const char* sb_version(void)` | 返回核心版本号 |
| 状态回调 | `void sb_set_state_cb(void (*cb)(int state))` | 连接状态回调：0=断开 1=连接中 2=已连接 3=断开中 |
| 流量回调 | `void sb_set_traffic_cb(void (*cb)(long long up, long long down))` | 周期流量统计（每 500ms） |

## ArkTS 侧接口

见 `harmony/entry/src/main/ets/bridge/VpnBridge.ets`：
- `connect(configJson: string): Promise<boolean>`
- `disconnect(): Promise<boolean>`
- `getState(): VpnState`
- `getCoreVersion(): string`

## VPN 隧道方案

HarmonyOS NEXT 提供 `@ohos.net.vpnExtension`（VPN 扩展）能力，与 Android VpnService 对应：

1. 应用声明 `ohos.permission.VPN` + `KEEP_BACKGROUND_RUNNING`（见 module.json5）
2. 通过 `vpnExtension.startVpnExtension` 建立系统 VPN 隧道
3. 核心以 TUN 入站（`type: "tun"`）接管流量，`stack: "system"` 使用系统网络栈

> 注：OpenHarmony 对 tun/raw socket 的系统能力随版本演进，API 22 需验证
> `strict_route`/`auto_route` 的可用性；不可用时降级为 `mixed` 本地端口
> + 系统代理模式（对应 Karing 的 `proxy_mode` 兼容路径）。
