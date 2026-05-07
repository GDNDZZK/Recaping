import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'pages/ai/ai_page.dart';
import 'pages/home/home_page.dart';
import 'pages/playback/playback_page.dart';
import 'pages/record/record_page.dart';
import 'pages/settings/settings_page.dart';
import 'providers/external_session_provider.dart';
import 'providers/settings_provider.dart';

/// 应用路由配置
///
/// 使用 go_router 管理页面导航。
final router = GoRouter(
  errorBuilder: (context, state) => const HomePage(),
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
      path: '/playback-external/:sessionId',
      builder: (context, state) => PlaybackPage(
        sessionId: state.pathParameters['sessionId']!,
        isExternal: true,
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
/// 使用 [MaterialApp.router] 配合 [GoRouter] 实现声明式路由。
/// 通过 [ConsumerStatefulWidget] 的 [ref] 监听主题模式变化。
/// 监听 [receive_sharing_intent] 处理外部 .recp 文件打开请求。
/// [ProviderScope] 在 [main.dart] 中包裹此组件。
class RecapingApp extends ConsumerStatefulWidget {
  const RecapingApp({super.key});

  @override
  ConsumerState<RecapingApp> createState() => _RecapingAppState();
}

class _RecapingAppState extends ConsumerState<RecapingApp> {
  /// receive_sharing_intent 流订阅
  StreamSubscription? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _setupExternalFileHandler();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  /// 设置外部文件处理
  ///
  /// 监听 [receive_sharing_intent] 的文件流，处理 .recp 文件打开请求。
  /// 包括冷启动（getInitialMedia）和热恢复（getMediaStream）两种场景。
  void _setupExternalFileHandler() {
    debugPrint('[ExternalFile] 设置外部文件处理器');
    // 处理冷启动时的文件打开
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      debugPrint('[ExternalFile] getInitialMedia 返回 ${files.length} 个文件');
      _handleExternalFiles(files);
    });

    // 处理热恢复时的文件打开
    _intentDataStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      debugPrint('[ExternalFile] getMediaStream 收到 ${files.length} 个文件');
      _handleExternalFiles(files);
    });
  }

  /// 处理外部文件列表
  ///
  /// 筛选出 .recp 文件并逐个处理。
  void _handleExternalFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      debugPrint('[ExternalFile] 文件: path=${file.path}, type=${file.type}, mimeType=${file.mimeType}');
      if (file.path.endsWith('.recp')) {
        _handleRecpFile(file.path);
      } else {
        debugPrint('[ExternalFile] 跳过非 .recp 文件: ${file.path}');
      }
    }
  }

  /// 处理单个 .recp 文件
  ///
  /// 通过 [ExternalSessionNotifier] 解压文件并导航到回放页面。
  /// 使用 [ref] 从 ConsumerState 访问 provider。
  void _handleRecpFile(String filePath) {
    debugPrint('[ExternalFile] 开始处理 .recp 文件: $filePath');
    // 在 build 完成后执行，确保 widget 树已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[ExternalFile] addPostFrameCallback 执行, mounted=$mounted');
      try {
        final notifier = ref.read(externalSessionProvider.notifier);
        debugPrint('[ExternalFile] 获取到 notifier，开始处理文件');

        notifier.handleIncomingFile(filePath).then((sessionId) {
          debugPrint('[ExternalFile] handleIncomingFile 返回 sessionId=$sessionId, mounted=$mounted');
          if (sessionId != null && mounted) {
            // 导航到外部会话回放页面
            debugPrint('[ExternalFile] 准备导航到 /playback-external/$sessionId');
            try {
              // 使用 go() 替代 push() 以替换整个导航栈
              // 因为初始路由可能是 errorBuilder 的错误状态
              router.go('/playback-external/$sessionId');
              debugPrint('[ExternalFile] router.go 已调用');
            } catch (e) {
              debugPrint('[ExternalFile] router.push 异常: $e');
            }
          }
        }).catchError((e) {
          debugPrint('[ExternalFile] handleIncomingFile 出错: $e');
        });
      } catch (e) {
        debugPrint('[ExternalFile] _handleRecpFile 异常: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
  }
}