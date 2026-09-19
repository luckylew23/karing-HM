# karing-HM

> Karing 的 HarmonyOS 移动版 —— 原生 VPN 数据面（NDK C++）+ ArkTS 壳
>
> 版本：v0.3.3 · 状态：sing-box 核心真机 dlopen 打通（GOOS=android 动态 TLS），
> 待验证 setConfig/start 全链路（HarmonyOS NEXT API 24）

[Karing](https://github.com/KaringX/karing)（GPL-3.0，Flutter + sing-box）的 HarmonyOS 移植项目。
聚焦手机/平板形态，提供订阅管理、节点选择与代理连接。

- bundleName：`com.karing.hmos`
- VPN：VpnExtensionAbility（type: vpn）+ sing-box 核心（NAPI 桥，libkaringbox.so）
- UI：ArkTS / ArkUI（HarmonyOS NEXT，API 22）

## 功能

| 模块 | 说明 |
|------|------|
| 首页 | 一键连接/断开、当前分组与节点、连接状态 |
| 订阅 | 添加订阅（URL / 节点文本）、分组管理、节点计数、配置持久化 |
| 设置 | TUN / DNS / GeoIP / GeoSite / 日志级别 |
| 解析 | base64 订阅、ss/vmess/vless/trojan/hy2/tuic URI、sing-box JSON |
| VPN | VpnExtensionAbility 系统授权 + tun 虚拟网卡 + native 数据面（TCP/UDP 转发） |

> v0.3 数据面已切换为 **sing-box 核心**（Go wrapper 交叉编译 `libkaringbox_core.so`，33.7MB，
> GOOS=android 分支绕开 musl IE TLS；NAPI 桥 `libkaringbox.so` 独占模块名），
> 支持 ss/vmess/vless/trojan/hy2 等代理协议；v0.2 的直连转发库（libkaring_vpn.so）保留备用。

## 快速开始

### 环境

- DevEco Studio 5.0+（OpenHarmony SDK 6.0.2 / API 22）
- 无第三方 npm 依赖；NDK（`openharmony/native` + CMake）随 SDK 提供，编译 libkaring_vpn.so

### 构建

```bash
cd harmony
hvigorw assembleHap --mode module -p product=default --build-mode debug
```

产出（Debug + 自动签名）：`entry/build/default/outputs/default/entry-default-signed.hap`
（含 `libs/arm64-v8a/libkaring_vpn.so`）

### 真机安装（HarmonyOS NEXT）

1. 首次装机需在 DevEco 内完成 **AGC 自动签名**（Project Structure → Signing Configs →
   Automatically generate signature），生成绑定 `com.karing.hmos` 的签名材料
   （`~/.ohos/config/default_harmony_*.cer/.p7b/.p12`，DevEco Managed Profile）
2. 构建签名 HAP 后：

```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

3. 启动：手机解锁后点图标，或 `hdc shell aa start -a EntryAbility -b com.karing.hmos`
   （屏幕锁定会被拒，Error 10106102，需人工解锁）

> 装机排障全过程见 [docs/deployment-log.md](./docs/deployment-log.md)。

### 目录结构

```
karing-HM/
├── projectdesign.md          # 设计文档（特性/C4架构/设计/测试/要求）
├── README.md                 # 本文件
├── docs/native-bridge-api.md # sing-box native 桥接契约
└── harmony/                  # DevEco 工程
    └── entry/src/main/
        ├── cpp/              # NDK：vpn_tun.cpp + karingbox_napi.cpp（sing-box NAPI 桥）+ CMakeLists.txt
        └── ets/
            ├── pages/        # Index（Tab）+ Home / Profiles / Settings
            ├── vpn/          # VpnExtAbility（type: vpn 扩展）
            ├── model/        # ProxyConfig / ServerConfigGroup
            ├── core/         # ServerManager / SettingsManager / SubscriptionParser / SingBoxConfigBuilder
            ├── bridge/       # VpnBridge（startVpnExtensionAbility + 状态同步）
            └── common/       # Constants / Logger
```

## 使用

1. **添加订阅**：订阅页 → 「+ 添加」→ 输入备注 + 订阅链接（或直接粘贴节点文本）
2. **选择分组**：点击分组卡片设为当前分组
3. **连接**：首页 → 「开始连接」→ 系统弹「是否允许使用 VPN？」→ 允许；断开点击「断开连接」

## 架构

```
ArkTS UI → ServerManager → SingBoxConfigBuilder → VpnBridge (startVpnExtensionAbility)
     ↑                                                        ↓
  SettingsManager                          VpnExtAbility (type: vpn 扩展进程)
                                                ├─ VpnConnection.create(VpnConfig) → tun fd
                                                ├─ protectProcessNet()（本进程 socket 绕 VPN 防回环）
                                                ├─ libkaringbox.so（NAPI 桥）
                                                └─ libkaringbox_core.so（sing-box 核心，读 tun → 节点代理）
```

详见 [projectdesign.md](./projectdesign.md)。

## 许可证

GPL-3.0（继承上游 Karing；不使用 "karing" 名称/品牌，故以 karing 命名）。
上游核心：https://github.com/KaringX/karing · https://github.com/KaringX/sing-box
