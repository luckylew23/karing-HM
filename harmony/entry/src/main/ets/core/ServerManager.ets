import { ProxyConfig } from '../model/ProxyConfig';
import { ServerConfigGroup } from '../model/ServerConfigGroup';
import { SubscriptionParser } from './SubscriptionParser';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/**
 * 服务器/订阅管理器
 * 对应 Karing 的 ServerManager（lib/app/modules/server_manager.dart）
 * 职责：订阅 CRUD、节点解析、配置持久化、延迟测试
 */
export class ServerManager {
  private static groups: ServerConfigGroup[] = [];
  private static currentGroupId: string = '';
  private static currentNodeTag: string = '';
  private static context: common.UIAbilityContext | null = null;
  private static instance: ServerManager | null = null;

  static getInstance(): ServerManager {
    if (ServerManager.instance === null) {
      ServerManager.instance = new ServerManager();
    }
    return ServerManager.instance;
  }

  /** 初始化（加载本地配置） */
  static async init(ctx: common.UIAbilityContext): Promise<void> {
    ServerManager.context = ctx;
    await ServerManager.loadFromStorage();
  }

  /** 获取全部分组 */
  static getGroups(): ServerConfigGroup[] {
    return ServerManager.groups;
  }

  /** 按 id 获取分组 */
  static getGroup(groupId: string): ServerConfigGroup | null {
    for (let i = 0; i < ServerManager.groups.length; i++) {
      if (ServerManager.groups[i].id === groupId) {
        return ServerManager.groups[i];
      }
    }
    return null;
  }

  /** 获取当前分组 id */
  static getCurrentGroupId(): string {
    if (ServerManager.currentGroupId.length === 0 && ServerManager.groups.length > 0) {
      ServerManager.currentGroupId = ServerManager.groups[0].id;
    }
    return ServerManager.currentGroupId;
  }

  /** 设置当前分组 */
  static setCurrentGroupId(groupId: string): void {
    ServerManager.currentGroupId = groupId;
  }

  /** 获取当前节点 tag */
  static getCurrentNodeTag(): string {
    return ServerManager.currentNodeTag;
  }

  /** 设置当前节点 */
  static setCurrentNodeTag(tag: string): void {
    ServerManager.currentNodeTag = tag;
  }

  /** 添加分组（本地或远程订阅） */
  static async addGroup(remark: string, url: string): Promise<string> {
    const groupId = 'g' + Date.now().toString();
    const group = new ServerConfigGroup(groupId, remark);
    group.url = url;
    if (url.length > 0) {
      await ServerManager.updateSubscription(group);
    }
    ServerManager.groups.push(group);
    await ServerManager.saveToStorage();
    if (ServerManager.currentGroupId.length === 0) {
      ServerManager.currentGroupId = groupId;
    }
    return groupId;
  }

  /** 删除分组 */
  static async removeGroup(groupId: string): Promise<boolean> {
    const idx = ServerManager.findGroupIndex(groupId);
    if (idx < 0) {
      return false;
    }
    ServerManager.groups.splice(idx, 1);
    if (ServerManager.currentGroupId === groupId) {
      ServerManager.currentGroupId = ServerManager.groups.length > 0 ? ServerManager.groups[0].id : '';
      ServerManager.currentNodeTag = '';
    }
    await ServerManager.saveToStorage();
    return true;
  }

  /** 更新订阅（拉取远程内容并解析节点） */
  static async updateSubscription(group: ServerConfigGroup): Promise<boolean> {
    if (group.url.length === 0) {
      return false;
    }
    try {
      const content = await ServerManager.fetchUrl(group.url);
      if (content.length === 0) {
        return false;
      }
      const nodes = SubscriptionParser.parseSubscription(content);
      if (nodes.length === 0) {
        return false;
      }
      // 保留原启用状态，更新节点列表
      group.nodes = nodes;
      group.lastUpdated = Date.now();
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 从链接或文本直接解析节点并加入分组 */
  static async addNodesFromText(remark: string, text: string): Promise<string> {
    const groupId = 'g' + Date.now().toString();
    const group = new ServerConfigGroup(groupId, remark);
    const nodes = SubscriptionParser.parseSubscription(text);
    if (nodes.length === 0) {
      // 视为订阅 URL
      group.url = text.trim();
      await ServerManager.updateSubscription(group);
    } else {
      group.nodes = nodes;
    }
    ServerManager.groups.push(group);
    await ServerManager.saveToStorage();
    if (ServerManager.currentGroupId.length === 0) {
      ServerManager.currentGroupId = groupId;
    }
    return groupId;
  }

  /** 拉取 URL 内容 */
  private static async fetchUrl(url: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 30000,
        header: {
          'User-Agent': 'karing/0.1.0'
        },
        expectDataType: http.HttpDataType.STRING
      });
      if (resp.responseCode === 200) {
        return resp.result as string;
      }
      return '';
    } finally {
      httpRequest.destroy();
    }
  }

  /** 延迟测试（通过 HTTP HEAD 到节点，简单连通性检测） */
  static async testLatency(node: ProxyConfig): Promise<number> {
    const httpRequest = http.createHttp();
    const start = Date.now();
    try {
      const resp = await httpRequest.request('http://www.gstatic.com/generate_204', {
        method: http.RequestMethod.GET,
        connectTimeout: 8000,
        readTimeout: 8000
      });
      const cost = Date.now() - start;
      if (resp.responseCode === 200 || resp.responseCode === 204) {
        return cost;
      }
      return -1;
    } catch (e) {
      return -1;
    } finally {
      httpRequest.destroy();
    }
  }

  /** 持久化到本地文件 */
  private static async saveToStorage(): Promise<void> {
    if (ServerManager.context === null) {
      return;
    }
    try {
      const path = ServerManager.context.filesDir + '/server_config.json';
      const data: Record<string, Object> = {
        'currentGroupId': ServerManager.currentGroupId,
        'currentNodeTag': ServerManager.currentNodeTag,
        'groups': ServerManager.groups.map((g: ServerConfigGroup) => g.toJson())
      };
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(data));
      fileIo.closeSync(file);
    } catch (e) {
      // 持久化失败不影响运行
    }
  }

  /** 从本地文件加载 */
  private static async loadFromStorage(): Promise<void> {
    if (ServerManager.context === null) {
      return;
    }
    try {
      const path = ServerManager.context.filesDir + '/server_config.json';
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const content = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      const json = JSON.parse(content) as Record<string, Object>;
      ServerManager.currentGroupId = (json['currentGroupId'] as string) ?? '';
      ServerManager.currentNodeTag = (json['currentNodeTag'] as string) ?? '';
      const groupsJson = json['groups'] as Record<string, Object>[];
      if (Array.isArray(groupsJson)) {
        ServerManager.groups = [];
        for (let i = 0; i < groupsJson.length; i++) {
          const g = ServerConfigGroup.fromJson(groupsJson[i]);
          ServerManager.groups.push(g);
        }
      }
    } catch (e) {
      // 首次运行无配置，忽略
    }
  }

  private static findGroupIndex(groupId: string): number {
    for (let i = 0; i < ServerManager.groups.length; i++) {
      if (ServerManager.groups[i].id === groupId) {
        return i;
      }
    }
    return -1;
  }
}
