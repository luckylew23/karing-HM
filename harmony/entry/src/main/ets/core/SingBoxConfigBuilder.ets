import { ServerManager } from './ServerManager';
import { SettingsManager } from './SettingsManager';
import { Constants } from '../common/Constants';
import { JsonMap } from '../model/SingBoxModels';

/**
 * sing-box 配置文件生成器
 * 对应 Karing 的 singbox_config_builder（私有模块）
 * 将订阅节点 + 设置生成 sing-box 标准 JSON 配置
 * 说明：ArkTS 不支持接口索引字段，故统一用 JsonMap (Record<string, Object>) 构建。
 */
export class SingBoxConfigBuilder {
  /** 生成完整 sing-box 配置 */
  static buildConfig(): JsonMap {
    const settings = SettingsManager.getConfig();
    const groups = ServerManager.getGroups();
    const currentGroupId = ServerManager.getCurrentGroupId();
    const currentNodeTag = ServerManager.getCurrentNodeTag();

    // 收集所有启用的节点
    const outbounds: Object[] = [];
    let selectedTag = currentNodeTag;
    for (let i = 0; i < groups.length; i++) {
      const group = groups[i];
      if (!group.enable) {
        continue;
      }
      for (let j = 0; j < group.nodes.length; j++) {
        const node = group.nodes[j];
        if (!node.enable) {
          continue;
        }
        outbounds.push(node.toOutbound());
        if (currentGroupId === group.id && (selectedTag.length === 0 || selectedTag === 'auto')) {
          selectedTag = node.tag;
        }
      }
    }
    if (selectedTag.length === 0 || selectedTag === 'auto') {
      selectedTag = 'direct';
    }

    // 添加内置 outbound
    const directOutbound: JsonMap = { 'type': 'direct', 'tag': 'direct' };
    outbounds.push(directOutbound);
    const blockOutbound: JsonMap = { 'type': 'block', 'tag': 'block' };
    outbounds.push(blockOutbound);
    const dnsOutbound: JsonMap = { 'type': 'dns', 'tag': 'dns-out' };
    outbounds.push(dnsOutbound);

    // selector：用户当前选择的节点
    const selector: JsonMap = {
      'type': 'selector',
      'tag': 'proxy',
      'outbounds': [selectedTag, 'direct', 'block'],
      'default': selectedTag
    };
    outbounds.push(selector);

    // 路由规则：默认代理，按 geoip/geosite 分流
    const rules: Object[] = [];
    const dnsRule: JsonMap = {
      'protocol': 'dns',
      'outbound': 'dns-out'
    };
    rules.push(dnsRule);
    const ruleSets: Object[] = [];
    if (settings.geoSiteEnabled) {
      const geositeSet: JsonMap = {
        'type': 'remote',
        'tag': 'geosite-cn',
        'format': 'binary',
        'url': Constants.GEOSITE_DB,
        'download_detour': 'direct'
      };
      ruleSets.push(geositeSet);
      const geositeRule: JsonMap = {
        'rule_set': ['geosite-cn'],
        'outbound': 'direct'
      };
      rules.push(geositeRule);
    }
    if (settings.geoIpEnabled) {
      const geoipSet: JsonMap = {
        'type': 'remote',
        'tag': 'geoip-cn',
        'format': 'binary',
        'url': Constants.GEOIP_DB,
        'download_detour': 'direct'
      };
      ruleSets.push(geoipSet);
      const geoipRule: JsonMap = {
        'rule_set': ['geoip-cn'],
        'outbound': 'direct'
      };
      rules.push(geoipRule);
    }
    const route: JsonMap = {
      'rules': rules,
      'final': 'proxy',
      'auto_detect_interface': true
    };
    if (ruleSets.length > 0) {
      route['rule_set'] = ruleSets;
    }

    // DNS 配置
    const remoteDns: JsonMap = {
      'tag': 'remote',
      'address': '1.1.1.1',
      'detour': 'direct'
    };
    const localDns: JsonMap = {
      'tag': 'local',
      'address': '223.5.5.5',
      'detour': 'direct'
    };
    const dns: JsonMap = {
      'servers': [remoteDns, localDns],
      'final': 'remote'
    };

    // 入站：混合端口 + TUN
    const inbounds: Object[] = [];
    const mixedInbound: JsonMap = {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '127.0.0.1',
      'listen_port': Constants.LOCAL_MIXED_PORT
    };
    inbounds.push(mixedInbound);
    if (settings.tunEnabled) {
      const tunInbound: JsonMap = {
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'karing0',
        'address': [
          settings.tunAddress + '/' + settings.tunMask
        ],
        'mtu': settings.tunMtu,
        'auto_route': false,
        'strict_route': false,
        'stack': 'system'
      };
      inbounds.push(tunInbound);
    }

    const log: JsonMap = {
      'level': settings.logLevel,
      'timestamp': true
    };

    const config: JsonMap = {
      'log': log,
      'dns': dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      'route': route
    };
    return config;
  }
}
