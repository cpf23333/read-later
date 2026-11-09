import 'package:flutter/services.dart';

/// 进入网页视频全屏：隐藏系统栏、允许旋转。
Future<void> enterFullscreen() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

/// 退出全屏：恢复系统栏，并把方向策略交还系统（空列表 = 允许自动旋转）。
Future<void> exitFullscreen() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([]);
}
