import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

class ReadLaterApp extends StatefulWidget {
  const ReadLaterApp({super.key});

  @override
  State<ReadLaterApp> createState() => _ReadLaterAppState();
}

class _ReadLaterAppState extends State<ReadLaterApp> {
  late final GoRouter _router = createRouter();

  static const _seedColor = Color(0xFF4F6BED);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '稍后再看',
      debugShowCheckedModeBanner: false,
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
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
