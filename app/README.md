# 掌上砚园

肇庆学院校园助手（Android / Flutter）。提供教务系统登录、课表导入查看、AI 通知转写等功能。

## 功能

| 功能 | 说明 |
|------|------|
| 功能页 | 功能入口按「学习功能 / 班委工作 / 校园生活」分类展示 |
| 课表 | 拾光课表风格的周视图网格，支持周次切换、课程详情、冲突并排展示；可从这里重新同步课表 |
| 教务系统 | 内嵌 WebView **自动登录**肇庆学院教务系统（校内直连 / WebVPN） |
| 通知转写 | 粘贴班委群通知，AI 按班级群口吻改写（DeepSeek），可复制直接发班群 |
| 我的 | 个人信息、课表数据管理、**验证码训练**、清空缓存、开源许可 |

### 导航结构

底部导航为 **看板** / **功能** / **设置**，默认停在「看板」，各功能模块从「功能」进入。
「功能」按「学习功能（我的课表、教务系统）/ 班委工作（通知转写）/ 校园生活（水电余额、快递站状态）」分组，
顶部只保留「掌上砚园」标题。
功能页的「教务系统」只做登录，**导入课表需进入「我的课表」后点击重新同步**。

## 课表数据来源

采用与 [拾光课程表](https://github.com/ShiGuangSchedule/shiguangschedule) 相同的方式：

1. App 内嵌 WebView 打开教务登录页（校外走 WebVPN，校内可直连）；
2. 首次启动时填写学号与**两套密码**（WebVPN、教务系统各一套，仅存本机）；
   之后打开登录页即进入**自动登录**：盖一层「自动登录中」的小弹窗，
   由 `assets/js/auto_login.js` 代填账号密码、点登录，
   WebVPN 滑块由 `assets/js/webvpn_captcha_solver.js` 自动完成，
   自动点进 WebVPN 首页里的「教务系统」入口，
   直到进入教务系统主页才收起弹窗；
   教务的图形验证码是随机旋转的 4~6 位字符，**能否代填取决于有没有训练样本**：
   训练过就能离线识别后直接代填，没训练或识别没把握则在弹窗里显示图片，
   由用户看一眼输入（位数输满自动提交）；
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

数据全程在设备本地处理，不经过任何第三方服务器。
学号与两套密码保存在本机 `shared_preferences`（`zsy_profile`），只用于登录时代填，
不上传、不发往任何服务器。

## 验证码识别

教务系统的图形验证码不是标准字体（实测与 10 种 Windows 字体最佳相关仅 0.54~0.60），
无法用字体合成训练数据，只能靠真实样本。App **内置了一份预置训练集**
（`assets/captcha_templates.json`，467 个字形、由 310 张真实验证码标注构建），
首次启动自动播种到本机，装上即有识别能力，无需先去训练页：

1. 登录时先离线识别，有把握直接代填提交；**没把握就自动换一张再认**
   （最多换 4 张，多数登录在前 1~2 张就能认准），换图次数用完才退回手动；
2. 退回手动时会把识别猜测填进输入框，用户核对一眼即可提交；
3. 一轮登录最多自动提交 2 次，避免把账号试到锁定；
4. 每次登录教务成功，也会自动把那一张验证码收为样本（标签由教务确认，不会污染模板），
   样本越用越准；「我的 → 验证码训练」可以手动补充或查看自检准确率。

算法在 `lib/services/captcha_ocr.dart`：亮度阈值 → 形态学去噪 → 连通域切字 →
粘连字块按中位宽拆分 → 按字块中心最小二乘摆正（验证码整体倾斜约 ±6°）→
裁字归一化到 24×24 → 与每类质心（按类 1~3 簇 k-means）算归一化相关，
每个字形再做 ±4°/±8° 小角度 TTA 取最高分；要求「最高分 ≥0.70 且领先次高 ≥0.06」。

实测（310 张真实验证码，467 字形）：整串自动代填触发率 ~49%（TTA 前 22%），
配合自动换图累计 ~96% 的登录无需完整手输验证码。

样本只存本机 `shared_preferences`（`zsy_captcha_templates`），不上传。
重建预置集：`dart run tool/build_captcha_templates.dart`。

## 通知转写（AI 改写）

班委的日常痛点：老师/辅导员发的通知是写给「各位带班」的，要转发到班级群得自己改称谓、
删掉「请帮忙转发」、补问候语、还要保留原文的排版格式。这个页面把这件事交给 AI。

做法是把「班委通知转写」skill 的规则整段写进系统提示词
（`lib/services/notice_rewrite_prompt.dart`，与 skill 规则一字不差），
页面上只让用户选有限几项，其余交给规则：

> **使用示例**：第一次进页面会自动弹一次（前后对照图 + 三步说明），
> 之后点标题栏的 `?` 随时再看；弹窗里的「填入示例」可以把示例原文和选项一键填好，
> 不想自己编内容时直接点「开始转写」就能看到效果。
> 示例图由 `tool/example_figure.html` 经 Edge 无头模式截图生成
> （`assets/images/notice_example.png`），改文案后重截即可。

| 选项 | 作用 |
|---|---|
| 消息来源 | 决定标题行：【转发（辅导员）关于xx的通知】/【转发关于xx的通知】/【关于xx的通知】 |
| 问好时间 | 早上好[太阳] / 中午好[太阳] / 下午好[太阳] / 傍晚好🌇 / 晚上好🌙，或按当前时间自动取 |
| 问好对象 | 法学5班的同学们 / 同学们 / 各位同学，与问候语拼成整句 |
| 截止时间 | 保持原样，或统一替换为新时间（「原时间→新时间」只改一处） |
| 补充通知 | 0~N 条，每条可选「融入原通知」或「接在正文下面」 |

硬规则（提示词里写死的）：只改外壳，时间/地点/邮箱/链接/命名规则逐字保留；
正文与结尾不得再出现「转发」；问候段、正文各段、结尾段行首恰好两个半角空格；
①②③/⭕/⚠️ 条目行与括号说明行顶格。

### 关于 API Key

模型走用户自己的账号：在「我的 → 模型来源」（或通知转写页右上角）里
选厂商并填入 API Key，支持 DeepSeek 官方、智谱 GLM、月之暗面 Kimi、
小米 MiMo（按量计费 / TokenPlan 两个通道），也可以选「自定义」接入任何
OpenAI 兼容服务。

**App 不内置任何 API Key**：早期参赛版本曾内置演示用 Key
（掩码存储于 `lib/core/ai_credentials.dart`），现已整体移除，
所有请求都用用户自己填写的 Key，Key 只保存在本机。

联调脚本（会真实调用接口、消耗额度，Key 从环境变量读取）：

```bash
cd app && DEEPSEEK_API_KEY=sk-xxx dart run tool/smoke_notice.dart
```

它会把拼好的用户消息、模型输出、以及「标题行是否顶格 / 缩进是否合规 / 是否残留转发字样」
的检查结果一并打出来，改提示词后跑一次就知道有没有改坏。

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

## 快递站数据热更新

「快递站状态」页的全部内容（分组、位置、名称、营业时间、备注、底部说明）
都放在仓库根的 **`data/express_stations.json`**，代码里不再硬编码。

**为什么放仓库文件、不放 Release 附件**：这份数据的改动频率远高于发版，
而 Gitee 的 `latest` Release 是整删整建、还挂着 3 个约 19 MB 的 APK；
为了改一行营业时间就重建 Release 并重传安装包不划算。仓库文件改完即生效、
有提交历史可回溯，匿名 raw 直链可直接被 App 读取；`version.json` 仍留在
Release 里只负责 APK 版本更新，两者互不干扰。

三条链路：

1. **出厂初始包**：`dart tool/gen_express_stations.dart` 把数据源写成
   `app/assets/express_stations.json` 与 `lib/generated/express_stations_bundled.dart`
   （两者内容一致，均提交入库）。CI 每次编译前会重跑一遍，
   所以新装用户拿到的安装包里一定带最新数据。
2. **运行时热更新**：App 进页先显示出厂数据，随后静默拉取
   `https://gitee.com/NoobLLiu/ZQUmobile/raw/master/data/express_stations.json`，
   失败退到 GitHub raw，再失败退本地缓存；`revision` 更高才覆盖并写入
   `SharedPreferences`（6 小时内不重复请求）。AppBar 的云下载按钮可强制刷新。
3. **同步到 Gitee**：推 `data/express_stations.json` 到 `main` 后，
   `sync-gitee.yml` 会立即用 Contents API 把该文件写到 Gitee 仓库同路径；
   本机也可以双击 `tool/gitee_sync/仅同步快递站数据.bat`（只传几 KB，
   不动 Release），或双击 `一键同步到Gitee.bat`（数据 + Release 一起同步）。
   内容没变时脚本会直接跳过，是幂等的。

改数据只需编辑 `data/express_stations.json`，**把 `revision` 加 1、更新
`updatedAt`**，其余字段留空表示「待补充」。本机改完跑一次生成脚本再提交，
即可保证出厂包与线上数据一致。

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
│   │   ├── notice_rewrite_prompt.dart # 通知转写的系统提示词与选项定义
│   │   ├── deepseek_client.dart  # DeepSeek 流式对话（SSE，可中断）
│   │   └── timetable_repository.dart  # 本地缓存（SharedPreferences）
│   ├── pages/
│   │   ├── home_page.dart        # 功能页分类入口
│   │   ├── mine_page.dart        # 我的
│   │   ├── notice_rewrite_page.dart # 通知转写
│   │   ├── timetable_page.dart   # 课表页
│   │   └── jwgl_login_page.dart  # 教务系统 WebView 登录与导入
│   └── widgets/schedule_grid.dart # 拾光风格课表网格
├── assets/
│   ├── images/notice_example.png  # 通知转写前后对照示例图
│   └── js/
│       ├── zqu_upstream.js         # shiguang_warehouse 上游 ZQU 适配脚本（原文）
│       └── shiguang_bridge_shim.js # 把官方 bridge 调用映射到 Flutter 的适配层
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
- [DeepSeek](https://www.deepseek.com/) —— 通知转写功能的模型服务（`deepseek-flash` / `deepseek-v4-pro`）。
- 「班委通知转写」skill —— 通知转写的规则与提示词来源，本项目的 `notice_rewrite_prompt.dart`
  即由它的规则整理而来。

> 感谢以上项目的作者与贡献者。本仓库仅在自己代码中引用与致谢，不会打扰上游。
