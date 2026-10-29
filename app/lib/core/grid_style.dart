/// 拾光课表风格的网格样式常量。
///
/// 数值取自拾光课表 `ScheduleGridStyle.DEFAULT`（Apache-2.0），
/// 深色模式的课程底色取自同文件的 `DEFAULT_COLOR_MAPS` 的 dark 分支。
library;

/// 网格样式配置。
class ScheduleGridStyle {
  const ScheduleGridStyle({
    this.timeColumnWidth = 40,
    this.dayHeaderHeight = 45,
    this.sectionHeight = 70,
    this.blockCornerRadius = 4,
    this.blockOuterPadding = 1,
    this.blockInnerPadding = 4,
    this.blockAlpha = 1.0,
  });

  /// 左列（节次轴）宽度。
  final double timeColumnWidth;

  /// 表头（星期 + 日期）高度。
  final double dayHeaderHeight;

  /// 每节课的行高。
  final double sectionHeight;

  /// 课程块圆角。
  final double blockCornerRadius;

  /// 课程块外边距。
  final double blockOuterPadding;

  /// 课程块内边距。
  final double blockInnerPadding;

  /// 课程块不透明度。
  final double blockAlpha;

  /// 默认样式。
  static const ScheduleGridStyle defaultStyle = ScheduleGridStyle();
}

/// 浅色 / 深色一对颜色。
class DualColor {
  const DualColor({required this.light, required this.dark});

  final int light;
  final int dark;
}

/// 拾光课表默认的 12 组柔和课程配色。
///
/// 浅色模式下用柔和浅底 + 深色字；深色模式下用同色系的深底 + 亮字。
const List<DualColor> kDefaultColorMaps = [
  DualColor(light: 0xFFFFCC99, dark: 0xFF663300),
  DualColor(light: 0xFFFFE699, dark: 0xFF664D00),
  DualColor(light: 0xFFE6FF99, dark: 0xFF4D6600),
  DualColor(light: 0xFFCCFF99, dark: 0xFF336600),
  DualColor(light: 0xFF99FFB3, dark: 0xFF00661A),
  DualColor(light: 0xFF99FFE6, dark: 0xFF00664D),
  DualColor(light: 0xFF99FFFF, dark: 0xFF006666),
  DualColor(light: 0xFF99E6FF, dark: 0xFF004D66),
  DualColor(light: 0xFFB399FF, dark: 0xFF1A0066),
  DualColor(light: 0xFFFF99E6, dark: 0xFF66004D),
  DualColor(light: 0xFFFF99CC, dark: 0xFF660033),
  DualColor(light: 0xFFFF99B3, dark: 0xFF66001A),
];
