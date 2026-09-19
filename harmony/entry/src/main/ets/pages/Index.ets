
import { HomePage } from './HomePage';
import { ProfilesPage } from './ProfilesPage';
import { SettingsPage } from './SettingsPage';

/**
 * 主页面：底部 Tab 导航（首页 / 订阅 / 设置）
 * 对应 Karing 的 HomeScreen + 主导航
 */
@Entry
@Component
export struct Index {
  @State currentIndex: number = 0;

  @Builder
  tabBarBuilder(index: number, title: string, icon: Resource) {
    Column({ space: 4 }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? '#0A59F7' : '#999999')
      Text(title)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? '#0A59F7' : '#666666')
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.tabBarBuilder(0, '首页', $r('app.media.app_icon')))

      TabContent() {
        ProfilesPage()
      }
      .tabBar(this.tabBarBuilder(1, '订阅', $r('app.media.app_icon')))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.tabBarBuilder(2, '设置', $r('app.media.app_icon')))
    }
    .scrollable(false)
    .barHeight(56)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .backgroundColor('#FFFFFF')
  }
}
