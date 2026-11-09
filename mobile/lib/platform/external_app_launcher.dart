import 'package:flutter/services.dart';

const MethodChannel _channel =
    MethodChannel('com.cpf23333.readlater/external');

/// 由 Android 侧解析并启动外部应用（含 intent:// 形式）。
/// 返回是否成功启动；失败时由调用方提示。
Future<bool> launchExternalUrl(String url) async {
  try {
    final result = await _channel.invokeMethod<bool>('launch', {'url': url});
    return result ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
