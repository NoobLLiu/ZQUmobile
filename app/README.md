# 掌上砚园

肇庆学院校园助手（Android / Flutter）。提供教务系统登录与课表导入查看功能。

## 功能

| 功能 | 说明 |
|------|------|
| 首页 | 功能入口宫格，可进入课表、教务系统登录等模块 |
| 课表 | 拾光课表风格的周视图网格，支持周次切换、课程详情、冲突并排展示 |
| 教务系统 | 内嵌 WebView 登录肇庆学院教务系统，登录后一键导入课表 |
| 我的 | 登录状态、课表数据管理、清空缓存、开源许可 |

### 导航结构

底部导航为 **首页** / **我的**，各功能模块从首页宫格进入。

## 课表数据来源

采用与 [拾光课程表](https://github.com/ShiGuangSchedule/shiguangschedule) 相同的方式：

1. App 内嵌 WebView 打开教务登录页（校外走 WebVPN，校内可直连）；
2. 用户自行完成登录（**图形验证码手动填写**，WebVPN 滑块人工拖动）；
3. 登录后 App 向页面注入 `assets/js/zqu_adapter.js`，在教务系统会话内直接请求课表 JSON 接口：

   ```
   GET {站点根}xsgrkbcx!getKbRq.action?xnxqdm=<学期>&zc=<周次>&xsdm=
   ```

   `zc` 传空表示不限周次，一次可取回整学期排课记录；每条记录自带 `zc` 字段标明上课周次，
   故无需逐周请求。

4. 适配脚本把结果通过 `zsyBridge` 回传 Dart 侧，解析、聚合并落本地缓存。

数据全程在设备本地处理，不经过任何第三方服务器，也不存储账号密码。

## 开发

```bash
# 环境
flutter --version        # 需要 Flutter 3.27+（本项目在 3.47.8 上开发）
flutter pub get

# 静态检查与测试
flutter analyze
flutter test

# 构建
flutter build apk --release
```

> Windows 上若设置了 `http_proxy` / `https_proxy`，跑 `flutter test` 需额外设置
> `NO_PROXY=localhost,127.0.0.1`，否则 `flutter_tester` 的本地 WebSocket 握手会被代理拦截。

## 目录结构

```
app/
├── lib/
│   ├── main.dart                 # App 根 + 底部导航外壳
│   ├── core/grid_style.dart      # 网格样式常量与拾光配色板
│   ├── models/timetable.dart     # 课程 / 节次 / 课表模型
│   ├── services/
│   │   ├── jwgl_service.dart     # ZQU 教务对接：节次/周次解析、课程聚合、合并去重
│   │   └── timetable_repository.dart  # 本地缓存（SharedPreferences）
│   ├── pages/
│   │   ├── home_page.dart        # 首页功能宫格
│   │   ├── mine_page.dart        # 我的
│   │   ├── timetable_page.dart   # 课表页
│   │   └── jwgl_login_page.dart  # 教务系统 WebView 登录与导入
│   └── widgets/schedule_grid.dart # 拾光风格课表网格
├── assets/js/zqu_adapter.js      # 注入 WebView 的取数脚本
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
