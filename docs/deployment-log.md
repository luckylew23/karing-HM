# karing-HM 装机记录（DevEco AGC 自动签名）

> 版本：v0.1.0-build20260919 · 状态：真机安装成功
> 对应任务：分析 karing 项目 → 创建 karing-HM → 安装到手机（HarmonyOS NEXT，API 24）

## 一、任务输入提示词（原始）

用户原始指令（多轮合并）：

1. 「分析 karing 项目，创建 HarmonyOS 移动版，就叫 karing-HM，安装到我的手机」
2. 装机失败后选择：DevEco 自动签名（AGC 真机签名）路径（用户拍板）

## 二、执行过程摘要

### 阶段 1：项目正名与骨架（已完成）

- `KaringLite-HM` → `karing-HM`（用户钦定，不使用 Lite-HM 后缀）
- 全局替换 `com.karinglite.hmos` → `com.karing.hmos`、`vendor` → `karing`
- 产出：工程骨架 + projectdesign.md + README.md + docs/native-bridge-api.md

### 阶段 2：本地自签 CA 装机（失败，已留档）

- 产物：`karing-HM-v0.1-signed.hap`（738KB，本地自签 CA）
- 真机拒绝：`error: failed to install bundle. code:9568257 fail to verify pkcs7 file.`
- 结论：**HarmonyOS NEXT 真机（API 24）不接受自签 CA 的 HAP**，必须走华为签名链（AGC / DevEco 自动签名）

### 阶段 3：IDE 同步排障（两个根因，均已修复）

**根因 A：`targetSdkVersion: ""` 触发 IDE 校验拦截**

- 报错：`Invalid value of compileSdkVersion, compatibleSdkVersion, or targetSdkVersion (if set)`
- 定位：反编译 `hos-project-mgmt-6.0.2.650.jar` 的 `HosIntegrationChecker.checkApiVersionFormat`
  - compatible 正则：`^(\d+)(\.\d+){2}\(\d+\)$` → `"6.0.2(22)"` 通过
  - compile/target 正则更严格，空字符串 `""` 不匹配 → 抛 `SyncInterruptException`
- 修复：删除 build-profile.json5 中的 `targetSdkVersion` 字段（空串字段直接删，非置空）

**根因 B：IDE hvigor daemon 的 `DEVECO_SDK_HOME` 缺少 `default` 子目录**

- 报错：`SDK component missing`（00303168）
- 现象对比：命令行同步成功（打印两条 `[SDKDBG] getLocalSdks`：`"22"` 与 `"6.0.2"`）；IDE 失败（仅一条 `"22"`）
- 定位：hvigor 的 Property 解析（`hvigor-ohos-plugin/src/sdk/lib/property-get.js`）对 HarmonyOS 工程
  **忽略 local.properties 的 `hwsdk.dir`，只从 `DEVECO_SDK_HOME` 环境变量取值**
  - IDE daemon：`DEVECO_SDK_HOME=.../Contents/sdk`（缺 default）→ SDK 组件扫描失败
  - 命令行 shell（.zshrc）：`DEVECO_SDK_HOME=.../Contents/sdk/default` → 成功
- 修复：`launchctl setenv DEVECO_SDK_HOME ".../Contents/sdk/default"` → 重启 DevEco
  → 新进程 env 验证正确 → IDE 内 `Sync and Refresh Project` → **successful**

### 阶段 4：DevEco AGC 自动签名（成功）

- 工程配置：Bundle name `com.karing.hmos`、Compatible SDK `6.0.2(22)`、runtimeOS `HarmonyOS`
- Project Structure → Signing Configs：勾选 Automatically generate signature
- DevEco 自动生成签名材料（绑定 `com.karing.hmos`）：
  - `~/.ohos/config/default_harmony_3HuVI9HWwa1fXWn09XkrdtTn7Hj1a031XBNt8xupCIU=.cer/.p7b/.p12`
  - Team：陆昕 · Profile：DevEco Managed Profile · KeyAlias：debugKey · 算法：SHA256withECDSA
- 验证：p7b 内 bundle-name 确认为 `com.karing.hmos`
- build-profile.json5 写入 signingConfigs.default（材料齐全）
- 修正：product 的 `signingConfig` 由 `""` → `"default"`（对照参照工程 zhihuLite-HM）

### 阶段 5：构建 + 真机安装（成功）

```bash
cd ~/Work/karing-HM/harmony
./hvigorw assembleHap --mode module -p product=default --build-mode debug --no-daemon
# → BUILD SUCCESSFUL
# → entry/build/default/outputs/default/entry-default-signed.hap (404KB)

hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
# → install bundle successfully
```

- 真机：HUAWEI Mate X5（`68Q0224327000037`，const.ohos.apiversion=24）
- `bm dump -n com.karing.hmos`：应用存在、enabled=true、isSystemApp=false
- 启动验证：`aa start -a EntryAbility -b com.karing.hmos`
  → 被拒 `10106102 The device screen is locked`（开发者模式无法自动解锁，需人工解锁后启动）

## 三、经验教训（沉淀）

1. **HarmonyOS NEXT 真机签名是硬门槛**：自签 CA 无法装真机（pkcs7 校验失败），
   本地自签只适用于模拟器/调试。真机安装 = 华为签名链（AGC 自动签名 / 正式证书）。
2. **IDE 同步失败先查环境变量，再查配置格式**：`DEVECO_SDK_HOME` 必须指向含
   `default` 的完整 SDK 路径；GUI app 的环境变量通过 `launchctl setenv` + 重启生效，
   不要只改 local.properties（HarmonyOS 工程下 hwsdk.dir 被 hvigor 忽略）。
3. **IDE 校验规则可反编译定位**：DevEco 插件 jar 在 `Contents/plugins/harmony/lib/`，
   用 unzip + javap/jadx 反编译可精确获知正则与校验逻辑，比盲试高效。
4. **build-profile.json5 的 product.signingConfig 需显式关联**：signingConfigs 里有材料
   不等于生效，product 必须引用 `"default"`（IDE 自动签名有时不写回该字段）。
5. **对照参照工程**：IDE 同步正常的工程（zhihuLite-HM/harmony-native）是排障的黄金参照
   ——配置差异即根因候选。

## 四、后续待办

- [ ] 手机解锁后人工启动 karing-HM 验证首屏
- [ ] sing-box native 交叉编译（VpnBridge N-API 契约见 docs/native-bridge-api.md）
- [ ] 订阅解析、连接链路真机联调

## 六、v0.2：基本 VPN 真机打通（2026-09-19）

> 对应任务：「尽快实现最基本的vpn功能」+ 此前报障「订阅不生效」

### 6.1 订阅不生效的根因（已修复）

1. **`EntryAbility.onCreate` 从未调用 `ServerManager.init()`** → `ServerManager.context` 恒为 null
   → `saveToStorage()` 直接 return，配置永不落盘（手机端 `filesDir/` 无 `server_config.json`）。
   修复：onCreate 中调用 `ServerManager.init(this.context)` + `VpnBridge.getInstance().init(this.context)`。
2. **`ServerConfigGroup.toJson()` 未序列化 `nodes`** → 即使落盘也只有分组、没有节点。
   修复：toJson/fromJson 增加 nodes 完整序列化（含 ProxyConfig 全字段）。
3. 现场验证：该订阅链接（api-huacloud.net）服务端返回 **HTTP 400 "no valid node info"**，
   属于订阅源本身失效（token 过期/停用），非 App 解析问题。

### 6.2 基本 VPN 实现（v0.2）

- **新增 `VpnExtAbility`**（type: vpn 扩展，`ets/vpn/VpnExtAbility.ets`）：
  `createVpnConnection(context)` → `VpnConnection.create(VpnConfig)` 返回 **tun fd**（实测 fd=29）
  → `protectProcessNet()`（API 22+，本进程 socket 直连物理网络防回环）→ `libkaring_vpn.so` 数据面。
- **新增 NDK 数据面**（`cpp/vpn_tun.cpp` + CMakeLists.txt，arm64-v8a）：
  读 tun fd → 解析 IPv4 → TCP/UDP 直连目标转发（TCP 维护基础 seq/ack 映射；UDP 简单映射）；
  每 5s 打印统计 `tunRx/sockRx/flows`。
- **VpnBridge 真实化**：connect → `startVpnExtensionAbility(want)`（系统弹授权窗）；
  状态经 `filesDir/vpn_status` 文件跨进程同步（CONNECTING→CONNECTED→DISCONNECTED）。
- **module.json5**：新增 `extensionAbilities`（type: "vpn"）；entry/build-profile.json5 加
  `externalNativeOptions`（CMake，abiFilters arm64-v8a）。

### 6.3 真机验证结果（Mate X5, API 24）

| 检查项 | 结果 |
|--------|------|
| 系统授权弹窗「是否允许使用 VPN？」 | 出现，点击允许成功 |
| tun 网卡 | `ifconfig vpn-tun`：10.89.0.2/24 存在 |
| 扩展进程 | `com.karing.hmos:vpn` 存活 |
| native 日志 | `tun fd=29` + `startVpn tunFd=29` |
| 数据面统计 | `tunRx=27 sockRx=12 flows=4`（流量经 tun 双向转发） |
| UI 状态 | 已连接 → 断开连接，状态随 vpn_status 同步 |
| 断开清理 | vpn-tun 网卡销毁、扩展进程退出、状态 DISCONNECTED |

### 6.4 经验沉淀

1. **HarmonyOS VPN 三步走**：`startVpnExtensionAbility(want)`（弹授权）→ 扩展进程内
   `createVpnConnection(context)` → `VpnConnection.create(VpnConfig)` 拿 **tun fd**；
   隧道内协议（TCP/IP 转发、代理加密）需应用自行实现。
2. **防回环关键**：数据面出向 socket 必须绕过 tun——`protectProcessNet()`（API 22+）一次调用
   保护整个进程，比逐 socket `protect(fd)` 简单可靠。
3. **VpnConfig 类型**：`routes[].gateway` 是 `NetAddress`（`address: string`），
   不是 `LinkAddress`（`address: NetAddress`）——按 SDK `@ohos.net.vpnExtension.d.ts` 为准。
4. **跨进程状态同步**：ExtensionAbility 与 UIAbility 不同进程，用 `filesDir/vpn_status`
   文件轮询同步（扩展写、UI 读），简单有效。
5. **ArkTS 约束**：对象字面量必须对应显式接口（`arkts-no-untyped-obj-literals`）；
   `util.TextDecoder` 而非全局 `TextDecoder`。
6. 真机 UI 自动化：`hdc shell uitest dumpLayout` 拿坐标 + `uitest uiInput click x y` 模拟点击；
   `power-shell wakeup` 唤醒屏幕，锁屏会拒启动（10106102）。

---

## 7. v0.3：集成 sing-box 核心（2026-09-19）

### 7.1 目标与决策

- **目标**：v0.2 是"直连转发"隧道，未代理到订阅节点。v0.3 集成 sing-box 核心，让 karing-HM
  消费订阅节点（ss/vmess/vless/trojan/hy2 等），tun 流量真正代理到节点。
- **关键决策**：不用官方 libbox/gomobile 封装（PlatformInterface 20+ 平台方法鸿蒙适配成本高），
  自写精简 Go wrapper（`cmd/libkaringbox/main.go`），调 sing-box 核心 `box.New` + `instance.Start()`，
  用 `service.ContextWith[adapter.PlatformInterface]` 注入鸿蒙平台实现 `hmPlatform`，
  `OpenInterface()` 把鸿蒙 VpnConnection 的 tun fd 赋给 `tun.Options.FileDescriptor`。

### 7.2 工具链与交叉编译

| 项 | 值 |
|---|---|
| Go | brew 1.27.1（Apple Silicon），GOPROXY=https://goproxy.cn,direct |
| 交叉编译 | GOOS=linux GOARCH=arm64 CGO_ENABLED=1 + OHOS NDK `aarch64-unknown-linux-ohos-clang` + musl sysroot |
| 坑 | sysroot 架构头在 `usr/include/aarch64-linux-ohos`（缺它报 bits/alltypes.h not found） |
| tags | with_gvisor with_quic with_wireguard with_utls with_clash_api with_naive_outbound |
| 产物 | `entry/libs/arm64-v8a/libkaringbox.so`（44.7MB，stripped，5 导出符号） |
| 脚本 | `tools/build-singbox-core.sh`（可复现） |

### 7.3 NAPI 桥与 ArkTS 接线

- `cpp/karingbox_napi.cpp`：NAPI 模块 `karingbox`，导出 setConfig/start/stop/isRunning/version。
- `CMakeLists.txt`：karingbox 库 IMPORTED 链接 libkaringbox.so（避免重复打包 Specification Limit）。
- `VpnExtAbility.ets`：protectProcessNet → VpnConnection.create → 读 singbox_config.json →
  karingbox.setConfig → karingbox.start(fd)。
- `VpnBridge.ets`：connect 前写 singbox_config.json（UI→扩展共享）。
- `SingBoxConfigBuilder.ets`：tun inbound auto_route/strict_route=false（系统 VPN 接管路由）。

### 7.4 构建排错记录

| 错误 | 解法 |
|---|---|
| napi_get_value_string_utf8 签名不匹配 | std::string::data() 返回 const char*（C++14），改 `&json[0]` |
| 00306049 Specification Limit Violation | CMake add_library 会复制 so 进 obj，与 entry/libs 重复；改 IMPORTED 仅链接 |
| arkts-no-any-unknown | NAPI 返回值显式声明 `: string` |

### 7.5 待真机验证

- [ ] sing-box 核心在真机启动（hilog 看 setConfig/start 返回）
- [ ] 有有效订阅节点时流量经节点代理
- [ ] tun + sing-box 栈（system）在鸿蒙是否正常建栈
- [ ] dhcp://auto DNS transport 可用性

### 7.6 真机排错三连（v0.3.0 → v0.3.3，均已定位）

**问题 1：`Load native module failed`，`llvm-nm -D` 353 个未定义符号，其中 14 个 glibc 专有符号缺失**
（`__libc_malloc / __res_state / __cmsg_nxthdr / __sched_cpufree / strtoll_l / strtoull_l / __vfprintf_chk` 等）

- 根因：`protocol/naive/outbound.go` 的 `//go:build with_naive_outbound` 引入
  `github.com/sagernet/cronet-go`（Google 预编译 **glibc** 库），与 musl 冲突。
- 解法：**去掉 `with_naive_outbound` tag 重编** → so 33.7MB，缺失符号清零
  （用 `tools/check_und.sh` 比对真机 musl `/tmp/ohos-musl.so` 验证）。→ **v0.3.1**

**问题 2：`initial-exec TLS resolves to dynamic definition`（dlopen libkaringbox.so 失败）**

- 根因：Go linux/arm64 runtime 用 **IE TLS**（`tls_arm64.s` 中 `runtime·tls_g` 是 TLSBSS 变量，
  `MRS TPIDR_EL1` + 固定偏移寻址），musl dlopen 无法为库内动态 TLS 定义分配静态 TLS 槽。
  这是 **Go c-shared + musl 的上游已知限制**（wener.me FAQ、Openwall musl 邮件列表证实）。
- 试错两条路（均弃）：
  1. `GOOS=android`（android 分支走 `gcc_android.c` 的 `TLS_SLOT_APP` 动态 TLS）→
     链接报 `unable to find library -llog`（bionic 日志库，OHOS 没有）。
  2. `buildmode=c-archive` 静态链进 NAPI 桥 → 交叉产物是 **96B 空归档**
     （仅 `__.SYMDEF SORTED`；OHOS NDK `llvm/bin` 无 llvm-ar/ranlib，疑似 extld 打包问题）。

**问题 3（v0.3.2 装机后）：`startVpn fail: {}`（tun fd=31 已建立、无 dlopen 报错）**

- 根因：**两个同名 `libkaringbox.so` 冲突**——CMake 的 NAPI 桥（karingbox_napi.cpp → libkaringbox.so）
  与 `entry/libs/arm64-v8a/libkaringbox.so`（Go 核心）同名，HAP 打包时 Go 库覆盖了 NAPI 桥；
  ArkTS `import karingbox from 'libkaringbox.so'` 加载到的是 Go 库（无 `napi_module_register`），
  `setConfig` 为 undefined → TypeError（JSON.stringify 空 Error = `{}`）。
- 解法：**Go 核心改名 `libkaringbox_core.so`**（c-shared 产物 + IMPORTED_LOCATION 同步改），
  NAPI 桥独占 `libkaringbox.so`。→ **v0.3.3**（33.7MB core + 53KB 桥，HAP 内符号验证正确）。

**TLS 方案定论**：v0.3.2/v0.3.3 实际采用 `GOOS=android` 分支 + `-llog` liblog stub 编出
（android 的 `TLSG_IS_VARIABLE` + `x_cgo_inittls` 动态 TLS 绕开 IE TLS）——
`tools/build-singbox-core.sh` 已更新为该方案（GOOS=android + netgo osusergo + liblog stub + 去 naive）。
若 android 分支在 OHOS 运行期暴露 bionic 假设问题，备选方案：Rust 重写数据面（TailMesh 验证过）、
patch Go runtime TLS 汇编重编 toolchain、或 gomobile/libbox 官方封装。

## v0.3.8 - sing-box 核心成功运行 (2026-09-19)

### 突破
- **Go sing-box 核心在 OHOS 真机上成功运行**
- `setConfig -> OK`，`start -> OK`
- VPN 状态: CONNECTED
- mixed proxy 监听 127.0.0.1:2082

### 关键修复
1. **TLS offset = 0**: 将 `gcc_android.c` 的 `inittls` 简化为 `*tlsg = (void*)0`
   - musl/OHOS 上 pthread_setspecific 扫描法不工作（偏移不对）
   - offset 0 对应 TCB self 指针，Go runtime 能正常工作
2. **with_dhcp 构建标签**: 配置中使用 dhcp://auto 需要此标签
3. **配置修复**:
   - 无节点时 selectedTag 默认为 'direct'（不再是空字符串）
   - 禁用 geoSite/geoIp（避免下载远程 rule-set）
   - DNS 改为 UDP 直连（1.1.1.1 + 223.5.5.5），detour=direct
   - TUN 地址统一为 10.89.0.2/24（Constants 与 VpnConnection 一致）
   - stack: system（gvisor stack fstat 失败）

### 构建参数
```
GOOS=android GOARCH=arm64 CGO_ENABLED=1
CC=aarch64-unknown-linux-ohos-clang
tags=netgo osusergo with_gvisor with_quic with_wireguard with_utls with_clash_api with_dhcp
-buildmode=c-shared
```

### 待办
- [ ] 添加有效订阅节点后验证代理连通性
- [ ] 流量统计功能
- [ ] 系统 stack tun 数据面验证（实际流量转发）
