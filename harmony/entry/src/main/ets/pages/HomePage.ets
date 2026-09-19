
import { ServerManager } from '../core/ServerManager';
import { SingBoxConfigBuilder } from '../core/SingBoxConfigBuilder';
import { VpnBridge, VpnState } from '../bridge/VpnBridge';
import { Logger } from '../common/Logger';

/**
 * 首页：连接开关、当前节点、状态展示
 * 对应 Karing 的 home_screen.dart 核心功能区
 */
@Component
export struct HomePage {
  @State vpnConnected: boolean = false;
  @State connecting: boolean = false;
  @State currentGroupName: string = '未选择';
  @State currentNodeName: string = '未选择';
  @State trafficUp: string = '0 B';
  @State trafficDown: string = '0 B';

  aboutToAppear(): void {
    this.refreshNodeInfo();
  }

  refreshNodeInfo(): void {
    const group = ServerManager.getGroup(ServerManager.getCurrentGroupId());
    if (group !== null) {
      this.currentGroupName = group.remark;
    }
    const tag = ServerManager.getCurrentNodeTag();
    if (tag.length > 0) {
      this.currentNodeName = tag;
    }
  }

  async onToggleConnect(): Promise<void> {
    const bridge = VpnBridge.getInstance();
    if (this.vpnConnected || this.connecting) {
      this.connecting = true;
      const ok = await bridge.disconnect();
      this.connecting = false;
      if (ok) {
        this.vpnConnected = false;
      }
      return;
    }
    this.connecting = true;
    try {
      const config = SingBoxConfigBuilder.buildConfig();
      const ok = await bridge.connect(JSON.stringify(config));
      if (ok) {
        this.vpnConnected = true;
      }
    } catch (e) {
      Logger.error('connect failed: ' + JSON.stringify(e));
    }
    this.connecting = false;
  }

  build() {
    Column({ space: 16 }) {
      // 顶部标题
      Row() {
        Text('karing')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
      }
      .width('100%')
      .padding({ left: 20, top: 16 })

      // 连接状态卡片
      Column({ space: 8 }) {
        // 开关按钮
        Button() {
          Text(this.connecting ? '连接中…' : (this.vpnConnected ? '断开连接' : '开始连接'))
            .fontSize(18)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Medium)
        }
        .type(ButtonType.Capsule)
        .width(200)
        .height(56)
        .backgroundColor(this.vpnConnected ? '#E64340' : '#0A59F7')
        .onClick(() => {
          this.onToggleConnect();
        })

        Text(this.vpnConnected ? '已连接' : '未连接')
          .fontSize(14)
          .fontColor(this.vpnConnected ? '#E64340' : '#999999')
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })

      // 节点信息卡片
      Column({ space: 12 }) {
        Row() {
          Text('当前分组')
            .fontSize(14)
            .fontColor('#666666')
          Blank()
          Text(this.currentGroupName)
            .fontSize(14)
            .fontColor('#1A1A1A')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')

        Divider().color('#F0F0F0')

        Row() {
          Text('当前节点')
            .fontSize(14)
            .fontColor('#666666')
          Blank()
          Text(this.currentNodeName)
            .fontSize(14)
            .fontColor('#0A59F7')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 180 })
        }
        .width('100%')

        Divider().color('#F0F0F0')

        Row() {
          Text('流量统计')
            .fontSize(14)
            .fontColor('#666666')
          Blank()
          Text(this.trafficUp + ' ↑  ' + this.trafficDown + ' ↓')
            .fontSize(14)
            .fontColor('#1A1A1A')
        }
        .width('100%')
      }
      .width('92%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 2 })

      // 提示
      Text('订阅管理请在「订阅」页添加，添加后回到本页连接')
        .fontSize(12)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
        .width('90%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6FA')
  }
}
