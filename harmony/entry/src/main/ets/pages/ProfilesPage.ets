
import { ServerManager } from '../core/ServerManager';
import { ServerConfigGroup } from '../model/ServerConfigGroup';

/**
 * 订阅管理页：分组列表 + 添加订阅
 * 对应 Karing 的 my_profiles_screen.dart
 */
@Component
export struct ProfilesPage {
  @State groups: ServerConfigGroup[] = [];
  @State showAddDialog: boolean = false;
  @State inputRemark: string = '';
  @State inputUrl: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.groups = ServerManager.getGroups();
  }

  async onAddGroup(): Promise<void> {
    if (this.inputRemark.trim().length === 0) {
      this.inputRemark = '订阅 ' + (this.groups.length + 1);
    }
    const groupId = await ServerManager.addGroup(this.inputRemark.trim(), this.inputUrl.trim());
    this.showAddDialog = false;
    this.inputRemark = '';
    this.inputUrl = '';
    this.reload();
    if (groupId.length > 0) {
      ServerManager.setCurrentGroupId(groupId);
    }
  }

  async onRemoveGroup(groupId: string): Promise<void> {
    await ServerManager.removeGroup(groupId);
    this.reload();
  }

  @Builder
  addDialog() {
    Column({ space: 12 }) {
      Text('添加订阅')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')

      TextInput({ placeholder: '备注名称（如：机场A）', text: this.inputRemark })
        .width('100%')
        .height(44)
        .onChange((value: string) => {
          this.inputRemark = value;
        })

      TextInput({ placeholder: '订阅链接或节点内容（URL / base64 / vmess 等）', text: this.inputUrl })
        .width('100%')
        .height(44)
        .onChange((value: string) => {
          this.inputUrl = value;
        })

      Row({ space: 12 }) {
        Button('取消')
          .type(ButtonType.Normal)
          .fontColor('#666666')
          .layoutWeight(1)
          .onClick(() => {
            this.showAddDialog = false;
          })
        Button('添加')
          .type(ButtonType.Normal)
          .fontColor('#FFFFFF')
          .backgroundColor('#0A59F7')
          .layoutWeight(1)
          .onClick(() => {
            this.onAddGroup();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('86%')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }

  build() {
    Column({ space: 0 }) {
      // 标题栏
      Row() {
        Text('订阅管理')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Blank()
        Button('+ 添加')
          .type(ButtonType.Normal)
          .fontColor('#0A59F7')
          .backgroundColor('#E8F0FE')
          .onClick(() => {
            this.showAddDialog = true;
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 分组列表
      if (this.groups.length === 0) {
        Column({ space: 8 }) {
          Text('暂无订阅')
            .fontSize(16)
            .fontColor('#666666')
          Text('点击右上角「+ 添加」导入订阅链接或节点')
            .fontSize(13)
            .fontColor('#999999')
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.groups, (group: ServerConfigGroup) => {
            ListItem() {
              Column({ space: 8 }) {
                Row() {
                  Text(group.remark)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1A1A1A')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(group.nodes.length + ' 节点')
                    .fontSize(12)
                    .fontColor('#0A59F7')
                    .backgroundColor('#E8F0FE')
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                }
                .width('100%')

                if (group.url.length > 0) {
                  Text(group.url)
                    .fontSize(12)
                    .fontColor('#999999')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }

                Row() {
                  Text(group.lastUpdated > 0 ? '更新于 ' + new Date(group.lastUpdated).toLocaleString() : '尚未更新')
                    .fontSize(12)
                    .fontColor('#999999')
                  Blank()
                  Button('删除')
                    .type(ButtonType.Normal)
                    .fontColor('#E64340')
                    .fontSize(12)
                    .backgroundColor('#FDECEC')
                    .height(28)
                    .onClick(() => {
                      this.onRemoveGroup(group.id);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .onClick(() => {
                ServerManager.setCurrentGroupId(group.id);
                this.reload();
              })
            }
          }, (group: ServerConfigGroup) => group.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 14, right: 14 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F6FA')
    .bindContentCover(this.showAddDialog, this.addDialog(), {
      backgroundColor: '#66000000'
    })
  }
}
