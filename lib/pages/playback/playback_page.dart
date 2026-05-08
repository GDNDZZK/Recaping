import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bookmark.dart';
import '../../models/text_note.dart';
import '../../models/timeline_event.dart';
import '../../providers/external_session_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/audio_playback_service.dart';
import '../../widgets/timeline/event_detail_panel.dart';
import '../../widgets/timeline/recording_timeline.dart';

/// 回放页面
///
/// 提供音频回放、时间轴事件同步显示等功能。
/// 复用录音页面的布局风格：顶部状态区 + 中部时间轴 + 底部控制栏。
///
/// 当 [isExternal] 为 true 时，表示该会话是从外部 .recp 文件打开的临时会话，
/// 此时 AppBar 会显示保存按钮，退出时会弹出保存确认对话框。
class PlaybackPage extends ConsumerStatefulWidget {
  /// 要回放的会话 ID
  final String sessionId;

  /// 是否为外部打开的临时会话
  final bool isExternal;

  const PlaybackPage({
    super.key,
    required this.sessionId,
    this.isExternal = false,
  });

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  /// 是否已加载数据
  bool _isLoading = true;

  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时位置（毫秒）
  double _draggingValue = 0;

  /// 缓存的播放服务引用。
  /// 在 [build()] 中通过 [ref] 获取并缓存，避免 [dispose()] 时 [ref] 已失效
  /// （Riverpod 在 widget dispose 后不允许使用 ref）导致无法调用 [stop()]。
  AudioPlaybackService? _cachedService;

  @override
  void initState() {
    super.initState();
    debugPrint('[PlaybackPage] initState: sessionId=${widget.sessionId}, isExternal=${widget.isExternal}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[PlaybackPage] addPostFrameCallback: calling _loadSessionData');
      _loadSessionData();
    });
  }

  @override
  void dispose() {
    debugPrint('[PlaybackPage] dispose() called');
    // 使用缓存的服务引用调用 stop()，避免 dispose 时 ref 已失效。
    final service = _cachedService;
    if (service != null) {
      debugPrint('[PlaybackPage] calling service.stop(), current state=${service.state}');
      service.stop();
    } else {
      debugPrint('[PlaybackPage] no cached service available');
    }
    super.dispose();
  }

  /// 加载会话数据
  Future<void> _loadSessionData() async {
    debugPrint('[PlaybackPage] _loadSessionData: sessionId=${widget.sessionId}');
    setState(() => _isLoading = true);
    try {
      await ref
          .read(playbackControlProvider.notifier)
          .loadSession(widget.sessionId);
      debugPrint('[PlaybackPage] _loadSessionData: 加载成功');
    } catch (e, stackTrace) {
      debugPrint('[PlaybackPage] _loadSessionData 失败: $e');
      debugPrint('[PlaybackPage] 堆栈: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载会话失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 缓存服务引用：ref 在 build() 中始终有效，但在 dispose() 中已失效。
    _cachedService ??= ref.read(playbackServiceProvider);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accentColor = Color(0xFF6B6BFF);

    // 监听播放状态
    final playbackStateAsync = ref.watch(playbackControlProvider);

    // 监听播放位置
    final positionAsync = ref.watch(playbackPositionProvider);
    final position = positionAsync.valueOrNull ?? Duration.zero;

    // 监听播放状态（用于判断是否正在播放）
    final stateAsync = ref.watch(playbackStateProvider);
    final playbackState = stateAsync.valueOrNull;
    final isPlaying = playbackState == PlaybackState.playing;

    // 监听播放速度
    final speed = ref.watch(playbackSpeedProvider);

    // 监听录音段数据（从 AudioChunk 构建，包含暂停间隔）
    final segments = ref.watch(playbackSegmentsProvider);

    // 监听时间轴事件
    final eventsAsync = ref.watch(playbackEventsProvider);

    // 监听外部会话状态（仅外部模式）
    final externalState = widget.isExternal
        ? ref.watch(externalSessionProvider)
        : null;

    // 加载中状态
    if (_isLoading || playbackStateAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(),
          ),
          title: const Text('加载中...'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 加载错误状态
    if (playbackStateAsync.hasError) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(),
          ),
          title: const Text('回放'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${playbackStateAsync.error}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadSessionData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final events = eventsAsync.valueOrNull ?? [];

    // 获取会话信息以计算总时长
    final sessionList = ref.watch(sessionListProvider);
    final session = sessionList.valueOrNull
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;
    // 优先使用音频服务的实际时长，避免事件时间戳不完整导致高度不足
    final audioDuration = ref.read(playbackDurationProvider);
    final totalDurationMs = session?.duration ??
        (audioDuration.inMilliseconds > 0
            ? audioDuration.inMilliseconds
            : (events.isNotEmpty
                ? events.map((e) => e.timestamp).reduce((a, b) => a > b ? a : b)
                : 0));

    final scaffold = Scaffold(
      appBar: _buildAppBar(
        context,
        theme,
        colorScheme,
        accentColor,
        externalState?.isDirty ?? false,
      ),
      body: Column(
        children: [
          // 顶部播放状态区域
          _buildPlaybackStatusArea(
            context,
            playbackState,
            position,
            Duration(milliseconds: totalDurationMs),
          ),
          const Divider(height: 1),

          // 中部时间轴（复用 RecordingTimeline，传入从 AudioChunk 构建的 segments）
          Expanded(
            child: RecordingTimeline(
              events: events,
              segments: segments,
              totalElapsedMs: totalDurationMs,
              isPlaybackMode: true,
              currentPlaybackMs: position.inMilliseconds,
              isPlaying: isPlaying,
              onEventTap: (event) => _handleEventDetail(event),
              onSeek: (ms) {
                ref.read(playbackControlProvider.notifier).seekTo(ms);
              },
            ),
          ),
          const Divider(height: 1),

          // 底部播放控制栏
          _buildPlaybackBottomBar(context, isPlaying, speed),
        ],
      ),
    );

    // 外部会话模式：拦截返回操作，检查是否有未保存修改
    if (widget.isExternal) {
      return WillPopScope(
        onWillPop: () async {
          if (externalState?.isDirty ?? false) {
            _showSaveConfirmDialog();
            return false; // 不退出，等待用户选择
          } else {
            // 正常退出（无修改），清理外部会话
            await _cleanupExternalSession();
            return true;
          }
        },
        child: scaffold,
      );
    }

    return scaffold;
  }

  // ==================== 顶部播放状态区域 ====================

  /// 构建顶部播放状态区域
  Widget _buildPlaybackStatusArea(
    BuildContext context,
    PlaybackState? playbackState,
    Duration position,
    Duration duration,
  ) {
    final theme = Theme.of(context);
    final totalMs = duration.inMilliseconds.toDouble();
    final positionMs =
        position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 0.0);
    final isPlaying = playbackState == PlaybackState.playing;
    final isAtEnd = position.inMilliseconds >= duration.inMilliseconds && duration.inMilliseconds > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // 播放状态指示器
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPlaying ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                playbackState == PlaybackState.playing
                    ? '播放中'
                    : isAtEnd
                        ? '播放完成'
                        : '已暂停',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isPlaying
                      ? Colors.green
                      : isAtEnd
                          ? Colors.orange
                          : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 当前时间 / 总时长
          Text(
            '${_formatDuration(_isDragging ? Duration(milliseconds: _draggingValue.toInt()) : position)} / ${_formatDuration(duration)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 进度条
          if (totalMs > 0)
            SliderTheme(
              data: const SliderThemeData(
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                trackHeight: 3,
              ),
              child: Slider(
                value: _isDragging
                    ? _draggingValue.clamp(0.0, totalMs)
                    : positionMs,
                min: 0,
                max: totalMs,
                onChangeStart: (value) {
                  setState(() {
                    _isDragging = true;
                    _draggingValue = value;
                  });
                },
                onChanged: (value) {
                  setState(() {
                    _draggingValue = value;
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _isDragging = false;
                  });
                  ref.read(playbackControlProvider.notifier).seekTo(value.toInt());
                },
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 底部播放控制栏 ====================

  /// 构建底部播放控制栏
  Widget _buildPlaybackBottomBar(
    BuildContext context,
    bool isPlaying,
    double speed,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 快退15秒
          IconButton(
            onPressed: () => _skipBySeconds(-15),
            icon: const Icon(Icons.fast_rewind),
            tooltip: '快退15秒',
          ),
          // 上一事件
          IconButton(
            onPressed: _skipToPreviousEvent,
            icon: const Icon(Icons.skip_previous),
            tooltip: '上一事件',
          ),
          // 播放/暂停大按钮
          FloatingActionButton(
            onPressed: _togglePlayPause,
            backgroundColor: const Color(0xFF6B6BFF),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 32,
            ),
          ),
          const SizedBox(width: 8),
          // 下一事件
          IconButton(
            onPressed: _skipToNextEvent,
            icon: const Icon(Icons.skip_next),
            tooltip: '下一事件',
          ),
          // 快进15秒
          IconButton(
            onPressed: () => _skipBySeconds(15),
            icon: const Icon(Icons.fast_forward),
            tooltip: '快进15秒',
          ),
          // 速度按钮
          _buildSpeedButton(speed),
        ],
      ),
    );
  }

  // ==================== 辅助方法 ====================

  /// 格式化时长为字符串（M:SS 或 H:MM:SS）
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 切换播放/暂停
  void _togglePlayPause() {
    final stateAsync = ref.read(playbackStateProvider);
    final state = stateAsync.valueOrNull;
    if (state == PlaybackState.playing) {
      ref.read(playbackControlProvider.notifier).pause();
    } else {
      ref.read(playbackControlProvider.notifier).play();
    }
  }

  /// 快进/快退指定秒数
  void _skipBySeconds(int seconds) {
    final position =
        ref.read(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.read(playbackDurationProvider);
    final newPosition = position + Duration(seconds: seconds);
    ref.read(playbackControlProvider.notifier).seekTo(
          newPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
        );
  }

  /// 跳转到上一个事件
  void _skipToPreviousEvent() {
    final eventsState = ref.read(playbackEventsProvider);
    final events = eventsState.valueOrNull ?? [];
    final position =
        ref.read(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final positionMs = position.inMilliseconds;

    final previousEvents =
        events.where((e) => e.timestamp < positionMs - 1000).toList();
    if (previousEvents.isNotEmpty) {
      ref
          .read(playbackControlProvider.notifier)
          .seekTo(previousEvents.last.timestamp);
    }
  }

  /// 跳转到下一个事件
  void _skipToNextEvent() {
    final eventsState = ref.read(playbackEventsProvider);
    final events = eventsState.valueOrNull ?? [];
    final position =
        ref.read(playbackPositionProvider).valueOrNull ?? Duration.zero;
    final positionMs = position.inMilliseconds;

    final nextEvents =
        events.where((e) => e.timestamp > positionMs + 1000).toList();
    if (nextEvents.isNotEmpty) {
      ref
          .read(playbackControlProvider.notifier)
          .seekTo(nextEvents.first.timestamp);
    }
  }

  /// 构建速度切换按钮
  Widget _buildSpeedButton(double speed) {
    return TextButton(
      onPressed: () {
        const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        final currentIndex = speeds.indexOf(speed);
        final nextIndex = (currentIndex + 1) % speeds.length;
        ref.read(playbackSpeedProvider.notifier).setSpeed(speeds[nextIndex]);
      },
      child: Text('${speed}x'),
    );
  }

  // ==================== AppBar ====================

  /// 构建 AppBar
  ///
  /// [isDirty] 外部会话是否有未保存的修改（仅外部模式使用）
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Color accentColor,
    bool isDirty,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => _handleBack(),
      ),
      title: widget.isExternal
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('回放'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '外部文件',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            )
          : const Text('回放'),
      actions: [
        // 外部会话模式：保存为文件按钮
        if (widget.isExternal)
          IconButton(
            icon: Icon(
              Icons.save,
              color: isDirty ? accentColor : null,
            ),
            tooltip: '保存为文件',
            onPressed: _handleSaveBackToFile,
          ),
        // 外部会话模式：保存到会话列表按钮
        if (widget.isExternal)
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: '保存到会话列表',
            onPressed: _handleSaveExternalSession,
          ),
        // 更多操作菜单
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: '更多操作',
          onSelected: (value) => _handleMenuAction(value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('编辑标题'),
                ],
              ),
            ),
            // 外部会话不显示删除选项
            if (!widget.isExternal)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20),
                    SizedBox(width: 12),
                    Text('删除会话'),
                  ],
                ),
              ),
            // 外部会话不显示导出选项（已有保存为文件按钮）
            if (!widget.isExternal)
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, size: 20),
                    SizedBox(width: 12),
                    Text('导出'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text('分享'),
                ],
              ),
            ),
            // 外部会话不显示 AI 功能（需要永久会话）
            if (!widget.isExternal)
              const PopupMenuItem(
                value: 'ai',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 12),
                    Text('AI 功能'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ==================== 外部会话相关 ====================

  /// 处理返回操作
  void _handleBack() {
    if (widget.isExternal) {
      final externalState = ref.read(externalSessionProvider);
      if (externalState.isDirty) {
        _showSaveConfirmDialog();
      } else {
        _cleanupExternalSession();
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      }
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }
  }

  /// 清理外部会话
  Future<void> _cleanupExternalSession() async {
    if (!widget.isExternal) return;
    await ref.read(externalSessionProvider.notifier).cleanup();
  }

  /// 保存外部会话到永久列表
  Future<void> _handleSaveExternalSession() async {
    final success = await ref.read(externalSessionProvider.notifier).saveSession();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到会话列表')),
      );
      // 保存成功后，导航到普通回放页面
      if (context.canPop()) {
        context.pop();
      }
      context.push('/playback/${widget.sessionId}');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败')),
      );
    }
  }

  /// 保存外部会话为文件
  ///
  /// 直接弹出 FilePicker 另存为对话框，让用户选择保存位置。
  Future<void> _handleSaveBackToFile() async {
    await _handleSaveAsFile();
  }

  /// 显示文件名编辑对话框
  ///
  /// 让用户在保存前编辑文件名。
  /// [initialName] 初始文件名
  /// 返回用户编辑后的文件名，如果用户取消则返回 null
  Future<String?> _showFileNameDialog(String initialName) async {
    final controller = TextEditingController(text: initialName);
    final nameWithoutExt = initialName.replaceAll(RegExp(r'\.recp$'), '');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: nameWithoutExt.length);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('保存文件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件名',
            hintText: '输入文件名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 另存为文件（降级方案）
  ///
  /// 使用 FilePicker 让用户选择保存位置，并允许编辑文件名。
  Future<void> _handleSaveAsFile() async {
    // 1. 先获取默认文件名
    final sessionId = widget.sessionId;
    final externalState = ref.read(externalSessionProvider);
    String defaultFileName;

    // 优先使用原始文件名
    final sourcePath = externalState.sourceFilePath;
    if (sourcePath != null && sourcePath.endsWith('.recp')) {
      defaultFileName = sourcePath.split('/').last;
    } else {
      // 尝试使用会话标题
      final sessionList = ref.read(sessionListProvider);
      final session = sessionList.valueOrNull
          ?.where((s) => s.sessionId == sessionId)
          .firstOrNull;
      final title = session?.title;
      if (title != null && title.isNotEmpty) {
        final sanitized =
            title.replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff-]'), '_').trim();
        defaultFileName = '$sanitized.recp';
      } else {
        // 回退到 session ID
        defaultFileName = '$sessionId.recp';
      }
    }

    // 2. 让用户选择保存目录
    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: '选择保存目录',
    );

    if (selectedDirectory == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消保存')),
        );
      }
      return;
    }

    // 3. 弹出文件名编辑对话框
    final editedFileName = await _showFileNameDialog(defaultFileName);
    if (editedFileName == null || editedFileName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消保存')),
        );
      }
      return;
    }

    // 4. 确保文件名以 .recp 结尾
    String finalFileName = editedFileName;
    if (!finalFileName.endsWith('.recp')) {
      finalFileName = '$finalFileName.recp';
    }

    // 5. 调用 saveAsFileToDirectory 保存文件
    final savePath = await ref
        .read(externalSessionProvider.notifier)
        .saveAsFileToDirectory(selectedDirectory, finalFileName);

    if (savePath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到: $savePath')),
      );
      // 清理外部会话缓存并导航到首页
      await _cleanupExternalSession();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败')),
      );
    }
  }

  /// 显示保存确认对话框
  ///
  /// 提供三个选项：保存为文件、保存到会话列表、放弃修改。
  void _showSaveConfirmDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('未保存的修改'),
        content: const Text('您有未保存的修改，请选择保存方式：'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // 放弃修改，清理并退出
              _cleanupExternalSession();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            child: const Text('放弃修改'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleSaveExternalSession();
            },
            child: const Text('保存到会话列表'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _handleSaveBackToFile();
            },
            child: const Text('保存为文件'),
          ),
        ],
      ),
    );
  }

  // ==================== 事件详情处理 ====================

  /// 统一处理事件详情展示
  ///
  /// 使用 [EventDetailPanel] 显示事件详情，支持编辑和删除操作。
  /// 录音事件仅跳转播放位置，不显示详情面板。
  /// 外部会话模式下，编辑和删除操作会标记脏状态。
  void _handleEventDetail(TimelineEvent event) {
    // 录音事件仅跳转播放位置
    if (event.type == TimelineEventType.audio) {
      ref.read(playbackControlProvider.notifier).seekTo(event.timestamp);
      return;
    }

    EventDetailPanel.show(
      context: context,
      event: event,
      onEdit: (updatedEvent) async {
        final eventsNotifier = ref.read(playbackEventsProvider.notifier);
        if (event.type == TimelineEventType.photo) {
          final photo = await eventsNotifier.getPhotoById(event.id);
          if (photo != null) {
            final updatedPhoto = photo.copyWith(title: updatedEvent.label);
            await eventsNotifier.updatePhoto(updatedPhoto);
          }
        } else if (event.type == TimelineEventType.video) {
          final chunk = await eventsNotifier.getVideoChunkById(event.id);
          if (chunk != null) {
            final updatedChunk = chunk.copyWith(title: updatedEvent.label);
            await eventsNotifier.updateVideoChunk(updatedChunk);
          }
        } else if (event.type == TimelineEventType.textNote) {
          final note = TextNote(
            id: event.id,
            timestamp: event.timestamp,
            title: updatedEvent.label,
            content: updatedEvent.textContent ?? '',
            createdAt: DateTime.now(),
          );
          await eventsNotifier.updateTextNote(note);
        } else if (event.type == TimelineEventType.bookmark) {
          final bookmark = Bookmark(
            id: event.id,
            timestamp: event.timestamp,
            label: updatedEvent.label,
            color: updatedEvent.color ?? '#FF6B6B',
            createdAt: DateTime.now(),
          );
          await eventsNotifier.updateBookmark(bookmark);
        }
        // 外部会话模式：标记脏状态
        if (widget.isExternal) {
          await ref.read(externalSessionProvider.notifier).markDirty();
        }
      },
      onDelete: () async {
        final eventsNotifier = ref.read(playbackEventsProvider.notifier);
        await eventsNotifier.removeEvent(event.id, event.type);
        // 外部会话模式：标记脏状态
        if (widget.isExternal) {
          await ref.read(externalSessionProvider.notifier).markDirty();
        }
      },
    );
  }

  // ==================== 菜单操作 ====================

  /// 处理菜单操作
  void _handleMenuAction(String action) {
    switch (action) {
      case 'edit':
        _showEditTitleDialog();
        break;
      case 'delete':
        _showDeleteConfirmDialog();
        break;
      case 'export':
        _handleExport();
        break;
      case 'share':
        _handleShare();
        break;
      case 'ai':
        context.push('/ai/${widget.sessionId}');
        break;
    }
  }

  /// 处理导出会话
  Future<void> _handleExport() async {
    try {
      final exportService = await ref.read(exportServiceProvider.future);
      final exportPath = await exportService.exportSession(widget.sessionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出到: $exportPath'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 处理分享会话
  Future<void> _handleShare() async {
    try {
      final exportService = await ref.read(exportServiceProvider.future);
      // 获取会话标题
      final sessionList = ref.read(sessionListProvider);
      final session = sessionList.valueOrNull
          ?.where((s) => s.sessionId == widget.sessionId)
          .firstOrNull;
      await exportService.shareSession(
        widget.sessionId,
        title: session?.title,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  /// 显示编辑标题对话框
  void _showEditTitleDialog() {
    final sessionList = ref.read(sessionListProvider);
    final session = sessionList.valueOrNull
        ?.where((s) => s.sessionId == widget.sessionId)
        .firstOrNull;

    final titleController = TextEditingController(
      text: session?.title ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑标题'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty && session != null) {
                await ref
                    .read(sessionListProvider.notifier)
                    .updateSession(session.copyWith(title: newTitle));
                // 外部会话模式：标记脏状态
                if (widget.isExternal) {
                  await ref.read(externalSessionProvider.notifier).markDirty();
                }
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确定要删除此会话吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref
                  .read(sessionListProvider.notifier)
                  .deleteSession(widget.sessionId);
              if (mounted) {
                context.pop();
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}