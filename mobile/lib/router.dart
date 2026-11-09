import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/browser/browser_screen.dart';
import 'features/library/library_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/sites/sites_screen.dart';
import 'shared/widgets/adaptive_scaffold.dart';

/// 创建应用路由（每次调用生成独立实例，便于测试）。
GoRouter createRouter() {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AdaptiveScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sites',
                builder: (context, state) => const SitesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/browser',
                builder: (context, state) => const BrowserScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
