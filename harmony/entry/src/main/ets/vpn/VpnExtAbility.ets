import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import karingbox from 'libkaringbox.so';

const TAG: string = 'karingVpn';

/**
 * VPN 扩展能力（sing-box 核心版）
 * 生命周期：UI 侧 startVpnExtensionAbility(want) → onCreate/onConnect
 * → createVpnConnection(context) → VpnConnection.create(VpnConfig) 建 tun 网卡
 * → protectProcessNet() 保护本进程（socket 直连物理网络，避免回环）
 * → karingbox.setConfig(配置JSON) + karingbox.start(tunFd) 启动 sing-box 数据面。
 */
export default class VpnExtAbility extends VpnExtensionAbility {
  private vpnConn: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private started: boolean = false;

  onCreate(want: Want): void {
    hilog.info(0x0000, TAG, 'VpnExtAbility onCreate, want=%{public}s', want.abilityName ?? '');
    try {
      this.vpnConn = vpnExtension.createVpnConnection(this.context);
      hilog.info(0x0000, TAG, 'createVpnConnection ok');
      // 立即建立 tun 网卡并启动 sing-box 数据面
      this.startVpn();
    } catch (e) {
      hilog.error(0x0000, TAG, 'createVpnConnection fail: %{public}s', JSON.stringify(e));
      this.writeStatus('DISCONNECTED');
    }
  }

  onConnect(want: Want): void {
    hilog.info(0x0000, TAG, 'VpnExtAbility onConnect');
  }

  onRequest(want: Want, startId: number): void {
    hilog.info(0x0000, TAG, 'VpnExtAbility onRequest startId=%{public}d', startId);
  }

  onDisconnect(want: Want): void {
    hilog.info(0x0000, TAG, 'VpnExtAbility onDisconnect');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'VpnExtAbility onDestroy');
    this.stopVpn();
  }

  /** 读取 UI 进程生成的 sing-box 配置 */
  private readConfig(): string {
    try {
      const path = this.context.filesDir + '/singbox_config.json';
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const len = fileIo.statSync(path).size;
      const buf = new ArrayBuffer(len);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      return String.fromCharCode(...new Uint8Array(buf));
    } catch (e) {
      hilog.error(0x0000, TAG, 'readConfig fail: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /**
   * 建立 VPN：创建 tun 网卡并启动 sing-box 数据面。
   * 由 UI 侧通过 startVpnExtensionAbility 拉起后调用。
   */
  async startVpn(): Promise<boolean> {
    if (this.vpnConn === null) {
      hilog.error(0x0000, TAG, 'vpnConn is null, call createVpnConnection first');
      return false;
    }
    try {
      // 1. 保护本进程：进程内所有 socket 流量直连物理网络（绕过 tun，防回环）
      await this.vpnConn.protectProcessNet();
      hilog.info(0x0000, TAG, 'protectProcessNet ok');

      // 2. 创建 tun 网卡，拿到 fd
      const config: vpnExtension.VpnConfig = {
        addresses: [{
          address: { address: '10.89.0.2', family: 1, port: 0 },
          prefixLength: 24
        }],
        routes: [{
          interface: '',
          destination: {
            address: { address: '0.0.0.0', family: 1, port: 0 },
            prefixLength: 0
          },
          gateway: {
            address: '10.89.0.2',
            family: 1,
            port: 0
          },
          hasGateway: true,
          isDefaultRoute: true
        }],
        dnsAddresses: ['223.5.5.5', '114.114.114.114'],
        mtu: 1400,
        isIPv4Accepted: true,
        isIPv6Accepted: false,
        blockedApplications: []
      };
      const fd = await this.vpnConn.create(config);
      this.tunFd = fd;
      hilog.info(0x0000, TAG, 'tun fd=%{public}d', fd);

      // 3. 读取 UI 侧生成的 sing-box 配置并启动核心
      hilog.info(0x0000, TAG, 'reading config...');
      const configJson = this.readConfig();
      hilog.info(0x0000, TAG, 'config len=%{public}d', configJson.length);
      if (configJson.length === 0) {
        hilog.error(0x0000, TAG, 'singbox_config.json is empty, abort start');
        await this.vpnConn.destroy();
        this.writeStatus('DISCONNECTED');
        return false;
      }
      hilog.info(0x0000, TAG, 'calling setConfig...');
      hilog.info(0x0000, TAG, 'karingbox type=%{public}s', typeof karingbox);
      if (karingbox === undefined || karingbox === null) {
        hilog.error(0x0000, TAG, 'karingbox module is undefined!');
        return false;
      }
      const setRet: string = karingbox.setConfig(configJson);
      hilog.info(0x0000, TAG, 'karingbox.setConfig -> %{public}s', setRet);
      if (setRet.startsWith('ERR')) {
        await this.vpnConn.destroy();
        this.writeStatus('DISCONNECTED');
        return false;
      }
      hilog.info(0x0000, TAG, 'calling start(%{public}d)...', fd);
      const startRet: string = karingbox.start(fd);
      hilog.info(0x0000, TAG, 'karingbox.start -> %{public}s', startRet);
      if (startRet.startsWith('ERR')) {
        await this.vpnConn.destroy();
        this.writeStatus('DISCONNECTED');
        return false;
      }
      this.started = true;
      this.writeStatus('CONNECTED');
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startVpn fail: name=%{public}s msg=%{public}s stack=%{public}s',
        (e as Error).name, (e as Error).message, (e as Error).stack);
      return false;
    }
  }

  /** 停止 VPN：停 sing-box 数据面并销毁 tun 网卡 */
  async stopVpn(): Promise<void> {
    try {
      if (this.started) {
        karingbox.stop();
        this.started = false;
      }
      this.tunFd = -1;
      if (this.vpnConn !== null) {
        await this.vpnConn.destroy();
      }
      this.writeStatus('DISCONNECTED');
    } catch (e) {
      hilog.error(0x0000, TAG, 'stopVpn fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 写状态文件（与 UI 进程通过 filesDir/vpn_status 同步） */
  private writeStatus(status: string): void {
    try {
      const path = this.context.filesDir + '/vpn_status';
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, status);
      fileIo.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, TAG, 'writeStatus fail: %{public}s', JSON.stringify(e));
    }
  }
}
