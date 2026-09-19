import { ProxyConfig } from '../model/ProxyConfig';
import { util } from '@kit.ArkTS';

/** host:port 解析结果 */
export interface HostPort {
  host: string;
  port: number;
}

/**
 * 订阅解析器
 * 支持：base64 订阅（ss:// vmess:// vless:// trojan:// hysteria2://）、
 * Clash YAML 订阅（部分）、sing-box JSON 订阅
 */
export class SubscriptionParser {
  /** 解析整个订阅文本，返回节点列表 */
  static parseSubscription(content: string): ProxyConfig[] {
    const trimmed = content.trim();
    if (trimmed.length === 0) {
      return [];
    }
    // 尝试 JSON（sing-box 格式）
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      const jsonNodes = SubscriptionParser.tryParseJson(trimmed);
      if (jsonNodes.length > 0) {
        return jsonNodes;
      }
    }
    // 尝试 base64 解码（SS 订阅常见）
    let decoded = content;
    if (!trimmed.includes('\n') && !trimmed.includes('://')) {
      const b64 = SubscriptionParser.tryBase64Decode(trimmed);
      if (b64.length > 0) {
        decoded = b64;
      }
    }
    // 按行解析 URI
    const nodes: ProxyConfig[] = [];
    const lines = decoded.split('\n');
    let index = 0;
    for (let line of lines) {
      line = line.trim();
      if (line.length === 0) {
        continue;
      }
      const node = SubscriptionParser.parseUriLine(line, index);
      if (node !== null) {
        nodes.push(node);
        index++;
      }
    }
    return nodes;
  }

  /** 解析单行节点 URI */
  static parseUriLine(line: string, index: number): ProxyConfig | null {
    const schemeMatch = line.match(/^([a-zA-Z0-9]+):\/\//);
    if (schemeMatch === null) {
      return null;
    }
    const scheme = schemeMatch[1].toLowerCase();
    if (scheme === 'ss') {
      return SubscriptionParser.parseSs(line, index);
    }
    if (scheme === 'vmess') {
      return SubscriptionParser.parseVmess(line, index);
    }
    if (scheme === 'vless') {
      return SubscriptionParser.parseVless(line, index);
    }
    if (scheme === 'trojan') {
      return SubscriptionParser.parseTrojan(line, index);
    }
    if (scheme === 'hysteria2' || scheme === 'hy2') {
      return SubscriptionParser.parseHysteria2(line, index);
    }
    if (scheme === 'tuic') {
      return SubscriptionParser.parseTuic(line, index);
    }
    return null;
  }

  /** ss:// 解析（支持 base64 userinfo 与明文） */
  private static parseSs(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(5);
    // 处理 #fragment 备注
    let remark = '';
    const hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      remark = SubscriptionParser.decodeURIComponentSafe(rest.substring(hashIdx + 1));
    }
    const main = hashIdx >= 0 ? rest.substring(0, hashIdx) : rest;
    let userInfo = main;
    let hostPart = '';
    const atIdx = main.lastIndexOf('@');
    if (atIdx >= 0) {
      userInfo = main.substring(0, atIdx);
      hostPart = main.substring(atIdx + 1);
    } else {
      // 无 @，可能整体是 base64：method:password@host:port
      const decoded = SubscriptionParser.tryBase64Decode(main);
      if (decoded.length > 0 && decoded.includes('@')) {
        const at2 = decoded.lastIndexOf('@');
        userInfo = decoded.substring(0, at2);
        hostPart = decoded.substring(at2 + 1);
      }
    }
    let method = '';
    let password = '';
    const colonIdx = userInfo.indexOf(':');
    if (colonIdx >= 0) {
      method = userInfo.substring(0, colonIdx);
      password = userInfo.substring(colonIdx + 1);
    } else {
      // userinfo 是 base64
      const decoded2 = SubscriptionParser.tryBase64Decode(userInfo);
      const colon2 = decoded2.indexOf(':');
      if (colon2 >= 0) {
        method = decoded2.substring(0, colon2);
        password = decoded2.substring(colon2 + 1);
      }
    }
    const host = SubscriptionParser.parseHostPort(hostPart);
    if (host.host.length === 0 || method.length === 0) {
      return null;
    }
    const node = new ProxyConfig('ss-' + index, 'shadowsocks', host.host, host.port);
    node.method = method;
    node.password = password;
    node.remark = remark.length > 0 ? remark : node.tag;
    node.tag = node.remark;
    return node;
  }

  /** vmess:// 解析（JSON payload 或 base64 JSON） */
  private static parseVmess(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(8);
    const decoded = SubscriptionParser.tryBase64Decode(rest);
    if (decoded.length === 0 || !decoded.startsWith('{')) {
      return null;
    }
    try {
      const json = JSON.parse(decoded) as Record<string, Object>;
      const alterId = json['alterId'] as number;
      const port = json['port'] as number;
      const node = new ProxyConfig('', 'vmess', json['add'] as string, port);
      node.uuid = json['id'] as string;
      node.method = (alterId === undefined || alterId <= 0) ? 'chacha20-poly1305' : 'auto';
      node.network = (json['net'] as string) ?? 'tcp';
      node.wsPath = (json['path'] as string) ?? '';
      node.wsHost = (json['host'] as string) ?? '';
      node.tls = (json['tls'] as string) === 'tls';
      node.remark = (json['ps'] as string) ?? node.tag;
      node.tag = node.remark;
      return node;
    } catch (e) {
      return null;
    }
  }

  /** vless:// 解析 */
  private static parseVless(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(8);
    const atIdx = rest.lastIndexOf('@');
    if (atIdx < 0) {
      return null;
    }
    const uuid = rest.substring(0, atIdx);
    const hostPart = rest.substring(atIdx + 1);
    let host = hostPart;
    let queryStr = '';
    const qIdx = hostPart.indexOf('?');
    if (qIdx >= 0) {
      host = hostPart.substring(0, qIdx);
      queryStr = hostPart.substring(qIdx + 1);
    }
    let remark = '';
    const hashIdx = host.indexOf('#');
    if (hashIdx >= 0) {
      remark = SubscriptionParser.decodeURIComponentSafe(host.substring(hashIdx + 1));
      host = host.substring(0, hashIdx);
    }
    const hp = SubscriptionParser.parseHostPort(host);
    if (hp.host.length === 0) {
      return null;
    }
    const node = new ProxyConfig('', 'vless', hp.host, hp.port);
    node.uuid = uuid;
    node.flow = SubscriptionParser.getQueryParam(queryStr, 'flow');
    node.network = SubscriptionParser.getQueryParam(queryStr, 'type') ?? 'tcp';
    node.wsPath = SubscriptionParser.getQueryParam(queryStr, 'path') ?? '';
    node.wsHost = SubscriptionParser.getQueryParam(queryStr, 'host') ?? '';
    node.tls = (SubscriptionParser.getQueryParam(queryStr, 'security') ?? '') === 'tls';
    node.fingerprint = SubscriptionParser.getQueryParam(queryStr, 'fp') ?? 'chrome';
    node.remark = remark.length > 0 ? remark : node.tag;
    node.tag = node.remark;
    return node;
  }

  /** trojan:// 解析 */
  private static parseTrojan(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(9);
    const atIdx = rest.lastIndexOf('@');
    if (atIdx < 0) {
      return null;
    }
    const password = rest.substring(0, atIdx);
    const hostPart = rest.substring(atIdx + 1);
    let host = hostPart;
    let queryStr = '';
    const qIdx = hostPart.indexOf('?');
    if (qIdx >= 0) {
      host = hostPart.substring(0, qIdx);
      queryStr = hostPart.substring(qIdx + 1);
    }
    let remark = '';
    const hashIdx = host.indexOf('#');
    if (hashIdx >= 0) {
      remark = SubscriptionParser.decodeURIComponentSafe(host.substring(hashIdx + 1));
      host = host.substring(0, hashIdx);
    }
    const hp = SubscriptionParser.parseHostPort(host);
    if (hp.host.length === 0) {
      return null;
    }
    const node = new ProxyConfig('', 'trojan', hp.host, hp.port);
    node.password = password;
    node.tls = true;
    node.wsHost = SubscriptionParser.getQueryParam(queryStr, 'sni');
    node.network = SubscriptionParser.getQueryParam(queryStr, 'type') ?? 'tcp';
    node.wsPath = SubscriptionParser.getQueryParam(queryStr, 'path') ?? '';
    node.fingerprint = SubscriptionParser.getQueryParam(queryStr, 'fp') ?? 'chrome';
    node.remark = remark.length > 0 ? remark : node.tag;
    node.tag = node.remark;
    return node;
  }

  /** hysteria2:// 解析 */
  private static parseHysteria2(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(line.indexOf('://') + 3);
    let host = rest;
    let queryStr = '';
    const qIdx = host.indexOf('?');
    if (qIdx >= 0) {
      host = host.substring(0, qIdx);
      queryStr = rest.substring(qIdx + 1);
    }
    let remark = '';
    const hashIdx = host.indexOf('#');
    if (hashIdx >= 0) {
      remark = SubscriptionParser.decodeURIComponentSafe(host.substring(hashIdx + 1));
      host = host.substring(0, hashIdx);
    }
    const hp = SubscriptionParser.parseHostPort(host);
    if (hp.host.length === 0) {
      return null;
    }
    const node = new ProxyConfig('', 'hysteria2', hp.host, hp.port);
    node.password = SubscriptionParser.getQueryParam(queryStr, 'password') ?? '';
    node.wsHost = SubscriptionParser.getQueryParam(queryStr, 'sni');
    node.remark = remark.length > 0 ? remark : node.tag;
    node.tag = node.remark;
    return node;
  }

  /** tuic:// 解析 */
  private static parseTuic(line: string, index: number): ProxyConfig | null {
    const rest = line.substring(7);
    const atIdx = rest.lastIndexOf('@');
    if (atIdx < 0) {
      return null;
    }
    const uuid = rest.substring(0, atIdx);
    const hostPart = rest.substring(atIdx + 1);
    let host = hostPart;
    let queryStr = '';
    const qIdx = hostPart.indexOf('?');
    if (qIdx >= 0) {
      host = hostPart.substring(0, qIdx);
      queryStr = hostPart.substring(qIdx + 1);
    }
    let remark = '';
    const hashIdx = host.indexOf('#');
    if (hashIdx >= 0) {
      remark = SubscriptionParser.decodeURIComponentSafe(host.substring(hashIdx + 1));
      host = host.substring(0, hashIdx);
    }
    const hp = SubscriptionParser.parseHostPort(host);
    if (hp.host.length === 0) {
      return null;
    }
    const node = new ProxyConfig('', 'tuic', hp.host, hp.port);
    node.uuid = uuid;
    node.password = SubscriptionParser.getQueryParam(queryStr, 'password') ?? '';
    node.wsHost = SubscriptionParser.getQueryParam(queryStr, 'sni');
    node.remark = remark.length > 0 ? remark : node.tag;
    node.tag = node.remark;
    return node;
  }

  /** 尝试解析 sing-box JSON 订阅 */
  private static tryParseJson(content: string): ProxyConfig[] {
    try {
      const json = JSON.parse(content) as Record<string, Object>;
      const outbounds = json['outbounds'];
      if (Array.isArray(outbounds)) {
        const nodes: ProxyConfig[] = [];
        for (let i = 0; i < outbounds.length; i++) {
          const ob = outbounds[i] as Record<string, Object>;
          const type = ob['type'] as string;
          if (type === 'direct' || type === 'block' || type === 'dns' || type === 'selector' ||
            type === 'urltest' || type === 'ssh') {
            continue;
          }
          const port = ob['server_port'] as number;
          const node = new ProxyConfig('', type, ob['server'] as string, port);
          node.tag = ob['tag'] as string;
          node.remark = node.tag;
          node.password = (ob['password'] as string) ?? '';
          node.uuid = (ob['uuid'] as string) ?? '';
          node.method = (ob['method'] as string) ?? '';
          nodes.push(node);
        }
        return nodes;
      }
    } catch (e) {
      return [];
    }
    return [];
  }

  /** 解析 host:port */
  private static parseHostPort(hostPart: string): HostPort {
    const trimmed = hostPart.trim();
    if (trimmed.length === 0) {
      return { host: '', port: 0 };
    }
    // IPv6 形式 [::1]:port
    if (trimmed.startsWith('[')) {
      const closeIdx = trimmed.indexOf(']');
      if (closeIdx > 0) {
        const host = trimmed.substring(1, closeIdx);
        const portStr = trimmed.substring(closeIdx + 1).replace(':', '');
        const port = parseInt(portStr);
        return { host: host, port: Number.isNaN(port) ? 0 : port };
      }
    }
    const colonIdx = trimmed.lastIndexOf(':');
    if (colonIdx > 0) {
      const host = trimmed.substring(0, colonIdx);
      const portStr = trimmed.substring(colonIdx + 1);
      const port = parseInt(portStr);
      return { host: host, port: Number.isNaN(port) ? 0 : port };
    }
    return { host: trimmed, port: 0 };
  }

  /** base64 解码（容错） */
  static tryBase64Decode(input: string): string {
    const cleaned = input.replace(/[\r\n\s]/g, '');
    try {
      const base64 = new util.Base64Helper();
      const bytes = base64.decodeSync(cleaned);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (e) {
      return '';
    }
  }

  /** 安全的 URI 解码 */
  static decodeURIComponentSafe(input: string): string {
    try {
      return decodeURIComponent(input);
    } catch (e) {
      return input;
    }
  }

  /** 从 query string 中取参数 */
  static getQueryParam(queryStr: string, key: string): string {
    const parts = queryStr.split('&');
    for (let i = 0; i < parts.length; i++) {
      const kv = parts[i].split('=');
      if (kv.length === 2 && kv[0] === key) {
        return SubscriptionParser.decodeURIComponentSafe(kv[1]);
      }
      if (kv.length === 1 && kv[0] === key) {
        return '';
      }
    }
    return '';
  }
}
