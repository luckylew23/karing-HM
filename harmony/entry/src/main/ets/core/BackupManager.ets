import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const TAG = 'BackupManager';

/**
 * 备份管理器
 * 将配置文件打包上传到 WebDAV，或从备份恢复
 */
export class BackupManager {
  /** 生成备份文件名 */
  static getBackupFileName(): string {
    const now: Date = new Date();
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    const stamp: string = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    return `karing-backup-${stamp}.json`;
  }

  /** 收集需要备份的文件内容 */
  static collectBackupFiles(filesDir: string): Map<string, string> {
    const files: Map<string, string> = new Map<string, string>();
    const toBackup: string[] = ['server_config.json', 'singbox_config.json'];
    for (const name of toBackup) {
      try {
        const path: string = filesDir + '/' + name;
        const stat = fileIo.statSync(path);
        const buf = new ArrayBuffer(stat.size);
        const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        fileIo.readSync(f.fd, buf);
        fileIo.closeSync(f);
        const decoder = util.TextDecoder.create('utf-8');
        files.set(name, decoder.decodeToString(new Uint8Array(buf)));
      } catch (e) {
        hilog.warn(0x0000, TAG, 'skip %{public}s', name);
      }
    }
    return files;
  }
}
