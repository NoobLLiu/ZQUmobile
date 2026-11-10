/// 模型来源配置的本地存储。
///
/// 只存本机，不上传。API Key 与其它个人资料一样以明文保存在
/// SharedPreferences 里，界面上会明确告知用户这一点。
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_source.dart';

class AiSourceRepository {
  AiSourceRepository._();

  static const String prefsKey = 'zsy_ai_source';

  /// 读取配置；从未保存过时返回「免费模型」默认值。
  ///
  /// 不做静态缓存：配置页保存后返回通知转写页要立刻看到新值。
  static Future<AiSourceConfig> load() async {
    final sp = await SharedPreferences.getInstance();
    return AiSourceConfig.decode(sp.getString(prefsKey));
  }

  static Future<void> save(AiSourceConfig config) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(prefsKey, config.encode());
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(prefsKey);
  }
}
