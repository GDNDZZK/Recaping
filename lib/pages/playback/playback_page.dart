import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bookmark.dart';
import '../../models/text_note.dart';
import '../../models/timeline_event.dart';
import '../../providers/playback_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/audio_playback_service.dart';
import '../../widgets/timeline/event_detail_panel.dart';
import '../../widgets/timeline/recording_timeline.dart';

/// 回放页面
///
/// 提供音频回放、时间轴事件同步显示等功能。
/// 复用录音页面的布局风格：顶部状态区 + 中部时间轴 + 底部控制栏。
/// Author: GDNDZZK
class PlaybackPage extends ConsumerStatefulWidget {
  /// 要回放的会话 ID
  final String sessionId;

  const PlaybackPage({super.key, required this.sessionId});

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  /// 是否已加载数据
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessionData();
    });
  }

  @override
  void dispose() {
    // 释放播放资源
    ref.read(playbackServiceProvider).dispose();
    super.dispose();
  }

  /// 加载会话数据
  Future<void> _loadSessionData() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(playbackControlProvider.notifier)
          .loadSession(widget.sessionId);
    } catch (e) {
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

    // 监听总时长
    final duration = ref.watch(playbackDurationProvider);

    // 监听时间轴事件
    final eventsAsync = ref.watch(playbackEventsProvider);

    // 加载中状态
    if (_isLoading || playbackStateAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
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
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
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
    final totalDurationMs = session?.duration ??
        (events.isNotEmpty
            ? events.map((e) => e.timestamp).reduce((a, b) => a > b ? a : b)
            : 0);

    return Scaffold(
      appBar: _buildAppBar(context, theme, colorScheme, accentColor),
      body: Column(
        children: [
          // 顶部播放状态区域
          _buildPlaybackStatusArea(
            context,
            isPlaying,
            position,
            duration,
          ),
          const Divider(height: 1),

          // 中部时间轴（复用 RecordingTimeline）
          Expanded(
            child: RecordingTimeline(
              events: events,
              totalElapsedMs: totalDurationMs,
              isPlaybackMode: true,
              currentPlaybackMs: position.inMilliseconds,
              isPlaying: isPlaying,
              onEventTap: (event) => _handleEventDetail(event),
            ),
          ),
          const Divider(height: 1),

          // 底部播放控制栏
          _buildPlaybackBottomBar(context, isPlaying, speed),
        ],
      ),
    );
  }

  // ==================== 顶部播放状态区域 ====================

  /// 构建顶部播放状态区域
  ///
  /// 参考录音页面的状态区域样式，显示播放状态、时间和进度条。
  Widget _buildPlaybackStatusArea(
    BuildContext context,
    bool isPlaying,
    Duration position,
    Duration duration,
  ) {
    final theme = Theme.of(context);
    final totalMs = duration.inMilliseconds.toDouble();
    final positionMs =
        position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 0.0);

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
                isPlaying ? '播放中' : '已暂停',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isPlaying ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 当前时间 / 总时长
          Text(
            '${_formatDuration(position)} / ${_formatDuration(duration)}',
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
                value: positionMs,
                min: 0,
                max: totalMs,
                onChanged: (value) {
                  // 拖动时不立即跳转
                },
                onChangeEnd: (value) {
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
  ///
  /// 替代原来的 AudioPlayerControls，简化控制栏布局。
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
        // 切换速度：0.5x -> 0.75x -> 1.0x -> 1.25x -> 1.5x -> 2.0x -> 0.5x
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
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    Color accentColor,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
      ),
      title: const Text('回放'),
      actions: [
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

  // ==================== 事件详情处理 ====================

  /// 统一处理事件详情展示
  ///
  /// 使用 [EventDetailPanel] 显示事件详情，支持编辑和删除操作。
  /// 录音事件仅跳转播放位置，不显示详情面板。
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
      },
      onDelete: () async {
        final eventsNotifier = ref.read(playbackEventsProvider.notifier);
        await eventsNotifier.removeEvent(event.id, event.type);
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
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty && session != null) {
                await ref
                    .read(sessionListProvider.notifier)
                    .updateSession(session.copyWith(title: newTitle));
              }
              if (context.mounted) {
                Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确定要删除此会话吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(sessionListProvider.notifier)
                  .deleteSession(widget.sessionId);
              if (mounted) {
                this.context.pop();
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
