# 掌上砚园

肇庆学院校园助手（Android / Flutter）。提供教务系统登录与课表导入查看功能。

## 功能

| 功能 | 说明 |
|------|------|
| 首页 | 功能入口宫格，可进入课表、教务系统登录等模块 |
| 课表 | 拾光课表风格的周视图网格，支持周次切换、课程详情、冲突并排展示；可从这里重新同步课表 |
| 教务系统 | 内嵌 WebView 登录肇庆学院教务系统（校内直连 / WebVPN），仅提供登录与浏览 |
| 我的 | 登录状态、个人信息、课表数据管理、清空缓存、开源许可 |

### 导航结构

底部导航为 **首页** / **我的**，各功能模块从首页宫格进入。
首页的「教务系统」只做登录，**导入课表需进入「我的课表」后点击重新同步**。

## 课表数据来源

采用与 [拾光课程表](https://github.com/ShiGuangSchedule/shiguangschedule) 相同的方式：

1. App 内嵌 WebView 打开教务登录页（校外走 WebVPN，校内可直连）；
2. 用户自行完成登录（**图形验证码手动填写**，WebVPN 滑块人工拖动）；
3. 登录后 App 向页面注入 **shiguang_warehouse 上游 ZQU 适配脚本原文**
   （`assets/js/zqu_upstream.js`，Apache-2.0）＋ 一层桥接 shim
   （`assets/js/shiguang_bridge_shim.js`，只把官方的弹窗/保存调用映射到 Flutter，
   不改动任何取数与解析逻辑），在教务系统会话内直接请求课表 JSON 接口：

   ```
   GET {站点根}xsgrkbcx!getKbRq.action?xnxqdm=<学期>&zc=<周次>&xsdm=
   ```

   `zc` 传空表示不限周次，一次可取回整学期排课记录；每条记录自带 `zc` 字段标明上课周次，
   故无需逐周请求。

4. 官方脚本按「课程 → 学期配置 → 作息时间 → 完成」分四次回传，
   App 逐段累积后一次性落本地缓存。

> 脚本来源固定为上游仓库当前版本，升级适配只需替换 `assets/js/zqu_upstream.js`
> （见该文件头部的来源与改动说明）。

数据全程在设备本地处理，不经过任何第三方服务器，也不存储账号密码。

## 开发

```bash
# 环境
flutter --version        # 需要 Flutter 3.27+（本项目在 3.47.8 上开发）
flutter pub get

# 静态检查与测试
flutter analyze
flutter test
```

> Windows 上若设置了 `http_proxy` / `https_proxy`，跑 `flutter test` 需额外设置
> `NO_PROXY=localhost,127.0.0.1`，否则 `flutter_tester` 的本地 WebSocket 握手会被代理拦截。

## 构建 APK（推荐走 CI）

本项目通过 GitHub Actions 云端构建，产物按 CPU 架构拆成 **3 个 APK**（不套压缩包）。
每个 APK 只带一种 ABI 的 native 库，体积约为整包的 1/3：

| 文件 | 适用设备 | 体积 |
|---|---|---|
| `zhangshangyanyuan-<版本>-arm64-v8a.apk` | 绝大多数手机（约 2017 年后的机型），**一般选这个** | ~19 MB |
| `zhangshangyanyuan-<版本>-armeabi-v7a.apk` | 老款 32 位手机 | ~15 MB |
| `zhangshangyanyuan-<版本>-x86_64.apk` | 仅模拟器 / x86 设备 | ~19 MB |

> 若不拆分，universal 整包会同时打进三种 ABI，实测达 **52 MB**。

- 仓库：<https://github.com/NoobLLiu/ZQUmobile>
- 触发：向 `main` 推送即自动构建，也可在 Actions 页手动触发
- 环境：`windows-latest`（其 Android SDK 镜像已预装 CMake，
  Flutter 新版模板的 `:jni` 模块构建依赖它，ubuntu runner 会因缺 CMake 而失败）
- 流程：pub get → analyze → test → `flutter build apk --release --split-per-abi`
- 下载：Actions 页 → 对应 run → Artifacts（3 个 `.apk` 可直接单独下载，不是 zip）；
  或 Releases 页 `latest` 下的三个 APK 直链

> 本机构建 Gradle 依赖会因代理卡死，因此**不建议本地出包**，以 CI 为准。

本地若确需构建：

```bash
flutter build apk --release --split-per-abi
# 输出：build/app/outputs/flutter-apk/app-<abi>-release.apk
```

## 目录结构

```
app/
├── lib/
│   ├── main.dart                 # App 根 + 底部导航外壳
│   ├── core/grid_style.dart      # 网格样式常量与拾光配色板
│   ├── models/timetable.dart     # 课程 / 节次 / 课表模型
│   ├── services/
│   │   ├── jwgl_service.dart     # 桥接通道消息解析（进度 / 课程 / 配置 / 作息 / 完成）
│   │   └── timetable_repository.dart  # 本地缓存（SharedPreferences）
│   ├── pages/
│   │   ├── home_page.dart        # 首页功能宫格
│   │   ├── mine_page.dart        # 我的
│   │   ├── timetable_page.dart   # 课表页
│   │   └── jwgl_login_page.dart  # 教务系统 WebView 登录与导入
│   └── widgets/schedule_grid.dart # 拾光风格课表网格
├── assets/js/
│   ├── zqu_upstream.js           # shiguang_warehouse 上游 ZQU 适配脚本（原文）
│   └── shiguang_bridge_shim.js   # 把官方 bridge 调用映射到 Flutter 的适配层
└── test/                         # 解析逻辑与界面冒烟测试
```

## 开源致谢

本项目是集锦项目，开发中引入/参考了以下优秀的开源项目（排名不分先后，均未修改其仓库内容）：

- [ShiGuangSchedule/shiguangschedule](https://github.com/ShiGuangSchedule/shiguangschedule) —— 课表网格布局、课程卡片视觉与配色板
  （`ScheduleGridStyle` / `CourseBlock`，Apache-2.0）。本页的网格尺寸（节高 70dp、表头 45dp、左列 40dp）、
  12 组柔和配色、课程名/教师/地点的信息排布与非本周课程的灰化斜纹遮罩，均按其同等视觉实现。
- [ShiGuangSchedule/shiguang_warehouse](https://github.com/ShiGuangSchedule/shiguang_warehouse) —— 官方适配脚本仓库，
  其中 `resources/ZQU/zqu_01.js` 为本项目教务对接逻辑的直接来源（Apache-2.0）。
- Flutter 生态依赖：[flutter](https://flutter.dev)、[webview_flutter](https://pub.dev/packages/webview_flutter)、
  [shared_preferences](https://pub.dev/packages/shared_preferences)。

> 感谢以上项目的作者与贡献者。本仓库仅在自己代码中引用与致谢，不会打扰上游。
