import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/platform/system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exitFullscreen 交还系统方向策略（不锁竖屏）', (tester) async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await exitFullscreen();

    final orientationCalls = calls
        .where((call) => call.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(orientationCalls, isNotEmpty);
    expect(orientationCalls.last.arguments, isEmpty);
  });

  testWidgets('enterFullscreen 允许横屏', (tester) async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    await enterFullscreen();

    final orientationCalls = calls
        .where((call) => call.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(orientationCalls, isNotEmpty);
    expect(orientationCalls.last.arguments, contains('DeviceOrientation.landscapeLeft'));
  });
}
