import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/features/settings/video_settings_controller.dart';
import 'package:readlater/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认不自动播放，显示播放按钮', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = container.read(videoSettingsProvider);
    expect(settings.autoPlay, isFalse);
    expect(settings.showPlayerButton, isTrue);
  });

  test('切换后写入 SharedPreferences', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(videoSettingsProvider.notifier);
    await notifier.setAutoPlay(true);
    await notifier.setShowPlayerButton(false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(VideoSettingsController.autoPlayKey), isTrue);
    expect(prefs.getBool(VideoSettingsController.showPlayerButtonKey), isFalse);
  });

  testWidgets('启动时从 SharedPreferences 读取', (tester) async {
    SharedPreferences.setMockInitialValues({
      VideoSettingsController.autoPlayKey: true,
      VideoSettingsController.showPlayerButtonKey: false,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(videoSettingsProvider);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final settings = container.read(videoSettingsProvider);
    expect(settings.autoPlay, isTrue);
    expect(settings.showPlayerButton, isFalse);
  });
}
