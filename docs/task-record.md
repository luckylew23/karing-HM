# 任务记录：分析 Karing 项目，创建 HarmonyOS 移动版

> 版本：v0.1.0（2026-09-18）· 记录人：AI 助手

## 1. 输入提示词（原样）

> 分析 karing 项目，创建 HarmonyOS 移动版

## 2. 任务解析

| 项 | 内容 |
|----|------|
| 目标 1 | 分析 Karing 开源项目（技术栈/架构/模块/内核集成） |
| 目标 2 | 创建 HarmonyOS 移动版（命名 karing-HM，bundleName com.karing.hmos） |
| 默认输出 | markdown 文档 + DevEco 工程骨架 |
| 输出目录 | ~/Work/karing-HM |
| 版本规范 | v0.1 起递增，不覆盖旧版本 |

## 3. 执行过程

1. **探查**：确认 `~/Work/karing` 为 Karing 源码（Flutter 1.2.25+2801，GPL-3.0）；
   发现 `lib/app/utils`、`local_services`、`private` 三个目录在开源仓库中**缺失**
   （被 Karing 保留私有，main.dart 中 315+20+3 处引用）。
2. **补全分析**：git 克隆超时 → codeload tar.gz 截断 → sparse clone 验证 GitHub main
   分支确实不含上述目录 → 确认核心层需自行设计。
3. **架构还原**：依据公开源码（152 个 Dart 文件 / 10.2 万行 / 79 个 screen）梳理出
   ServerManager / SettingsManager / SubscriptionParser / SingBoxConfigBuilder / VpnBridge 五层结构。
4. **设计移植方案**：ArkTS 重写 UI + sing-box 核心 native 化（N-API 桥接）；
   TUN 走 vpnExtension，降级路径为 mixed 端口 + 系统代理。
5. **创建工程**：DevEco 标准工程（API 22 / OpenHarmony 6.0.2），3 Tab 移动端 UI，
   订阅解析器（ss/vmess/vless/trojan/hy2/tuic/JSON）、配置生成器、持久化、桥接契约。
6. **构建验证**：首轮构建失败（VPN 权限、ArkTS 对象字面量、kit 导入错误）→ 逐项修复 →
   **构建成功 + 本地签名 VERIFY OK**。
7. **清理**：删除 karing-full/karing-main/karing-src.tar.gz 等临时分析产物。

## 4. 产物清单

| 产物 | 路径 |
|------|------|
| 可安装 HAP | ~/Work/karing-HM/karing-HM-v0.1-signed.hap |
| 设计文档 | ~/Work/karing-HM/projectdesign.md |
| 项目说明 | ~/Work/karing-HM/README.md |
| native 桥接契约 | ~/Work/karing-HM/docs/native-bridge-api.md |
| DevEco 工程 | ~/Work/karing-HM/harmony/ |

## 5. 经验教训（沉淀）

### 5.1 关于 Karing 移植

1. **上游部分开源**：Karing 的 UI/业务层开源，但 sing-box 集成核心（utils/local_services）
   私有。移植时不要指望"直接翻译 Dart"，而是按契约自行实现，反而是干净的架构起点。
2. **内核策略**：sing-box 是 Go 核心，HarmonyOS 无法直接运行 → N-API 桥接 libsingbox.so；
   这是最大工程量，v0.1 先定契约，后续交叉编译。
3. **降级路径必须提前设计**：TUN 不可用时应降级 mixed 端口 + 系统代理，保证基础可用性。

### 5.2 关于 HarmonyOS/ArkTS 工程（可直接复用）

1. **`@kit.ArkUI` 只导出 API 类**（window 等）；Column/Text/Tabs/Divider 等 UI 组件是全局符号，
   **从 kit 导入会报 `not exported`** —— 页面文件无需 import 任何 UI 组件。
2. **ArkTS 严格语法**：
   - 对象字面量必须对应显式类型：用 `Record<string, Object>`（别名为 JsonMap）构建 JSON 配置
   - interface 不支持索引签名（`[key: string]: T`）、字段不支持按索引访问
   - 嵌套对象字面量也要显式变量化，否则报 `arkts-no-untyped-obj-literals`
   - `as T ?? x` 需加括号 `(v as T) ?? x`
3. **权限白名单**：`ohos.permission.VPN` 不在 SDK 预定义权限内，加了会构建失败；
   VPN 能力经 vpnExtension API 申请。
4. **deviceTypes**：写 `phone/tablet` 有 warning，建议 `default`（API 22 行为）。
5. **构建工具链**：hvigorw 委托 DevEco 全局 hvigor（6.22.4），本地 CA 链签名可离线产出可安装 HAP。

## 6. 后续迭代建议

- [ ] sing-box 核心 NDK 交叉编译（arm64-v8a/armeabi-v7a）
- [ ] 节点列表页 + 延迟测试 UI
- [ ] 配置编辑（YAML/JSON 文本）
- [ ] WebDAV / ZIP 备份同步
- [ ] 规则集自定义分组（对应 Karing diversion 模块）

---

## 任务：karing-HM v0.3 集成 sing-box 核心（2026-09-19）

### 输入提示词
用户："分析 karing 项目，创建 HarmonyOS 移动版，就叫 karing-HM，安装到我的手机" / "go on" / "安装" / "订阅不生效" / "尽快实现最基本的vpn功能" / "继续" / "继续吧"

### 过程
1. Go 1.27.1 工具链 + sing-box 源码（KaringX/sing-box dev-next）
2. 自写 Go wrapper（cmd/libkaringbox）：hmPlatform 注入 tun fd，5 个 C 导出
3. OHOS 交叉编译 libkaringbox.so（44.7MB，arm64）
4. NAPI 桥 karingbox_napi.cpp + CMake IMPORTED 链接
5. ArkTS 接线：VpnExtAbility/VpnBridge/SingBoxConfigBuilder
6. 构建排错：NAPI 签名（&json[0]）、Specification Limit（IMPORTED）、arkts-no-any-unknown（:string）
7. HAP 46MB 构建成功；设备掉线，待重连装机验证

### 经验沉淀（v0.3 真机排错追加，2026-09-19）
1. Go c-shared 交叉编译 OHOS：GOOS=linux GOARCH=arm64 + OHOS clang + musl sysroot，
   架构头要加 -I.../aarch64-linux-ohos
2. NAPI C++：std::string::data() 在 C++14 返回 const char*，写缓冲用 &str[0]
3. hvigor 会自动打包 entry/libs/*.so；CMake 再 add_library 会重复导致 00306049，
   预编译 so 必须用 add_library(... SHARED IMPORTED) 仅链接
4. ArkTS 严格模式：NAPI 返回值必须显式声明类型
5. sing-tun FileDescriptor>0 时复用 fd 不重建 tun 设备——鸿蒙 VpnConnection fd 直接可用
6. **with_naive_outbound 引入 cronet-go（glibc 预编译库）→ 真机 14 个 glibc 符号缺失**；
   去该 tag 后缺失符号清零（check_und.sh 验证）
7. **Go c-shared + musl dlopen：IE TLS 冲突（initial-exec TLS resolves to dynamic
   definition）是上游已知限制**；GOOS=android 分支走 x_cgo_inittls 动态 TLS 可绕开，
   但 android 分支链接需要 -llog（bionic）→ 编 liblog stub（__android_log_* 空实现）
   + netgo osusergo 解决
8. **c-archive 交叉编译 OHOS 产出 96B 空归档**（仅 __.SYMDEF；NDK 无 llvm-ar）——不可用
9. **同名 .so 冲突坑**：CMake 产物与 entry/libs 预编译 so 同名时 HAP 打包覆盖；
   ArkTS import 加载到错库 → 调 NAPI 方法 TypeError（JSON.stringify 空 Error = {}）。
   解法：Go 核心改名 libkaringbox_core.so，NAPI 桥独占 libkaringbox.so
10. 真机 hilog 排错关键：`hilog -x | grep -iE 'karingVpn|karingbox'`；
    `JSON.stringify(e) == {}` 说明异常对象不可序列化（多为 native/undefined 调用）
