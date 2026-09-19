import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'WebdavClient';

/**
 * WebDAV 客户端
 * 实现标准 WebDAV 协议：PROPFIND / PUT / GET / DELETE
 */
export class WebdavClient {
  private baseUrl: string;
  private user: string;
  private password: string;

  constructor(baseUrl: string, user: string, password: string) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this.user = user;
    this.password = password;
  }

  private authHeader(): string {
    const cred: string = this.user + ':' + this.password;
    return 'Basic ' + base64Encode(cred);
  }

  private async request(method: string, path: string, body?: ArrayBuffer): Promise<ReqResult> {
    const url: string = this.baseUrl + path;
    const req = http.createHttp();
    const opt: http.HttpRequestOptions = {
      method: method as http.RequestMethod,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
    };
    const headers: Record<string, string> = {};
    headers['Authorization'] = this.authHeader();
    if (method === 'PROPFIND') {
      headers['Depth'] = '1';
    }
    opt.header = headers;
    if (body) {
      opt.extraData = body;
    }
    try {
      const resp = await req.request(url, opt);
      const result: ReqResult = { status: resp.responseCode, body: resp.result as string };
      return result;
    } finally {
      req.destroy();
    }
  }

  /** 连接测试：PROPFIND 根目录 */
  async connect(): Promise<boolean> {
    try {
      const r: ReqResult = await this.request('PROPFIND', '/');
      hilog.info(0x0000, TAG, 'connect status=%{public}d', r.status);
      return r.status >= 200 && r.status < 300;
    } catch (e) {
      hilog.error(0x0000, TAG, 'connect fail: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 列出备份文件 */
  async list(): Promise<string[]> {
    const r: ReqResult = await this.request('PROPFIND', '/');
    if (r.status >= 400) {
      throw new Error('PROPFIND failed: ' + r.status);
    }
    const files: string[] = [];
    const hrefRe = /<[^>]*href[^>]*>([^<]+)<\/[^>]*href[^>]*>/gi;
    let m: RegExpExecArray | null;
    while ((m = hrefRe.exec(r.body)) !== null) {
      const href: string = decodeURIComponent(m[1]);
      const name: string = href.split('/').pop() || '';
      if (name.endsWith('.json') && name.includes('karing-backup')) {
        files.push(name);
      }
    }
    files.sort().reverse();
    return files;
  }

  /** 上传文件 */
  async upload(filename: string, data: ArrayBuffer): Promise<void> {
    const url: string = this.baseUrl + '/' + filename;
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.PUT,
        header: {
          'Authorization': this.authHeader(),
          'Content-Type': 'application/json'
        },
        extraData: data,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      if (resp.responseCode >= 300) {
        throw new Error('PUT failed: ' + resp.responseCode);
      }
    } finally {
      req.destroy();
    }
  }

  /** 下载文件 */
  async download(filename: string): Promise<ArrayBuffer> {
    const url: string = this.baseUrl + '/' + filename;
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': this.authHeader() },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000
      });
      if (resp.responseCode >= 300) {
        throw new Error('GET failed: ' + resp.responseCode);
      }
      return resp.result as ArrayBuffer;
    } finally {
      req.destroy();
    }
  }

  /** 删除文件 */
  async delete(filename: string): Promise<void> {
    const r: ReqResult = await this.request('DELETE', '/' + filename);
    if (r.status >= 300) {
      throw new Error('DELETE failed: ' + r.status);
    }
  }
}

class ReqResult {
  status: number = 0;
  body: string = '';
}

function base64Encode(s: string): string {
  const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result: string = '';
  let i: number = 0;
  while (i < s.length) {
    const a: number = s.charCodeAt(i++);
    const b: number = i < s.length ? s.charCodeAt(i++) : -1;
    const c: number = i < s.length ? s.charCodeAt(i++) : -1;
    const bitmap: number = (a << 16) | (b >= 0 ? b << 8 : 0) | (c >= 0 ? c : 0);
    result += chars[(bitmap >> 18) & 63];
    result += chars[(bitmap >> 12) & 63];
    result += b < 0 ? '=' : chars[(bitmap >> 6) & 63];
    result += c < 0 ? '=' : chars[bitmap & 63];
  }
  return result;
}
