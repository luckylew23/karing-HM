import { Constants } from '../common/Constants';

/**
 * 设置管理器
 * 对应 Karing 的 SettingManager（lib/app/modules/setting_manager.dart）
 * 管理 TUN、DNS、分流、UI 等配置
 */
export class VpnSettings {
  /** TUN 模式 */
  tunEnabled: boolean = true;
  tunAddress: string = Constants.TUN_ADDRESS;
  tunMask: number = Constants.TUN_MASK;
  tunMtu: number = Constants.TUN_MTU;
  /** DNS */
  dnsEnabled: boolean = true;
  dnsServers: string[] = Constants.DEFAULT_DNS;
  /** 分流规则集 */
  geoIpEnabled: boolean = false;
  geoSiteEnabled: boolean = false;
  aclEnabled: boolean = false;
  /** 日志级别：trace/debug/info/warn/error */
  logLevel: string = 'info';
  /** 自动启动 */
  autoStart: boolean = false;
  /** 流量统计 */
  trafficStatsEnabled: boolean = true;
  /** WebDAV */
  webdavUrl: string = '';
  webdavUser: string = '';
  webdavPassword: string = '';

  toJson(): Record<string, Object> {
    return {
      'tunEnabled': this.tunEnabled,
      'tunAddress': this.tunAddress,
      'tunMask': this.tunMask,
      'tunMtu': this.tunMtu,
      'dnsEnabled': this.dnsEnabled,
      'dnsServers': this.dnsServers,
      'geoIpEnabled': this.geoIpEnabled,
      'geoSiteEnabled': this.geoSiteEnabled,
      'aclEnabled': this.aclEnabled,
      'logLevel': this.logLevel,
      'autoStart': this.autoStart,
      'trafficStatsEnabled': this.trafficStatsEnabled,
      'webdavUrl': this.webdavUrl,
      'webdavUser': this.webdavUser,
      'webdavPassword': this.webdavPassword
    };
  }

  static fromJson(json: Record<string, Object>): VpnSettings {
    const s = new VpnSettings();
    s.tunEnabled = (json['tunEnabled'] as boolean) ?? true;
    s.tunAddress = (json['tunAddress'] as string) ?? Constants.TUN_ADDRESS;
    s.tunMask = (json['tunMask'] as number) ?? Constants.TUN_MASK;
    s.tunMtu = (json['tunMtu'] as number) ?? Constants.TUN_MTU;
    s.dnsEnabled = (json['dnsEnabled'] as boolean) ?? true;
    s.dnsServers = json['dnsServers'] as string[] ?? Constants.DEFAULT_DNS;
    s.geoIpEnabled = (json['geoIpEnabled'] as boolean) ?? false;
    s.geoSiteEnabled = (json['geoSiteEnabled'] as boolean) ?? false;
    s.aclEnabled = (json['aclEnabled'] as boolean) ?? false;
    s.logLevel = (json['logLevel'] as string) ?? 'info';
    s.autoStart = (json['autoStart'] as boolean) ?? false;
    s.trafficStatsEnabled = (json['trafficStatsEnabled'] as boolean) ?? true;
    s.webdavUrl = (json['webdavUrl'] as string) ?? '';
    s.webdavUser = (json['webdavUser'] as string) ?? '';
    s.webdavPassword = (json['webdavPassword'] as string) ?? '';
    return s;
  }
}

export class SettingsManager {
  private static settings: VpnSettings = new VpnSettings();
  private static instance: SettingsManager | null = null;

  static getInstance(): SettingsManager {
    if (SettingsManager.instance === null) {
      SettingsManager.instance = new SettingsManager();
    }
    return SettingsManager.instance;
  }

  static getConfig(): VpnSettings {
    return SettingsManager.settings;
  }

  static load(settings: VpnSettings): void {
    SettingsManager.settings = settings;
  }
}
