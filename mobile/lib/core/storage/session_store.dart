import 'package:shared_preferences/shared_preferences.dart';

/// 浏览器会话数据。
class SessionData {
  final List<String> urls;
  final String? activeUrl;

  const SessionData({required this.urls, this.activeUrl});
}

/// 会话持久化接口（便于测试替换）。
abstract class SessionStore {
  Future<SessionData?> load();
  Future<void> save(SessionData data);
}

/// SharedPreferences 实现。
class SharedPreferencesSessionStore implements SessionStore {
  static const urlsKey = 'browser_tabs';
  static const activeKey = 'browser_active';

  @override
  Future<SessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(urlsKey);
    if (urls == null || urls.isEmpty) return null;
    return SessionData(urls: urls, activeUrl: prefs.getString(activeKey));
  }

  @override
  Future<void> save(SessionData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(urlsKey, data.urls);
    final active = data.activeUrl;
    if (active == null) {
      await prefs.remove(activeKey);
    } else {
      await prefs.setString(activeKey, active);
    }
  }
}
