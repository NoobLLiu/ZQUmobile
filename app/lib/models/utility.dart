/// 宿舍水电余额数据模型。
library;

/// 电费低余额阈值（度）：低于等于该值时界面标红、提醒服务告警。
const double kLowElectricity = 5.0;

/// 水费低余额阈值（吨）：低于等于该值时界面标红、提醒服务告警。
const double kLowWater = 1.0;

/// 电费是否低于阈值。
bool isElectricityLow(double v) => v <= kLowElectricity;

/// 水费是否低于阈值。
bool isWaterLow(double v) => v <= kLowWater;

/// 一个宿舍房间的水电剩余量。
class UtilityRoom {
  const UtilityRoom({
    required this.roomName,
    required this.electricity,
    required this.water,
  });

  /// 房间全名，如「12栋 507」。
  final String roomName;

  /// 电费剩余量（度）。
  final double electricity;

  /// 水费剩余量（吨）。
  final double water;

  Map<String, dynamic> toJson() => {
    'roomName': roomName,
    'electricity': electricity,
    'water': water,
  };

  factory UtilityRoom.fromJson(Map<String, dynamic> j) => UtilityRoom(
    roomName: (j['roomName'] ?? '').toString(),
    electricity: (j['electricity'] as num?)?.toDouble() ?? 0,
    water: (j['water'] as num?)?.toDouble() ?? 0,
  );
}
