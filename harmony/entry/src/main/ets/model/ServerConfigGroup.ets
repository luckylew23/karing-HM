import { ProxyConfig } from './ProxyConfig';

/**
 * 配置分组模型
 * 对应 Karing 的 ServerConfigGroupItem
 */
export class ServerConfigGroup {
  /** 分组 id */
  id: string = '';
  /** 分组备注 */
  remark: string = '';
  /** 订阅 URL */
  url: string = '';
  /** 是否启用 */
  enable: boolean = true;
  /** 自动更新间隔（小时） */
  updateInterval: number = 24;
  /** 上次更新时间 */
  lastUpdated: number = 0;
  /** 分组内节点 */
  nodes: ProxyConfig[] = [];

  constructor(id: string = '', remark: string = '') {
    this.id = id;
    this.remark = remark;
  }

  toJson(): Record<string, Object> {
    return {
      'id': this.id,
      'remark': this.remark,
      'url': this.url,
      'enable': this.enable,
      'updateInterval': this.updateInterval,
      'lastUpdated': this.lastUpdated,
      'nodes': this.nodes.map((n: ProxyConfig) => this.nodeToJson(n))
    };
  }

  private nodeToJson(n: ProxyConfig): Record<string, Object> {
    return {
      'tag': n.tag,
      'type': n.type,
      'server': n.server,
      'serverPort': n.serverPort,
      'password': n.password,
      'uuid': n.uuid,
      'method': n.method,
      'tls': n.tls,
      'network': n.network,
      'wsPath': n.wsPath,
      'wsHost': n.wsHost,
      'flow': n.flow,
      'fingerprint': n.fingerprint,
      'remark': n.remark,
      'groupId': n.groupId,
      'latency': n.latency,
      'enable': n.enable,
      'index': n.index
    };
  }

  static fromJson(json: Record<string, Object>): ServerConfigGroup {
    const group = new ServerConfigGroup();
    group.id = json['id'] as string;
    group.remark = json['remark'] as string;
    group.url = json['url'] as string;
    group.enable = json['enable'] as boolean;
    group.updateInterval = json['updateInterval'] as number;
    group.lastUpdated = json['lastUpdated'] as number;
    const nodesJson = json['nodes'] as Record<string, Object>[];
    if (Array.isArray(nodesJson)) {
      group.nodes = [];
      for (let i = 0; i < nodesJson.length; i++) {
        group.nodes.push(ServerConfigGroup.nodeFromJson(nodesJson[i]));
      }
    }
    return group;
  }

  private static nodeFromJson(json: Record<string, Object>): ProxyConfig {
    const n = new ProxyConfig();
    n.tag = (json['tag'] as string) ?? '';
    n.type = (json['type'] as string) ?? '';
    n.server = (json['server'] as string) ?? '';
    n.serverPort = (json['serverPort'] as number) ?? 0;
    n.password = (json['password'] as string) ?? '';
    n.uuid = (json['uuid'] as string) ?? '';
    n.method = (json['method'] as string) ?? '';
    n.tls = (json['tls'] as boolean) ?? false;
    n.network = (json['network'] as string) ?? '';
    n.wsPath = (json['wsPath'] as string) ?? '';
    n.wsHost = (json['wsHost'] as string) ?? '';
    n.flow = (json['flow'] as string) ?? '';
    n.fingerprint = (json['fingerprint'] as string) ?? 'chrome';
    n.remark = (json['remark'] as string) ?? '';
    n.groupId = (json['groupId'] as string) ?? '';
    n.latency = (json['latency'] as number) ?? -1;
    n.enable = (json['enable'] as boolean) ?? true;
    n.index = (json['index'] as number) ?? 0;
    return n;
  }
}
