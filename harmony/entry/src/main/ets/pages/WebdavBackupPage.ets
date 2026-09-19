import { WebdavClient } from '../core/WebdavClient';
import { BackupManager } from '../core/BackupManager';
import { SettingsManager } from '../core/SettingsManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const TAG = 'WebdavPage';

/**
 * WebDAV 备份恢复页
 * 对应 Karing 的 BackupAndSyncWebdavScreen
 */
@Entry
@Component
struct WebdavBackupPage {
  @State url: string = '';
  @State user: string = '';
  @State password: string = '';
  @State fileList: string[] = [];
  @State connecting: boolean = false;
  @State uploading: boolean = false;
  @State status: string = '';
  private webdav: WebdavClient | null = null;
  private filesDir: string = '';

  aboutToAppear(): void {
    const s = SettingsManager.getConfig();
    this.url = s.webdavUrl;
    this.user = s.webdavUser;
    this.password = s.webdavPassword;
    const ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    if (this.url.length > 0 && this.user.length > 0) {
      this.connectAndList();
    }
  }

  async connectAndList(): Promise<void> {
    this.connecting = true;
    this.status = '连接中...';
    this.webdav = new WebdavClient(this.url, this.user, this.password);
    try {
      const ok: boolean = await this.webdav.connect();
      if (ok) {
        this.status = '已连接';
        const files: string[] = await this.webdav.list();
        this.fileList = files;
      } else {
        this.status = '连接失败';
      }
    } catch (e) {
      this.status = '错误: ' + JSON.stringify(e);
    }
    this.connecting = false;
  }

  async onBackup(): Promise<void> {
    if (!this.webdav) return;
    this.uploading = true;
    this.status = '备份中...';
    try {
      const files = BackupManager.collectBackupFiles(this.filesDir);
      const obj: Record<string, string> = {};
      files.forEach((v: string, k: string) => { obj[k] = v; });
      const jsonStr: string = JSON.stringify(obj);
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(jsonStr);
      const filename: string = BackupManager.getBackupFileName().replace('.zip', '.json');
      await this.webdav.upload(filename, encoded.buffer as ArrayBuffer);
      this.status = '备份成功: ' + filename;
      await this.connectAndList();
    } catch (e) {
      this.status = '备份失败: ' + JSON.stringify(e);
    }
    this.uploading = false;
  }

  async onRestore(filename: string): Promise<void> {
    if (!this.webdav) return;
    this.status = '恢复中: ' + filename;
    try {
      const data: ArrayBuffer = await this.webdav.download(filename);
      const decoder = util.TextDecoder.create('utf-8');
      const text: string = decoder.decodeToString(new Uint8Array(data));
      hilog.info(0x0000, TAG, 'restored, size=%{public}d', data.byteLength);
      this.status = '恢复成功: ' + filename;
    } catch (e) {
      this.status = '恢复失败: ' + JSON.stringify(e);
    }
  }

  async onDelete(filename: string): Promise<void> {
    if (!this.webdav) return;
    try {
      await this.webdav.delete(filename);
      this.status = '已删除: ' + filename;
      await this.connectAndList();
    } catch (e) {
      this.status = '删除失败: ' + JSON.stringify(e);
    }
  }

  build() {
    Column() {
      Row() {
        Text('WebDAV 备份')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('备份')
          .type(ButtonType.Capsule)
          .fontSize(14)
          .enabled(!this.uploading && this.webdav !== null)
          .onClick(() => this.onBackup())
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Column({ space: 8 }) {
        TextInput({ placeholder: 'WebDAV 地址 https://dav.example.com/dav/', text: this.url })
          .onChange((v: string) => { this.url = v.trim(); })
          .type(InputType.URL)
        TextInput({ placeholder: '用户名', text: this.user })
          .onChange((v: string) => { this.user = v.trim(); })
        TextInput({ placeholder: '密码', text: this.password })
          .type(InputType.Password)
          .onChange((v: string) => { this.password = v.trim(); })
        Button('保存并连接')
          .type(ButtonType.Capsule)
          .width('100%')
          .onClick(() => {
            const s = SettingsManager.getConfig();
            s.webdavUrl = this.url;
            s.webdavUser = this.user;
            s.webdavPassword = this.password;
            this.connectAndList();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 12 })
      .backgroundColor('#FFFFFF')

      if (this.status.length > 0) {
        Text(this.status)
          .fontSize(13)
          .fontColor('#666666')
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 8 })
      }

      List({ space: 1 }) {
        ForEach(this.fileList, (item: string) => {
          ListItem() {
            Row() {
              Text(item)
                .fontSize(14)
                .layoutWeight(1)
              Button('恢复')
                .fontSize(12)
                .onClick(() => this.onRestore(item))
              Button('删除')
                .fontSize(12)
                .fontColor('#FF4444')
                .backgroundColor('#FFEEEE')
                .margin({ left: 8 })
                .onClick(() => this.onDelete(item))
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .backgroundColor('#FFFFFF')
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6FA')
  }
}
