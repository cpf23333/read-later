import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 视频播放相关偏好。
class VideoSettings {
  /// 检测到直链视频时自动用 Media3 打开。
  final bool autoPlay;

  /// 浏览器是否显示「播放视频」按钮。
  final bool showPlayerButton;

  const VideoSettings({
    this.autoPlay = false,
    this.showPlayerButton = true,
  });

  VideoSettings copyWith({bool? autoPlay, bool? showPlayerButton}) {
    return VideoSettings(
      autoPlay: autoPlay ?? this.autoPlay,
      showPlayerButton: showPlayerButton ?? this.showPlayerButton,
    );
  }
}

/// 视频播放偏好（SharedPreferences 持久化）。
class VideoSettingsController extends Notifier<VideoSettings> {
  static const autoPlayKey = 'video_auto_play';
  static const showPlayerButtonKey = 'video_show_player_button';

  @override
  VideoSettings build() {
    _load();
    return const VideoSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = VideoSettings(
      autoPlay: prefs.getBool(autoPlayKey) ?? false,
      showPlayerButton: prefs.getBool(showPlayerButtonKey) ?? true,
    );
  }

  Future<void> setAutoPlay(bool value) async {
    state = state.copyWith(autoPlay: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoPlayKey, value);
  }

  Future<void> setShowPlayerButton(bool value) async {
    state = state.copyWith(showPlayerButton: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showPlayerButtonKey, value);
  }
}
