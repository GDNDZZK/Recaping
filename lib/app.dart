import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/ai/ai_page.dart';
import 'pages/home/home_page.dart';
import 'pages/playback/playback_page.dart';
import 'pages/record/record_page.dart';
import 'pages/settings/settings_page.dart';
import 'providers/settings_provider.dart';

/// 应用路由配置
///
/// 使用 go_router 管理页面导航。
/// Author: GDNDZZK
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/record',
      builder: (context, state) => const RecordPage(),
    ),
    GoRoute(
      path: '/record/:sessionId',
      builder: (context, state) => RecordPage(
        sessionId: state.pathParameters['sessionId'],
      ),
    ),
    GoRoute(
      path: '/playback/:sessionId',
      builder: (context, state) => PlaybackPage(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/ai/:sessionId',
      builder: (context, state) => AiPage(
        sessionId: state.pathParameters['sessionId']!,
      ),
    ),
  ],
);

/// Recaping 应用根组件
///
/// 使用 [ProviderScope] 包裹整个应用，通过 [Consumer] 监听主题模式变化。
/// 使用 [MaterialApp.router] 配合 [GoRouter] 实现声明式路由。
/// Author: GDNDZZK
class RecapingApp extends StatelessWidget {
  const RecapingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Consumer(
        builder: (context, ref, child) {
          final themeMode = ref.watch(themeModeProvider);
          return MaterialApp.router(
            title: 'Recaping',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6B6BFF),
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6B6BFF),
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: themeMode,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
