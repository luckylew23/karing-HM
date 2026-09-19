/**
 * 全局常量定义
 */
export class Constants {
  /** 应用 TAG */
  static readonly TAG: string = 'karing';
  /** 默认 TUN 网段 */
  static readonly TUN_ADDRESS: string = '10.89.0.2';
  static readonly TUN_MASK: number = 24;
  static readonly TUN_MTU: number = 1400;
  /** sing-box 核心版本（对应 Karing 魔改核心） */
  static readonly CORE_VERSION: string = '1.13.0';
  /** 本地监听地址 */
  static readonly LOCAL_SOCKS_PORT: number = 2080;
  static readonly LOCAL_HTTP_PORT: number = 2081;
  static readonly LOCAL_MIXED_PORT: number = 2082;
  /** 订阅 User-Agent */
  static readonly DEFAULT_USER_AGENT: string = 'karing/0.1.0';
  /** 配置文件存储目录 */
  static readonly CONFIG_DIR: string = 'karing/profiles';
  static readonly RULESET_DIR: string = 'karing/rulesets';
  /** 默认 DNS */
  static readonly DEFAULT_DNS: string[] = ['https://dns.google/dns-query', 'https://1.1.1.1/dns-query'];
  /** GeoIP 数据库（sing-box 标准格式） */
  static readonly GEOIP_DB: string = 'https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs';
  static readonly GEOSITE_DB: string = 'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs';
}
