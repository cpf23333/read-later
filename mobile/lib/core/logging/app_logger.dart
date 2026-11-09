import 'package:logger/logger.dart';

/// 统一日志入口：`[ReadLater]` 前缀，便于 adb logcat 过滤。
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger();

  static void d(String message) => _logger.d('[ReadLater] $message');
  static void i(String message) => _logger.i('[ReadLater] $message');
  static void w(String message) => _logger.w('[ReadLater] $message');
  static void e(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.e('[ReadLater] $message', error: error, stackTrace: stackTrace);
}
