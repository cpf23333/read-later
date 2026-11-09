import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'router.dart';

class ReadLaterApp extends ConsumerStatefulWidget {
  const ReadLaterApp({super.key});

  @override
  ConsumerState<ReadLaterApp> createState() => _ReadLaterAppState();
}

class _ReadLaterAppState extends ConsumerState<ReadLaterApp> {
  late final GoRouter _router = createRouter();

  static const _seedColor = Color(0xFF4F6BED);

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: '稍后再看',
      debugShowCheckedModeBanner: false,
      // App 文案本身是中文，框架文案也固定中文（不受系统语言影响）。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
