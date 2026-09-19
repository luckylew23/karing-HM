import { JsonMap } from './SingBoxModels';

/**
 * 代理节点配置模型
 * 对应 Karing 的 ProxyConfig（lib/app/modules/server_manager.dart 私有部分）
 */
export class ProxyConfig {
  /** 节点 tag */
  tag: string = '';
  /** 节点类型：shadowsocks / vmess / vless / trojan / hysteria2 / tuic / wireguard */
  type: string = '';
  /** 服务器地址 */
  server: string = '';
  /** 服务器端口 */
  serverPort: number = 0;
  /** 密码（ss/trojan） */
  password: string = '';
  /** 用户 ID（vmess/vless） */
  uuid: string = '';
  /** 加密方式（ss） */
  method: string = '';
  /** TLS 开关 */
  tls: boolean = false;
  /** 传输层：ws / grpc / httpupgrade / xhttp 等 */
  network: string = '';
  /** ws 路径 */
  wsPath: string = '';
  /** ws Host */
  wsHost: string = '';
  /** 流控（vless） */
  flow: string = '';
  /** 指纹 */
  fingerprint: string = 'chrome';
  /** 备注（展示名） */
  remark: string = '';
  /** 所属分组 id */
  groupId: string = '';
  /** 延迟（ms），-1 表示未测试 */
  latency: number = -1;
  /** 是否启用 */
  enable: boolean = true;
  /** 排序权重 */
  index: number = 0;

  constructor(tag: string = '', type: string = '', server: string = '', serverPort: number = 0) {
    this.tag = tag;
    this.type = type;
    this.server = server;
    this.serverPort = serverPort;
  }

  /** 生成 sing-box outbound tag */
  getOutboundTag(): string {
    return this.tag;
  }

  /** 生成 sing-box outbound 配置 */
  toOutbound(): JsonMap {
    const outbound: JsonMap = {
      'type': this.type,
      'tag': this.tag,
      'server': this.server,
      'server_port': this.serverPort
    };
    if (this.password.length > 0) {
      outbound['password'] = this.password;
    }
    if (this.uuid.length > 0) {
      outbound['uuid'] = this.uuid;
    }
    if (this.method.length > 0) {
      outbound['method'] = this.method;
    }
    if (this.type === 'vless') {
      outbound['flow'] = this.flow;
    }
    if (this.tls) {
      const utls: JsonMap = {
        'enabled': true,
        'fingerprint': this.fingerprint
      };
      const tlsObj: JsonMap = {
        'enabled': true,
        'server_name': this.wsHost.length > 0 ? this.wsHost : this.server,
        'utls': utls
      };
      outbound['tls'] = tlsObj;
      if (this.network === 'ws' || this.network === 'grpc' || this.network === 'httpupgrade') {
        const transportObj: JsonMap = {
          'type': this.network,
          'path': this.wsPath,
          'host': this.wsHost
        };
        outbound['transport'] = transportObj;
      }
    }
    return outbound;
  }
}
