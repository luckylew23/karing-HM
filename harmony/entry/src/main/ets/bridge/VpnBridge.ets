import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/**
 * VPN 桥接层
 * v0.2：真实 VPN —— 通过 vpnExtension.startVpnExtensionAbility 拉起
 * VpnExtAbility（type: vpn），由扩展进程创建 tun 网卡并启动 native 数据面。
 * UI 与扩展跨进程，用 filesDir/vpn_status 文件同步连接状态。
 */
export enum VpnState {
  DISCONNECTED = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  DISCONNECTING = 3
}

export class VpnBridge {
  private static instance: VpnBridge | null = null;
  private state: VpnState = VpnState.DISCONNECTED;
  private context: common.UIAbilityContext | null = null;

  static getInstance(): VpnBridge {
    if (VpnBridge.instance === null) {
      VpnBridge.instance = new VpnBridge();
    }
    return VpnBridge.instance;
  }

  init(ctx: common.UIAbilityContext): void {
    this.context = ctx;
    hilog.info(0x0000, 'karing', 'VpnBridge init');
  }

  /** 连接：拉起 VPN 扩展，等待 tun 建立成功 */
  async connect(configJson: string): Promise<boolean> {
    if (this.context === null) {
      return false;
    }
    if (this.state !== VpnState.DISCONNECTED) {
      return false;
    }
    this.state = VpnState.CONNECTING;
    hilog.info(0x0000, 'karing', 'VpnBridge connect start');
    try {
      // 将 sing-box 配置写入文件，供扩展进程读取
      this.writeConfig(configJson);
      this.writeStatus('CONNECTING');
      const want: Want = {
        bundleName: 'com.karing.hmos',
        abilityName: 'VpnExtAbility'
      };
      await vpnExtension.startVpnExtensionAbility(want);
      // 等待扩展进程内 tun 建立完成（轮询状态文件，最长 10s）
      const ok = await this.waitStatus('CONNECTED', 10000);
      this.state = ok ? VpnState.CONNECTED : VpnState.DISCONNECTED;
      return ok;
    } catch (e) {
      hilog.error(0x0000, 'karing', 'connect fail: %{public}s', JSON.stringify(e));
      this.state = VpnState.DISCONNECTED;
      return false;
    }
  }

  /** 断开连接 */
  async disconnect(): Promise<boolean> {
    if (this.context === null) {
      return false;
    }
    if (this.state === VpnState.DISCONNECTED) {
      return false;
    }
    this.state = VpnState.DISCONNECTING;
    hilog.info(0x0000, 'karing', 'VpnBridge disconnect');
    try {
      this.writeStatus('DISCONNECTING');
      const want: Want = {
        bundleName: 'com.karing.hmos',
        abilityName: 'VpnExtAbility'
      };
      await vpnExtension.stopVpnExtensionAbility(want);
      // 等待扩展销毁 tun
      const ok = await this.waitStatus('DISCONNECTED', 10000);
      this.state = VpnState.DISCONNECTED;
      return ok;
    } catch (e) {
      hilog.error(0x0000, 'karing', 'disconnect fail: %{public}s', JSON.stringify(e));
      this.state = VpnState.DISCONNECTED;
      return true;
    }
  }

  /** 当前状态 */
  getState(): VpnState {
    return this.state;
  }

  /** 核心版本 */
  getCoreVersion(): string {
    return 'v0.2 (tun data-plane)';
  }

  /** 写入 sing-box 配置（UI 进程 → 扩展进程共享文件） */
  private writeConfig(configJson: string): void {
    try {
      if (this.context === null) {
        return;
      }
      const path = this.context.filesDir + '/singbox_config.json';
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, configJson);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, 'karing', 'writeConfig fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 写入状态文件（UI 进程） */
  private writeStatus(status: string): void {
    try {
      if (this.context === null) {
        return;
      }
      const path = this.context.filesDir + '/vpn_status';
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, status);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, 'karing', 'writeStatus fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 轮询状态文件直到期望值或超时 */
  private async waitStatus(expected: string, timeoutMs: number): Promise<boolean> {
    if (this.context === null) {
      return false;
    }
    const path = this.context.filesDir + '/vpn_status';
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(path);
        const buf = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        fileIo.closeSync(file);
        const content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        if (content.trim() === expected) {
          return true;
        }
        if (expected === 'DISCONNECTED' && content.trim() === 'CONNECTING') {
          // 扩展已销毁时状态文件可能已被删除，视为断开成功
          return true;
        }
      } catch (e) {
        // 文件不存在：若期望断开则视为成功
        if (expected === 'DISCONNECTED') {
          return true;
        }
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 300));
    }
    return false;
  }
}
