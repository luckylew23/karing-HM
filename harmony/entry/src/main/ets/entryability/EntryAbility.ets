import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ServerManager } from '../core/ServerManager';
import { VpnBridge } from '../bridge/VpnBridge';

const TAG: string = 'karing';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'EntryAbility onCreate');
    // 初始化全局状态
    AppStorage.setOrCreate<boolean>('vpnConnected', false);
    AppStorage.setOrCreate<string>('currentProfile', '');
    AppStorage.setOrCreate<string>('currentNode', '');
    // 初始化数据管理器（加载本地订阅配置）与 VPN 桥
    ServerManager.init(this.context);
    VpnBridge.getInstance().init(this.context);
    hilog.info(0x0000, TAG, 'ServerManager & VpnBridge initialized');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, TAG, 'Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, TAG, 'EntryAbility onBackground');
  }
}
