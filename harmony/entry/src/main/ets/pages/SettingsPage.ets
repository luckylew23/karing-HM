
import { SettingsManager } from '../core/SettingsManager';
import { VpnBridge } from '../bridge/VpnBridge';

/**
 * 设置页：TUN、DNS、分流、日志、关于
 * 对应 Karing 的 settings_screen.dart
 */
@Component
export struct SettingsPage {
  @State tunEnabled: boolean = true;
  @State dnsEnabled: boolean = true;
  @State geoIpEnabled: boolean = true;
  @State geoSiteEnabled: boolean = true;
  @State logLevel: string = 'info';
  @State coreVersion: string = '';

  aboutToAppear(): void {
    const s = SettingsManager.getConfig();
    this.tunEnabled = s.tunEnabled;
    this.dnsEnabled = s.dnsEnabled;
    this.geoIpEnabled = s.geoIpEnabled;
    this.geoSiteEnabled = s.geoSiteEnabled;
    this.logLevel = s.logLevel;
    this.coreVersion = VpnBridge.getInstance().getCoreVersion();
  }

  syncSettings(): void {
    const s = SettingsManager.getConfig();
    s.tunEnabled = this.tunEnabled;
    s.dnsEnabled = this.dnsEnabled;
    s.geoIpEnabled = this.geoIpEnabled;
    s.geoSiteEnabled = this.geoSiteEnabled;
    s.logLevel = this.logLevel;
    SettingsManager.load(s);
  }

  getLogLevelIndex(level: string): number {
    const levels: string[] = ['trace', 'debug', 'info', 'warn', 'error'];
    const idx = levels.indexOf(level);
    return idx >= 0 ? idx : 2;
  }

  @Builder
  settingRow(title: string, desc: string, toggleValue: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontColor('#1A1A1A')
        if (desc.length > 0) {
          Text(desc)
            .fontSize(12)
            .fontColor('#999999')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: toggleValue })
        .onChange((isOn: boolean) => {
          onChange(isOn);
          this.syncSettings();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        // 标题
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .width('100%')
          .padding({ left: 20, top: 16, bottom: 8 })

        // TUN 模式
        Column() {
          this.settingRow('TUN 模式', '全局接管系统流量（需 VPN 权限）', this.tunEnabled,
            (v: boolean) => {
              this.tunEnabled = v;
            })
          Divider().color('#F0F0F0').margin({ left: 20, right: 20 })

          this.settingRow('DNS 代理', '使用远程 DNS 解析', this.dnsEnabled,
            (v: boolean) => {
              this.dnsEnabled = v;
            })
          Divider().color('#F0F0F0').margin({ left: 20, right: 20 })

          this.settingRow('GeoIP 分流', '中国 IP 直连', this.geoIpEnabled,
            (v: boolean) => {
              this.geoIpEnabled = v;
            })
          Divider().color('#F0F0F0').margin({ left: 20, right: 20 })

          this.settingRow('GeoSite 分流', '中国网站直连', this.geoSiteEnabled,
            (v: boolean) => {
              this.geoSiteEnabled = v;
            })
        }
        .width('100%')
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')

        // 日志级别
        Column() {
          Row() {
            Text('日志级别')
              .fontSize(15)
              .fontColor('#1A1A1A')
              .layoutWeight(1)
            Select([
              { value: 'trace' },
              { value: 'debug' },
              { value: 'info' },
              { value: 'warn' },
              { value: 'error' }
            ])
              .selected(this.getLogLevelIndex(this.logLevel))
              .value(this.logLevel)
              .onSelect((index: number, value: string) => {
                this.logLevel = value;
                this.syncSettings();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
        }
        .width('100%')
        .margin({ top: 12 })
        .backgroundColor('#FFFFFF')

        // 关于
        Column() {
          Row() {
            Text('核心版本')
              .fontSize(15)
              .fontColor('#1A1A1A')
            Blank()
            Text(this.coreVersion)
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          Divider().color('#F0F0F0').margin({ left: 20, right: 20 })
          Row() {
            Text('应用')
              .fontSize(15)
              .fontColor('#1A1A1A')
            Blank()
            Text('karing-HM v0.1.0')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
          Divider().color('#F0F0F0').margin({ left: 20, right: 20 })
          Row() {
            Text('开源协议')
              .fontSize(15)
              .fontColor('#1A1A1A')
            Blank()
            Text('GPL-3.0')
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 12 })
        }
        .width('100%')
        .margin({ top: 12, bottom: 30 })
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6FA')
    .scrollBar(BarState.Off)
  }
}
