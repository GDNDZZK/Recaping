import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format_util.dart';
import '../../models/bookmark.dart';
import '../../models/recording_segment.dart';
import '../../models/text_note.dart';
import '../../models/timeline_event.dart';
import '../../providers/recording_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/recording_service.dart';
import '../../widgets/recording_controls/recording_controls.dart';
import '../../widgets/recording_controls/waveform_indicator.dart';
import '../../widgets/timeline/event_detail_panel.dart';
import '../../widgets/timeline/recording_timeline.dart';

/// 录音页面
///
/// 提供完整的录音交互界面，包括：
/// - 顶部状态区域（录音状态、时间显示、波形指示器）
/// - 中部实时时间轴
/// - 底部操作栏（快捷操作 + 录音控制）
///
/// 使用双时间轴模型（总时间轴 + 录音时间轴）。
/// Author: GDNDZZK
class RecordPage extends ConsumerStatefulWidget {
  /// 关联的会话 ID（可选，为 null 时表示新建录音）
  final String? sessionId;

  const RecordPage({super.key, this.sessionId});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage>
    with SingleTickerProviderStateMixin {
  /// 脉冲动画控制器
  late AnimationController _pulseController;

  /// 脉冲缩放动画
  late Animation<double> _pulseAnimation;

  /// 会话标题控制器
  final _titleController = TextEditingController();

  /// 是否已初始化会话
  bool _sessionInitialized = false;

  /// ref.listenManual 返回的监听器订阅（用于 dispose 时关闭）
  ProviderSubscription<AsyncValue<void>>? _controlStateSubscription;

  @override
  void initState() {
    super.initState();

    // 初始化脉冲动画
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 新建录音时自动开始会话
    if (widget.sessionId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startNewSession();
      });
    }

    // 监听控制状态错误（使用 listenManual 在 initState 中注册，避免 build 中高频重建导致依赖追踪异常）
    _controlStateSubscription = ref.listenManual<AsyncValue<void>>(
      recordingControlProvider,
      (previous, next) {
        if (next.hasError && !next.isLoading) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('操作失败: ${next.error}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    _controlStateSubscription?.close();
    _pulseController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// 开始新的录音会话
  Future<void> _startNewSession() async {
    if (_sessionInitialized) return;
    _sessionInitialized = true;
    final title = await ref.read(recordingControlProvider.notifier).startSession();
    if (title != null && mounted) {
      setState(() {
        _titleController.text = title;
      });
    }
  }

  /// 获取当前录音状态
  RecordingState _currentRecordingState(WidgetRef ref) {
    final stateAsync = ref.watch(recordingStateProvider);
    return stateAsync.valueOrNull ?? RecordingState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = _currentRecordingState(ref);
    final totalMsAsync = ref.watch(totalElapsedMsProvider);
    final audioMsAsync = ref.watch(audioElapsedMsProvider);
    final events = ref.watch(timelineEventsProvider);
    final controlState = ref.watch(recordingControlProvider);
    final amplitudeAsync = ref.watch(amplitudeProvider);

    final totalMs = totalMsAsync.valueOrNull ?? 0;
    final audioMs = audioMsAsync.valueOrNull ?? 0;
    final isRecording = recordingState == RecordingState.recording;
    final isPaused = recordingState == RecordingState.paused;
    final isTotalPaused = recordingState == RecordingState.totalPaused;
    final isActive = isRecording || isPaused || isTotalPaused;

    // 获取录音段，并实时更新最后一个段的 endMs 用于显示
    final rawSegments = ref.watch(recordingSegmentsProvider);
    List<RecordingSegment> displaySegments = rawSegments;
    if (rawSegments.isNotEmpty && totalMs > 0) {
      // 本地计算显示用的段列表，将最后一个活跃段延伸到当前时间
      displaySegments = List<RecordingSegment>.from(rawSegments);
      final lastSegment = displaySegments.last;
      displaySegments[displaySegments.length - 1] = lastSegment.copyWith(
        endMs: totalMs,
      );
    }

    // 获取振幅高度（0.0 ~ 1.0）
    final amplitude = amplitudeAsync.valueOrNull?.toNormalizedHeight() ?? 0.0;

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isActive) {
          _showDiscardDialog();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context, isActive),
        body: Column(
          children: [
            // 顶部状态区域
            _buildStatusArea(
              context: context,
              recordingState: recordingState,
              totalMs: totalMs,
              audioMs: audioMs,
              isRecording: isRecording,
              isPaused: isPaused,
              isTotalPaused: isTotalPaused,
              isLoading: controlState.isLoading,
              amplitude: amplitude,
            ),

            // 分隔线
            const Divider(height: 1),

            // 中部：实时时间轴
            Expanded(
              child: RecordingTimeline(
                events: events,
                segments: displaySegments,
                totalElapsedMs: totalMs,
                onEventTap: (event) => _handleEventTap(event),
              ),
            ),

            // 分隔线
            const Divider(height: 1),

            // 底部操作栏
            _buildBottomBar(
              context: context,
              recordingState: recordingState,
              isActive: isActive,
              isRecording: isRecording,
              isTotalPaused: isTotalPaused,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar(BuildContext context, bool isActive) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (isActive) {
            _showDiscardDialog();
          } else {
            context.pop();
          }
        },
      ),
      title: GestureDetector(
        onTap: isActive ? () => _showEditTitleDialog() : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _titleController.text.isEmpty ? '新建录音' : _titleController.text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.edit,
                size: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (isActive)
          TextButton(
            onPressed: () => _showStopConfirmDialog(),
            child: const Text('完成'),
          ),
      ],
    );
  }

  /// 构建顶部状态区域
  Widget _buildStatusArea({
    required BuildContext context,
    required RecordingState recordingState,
    required int totalMs,
    required int audioMs,
    required bool isRecording,
    required bool isPaused,
    required bool isTotalPaused,
    required bool isLoading,
    required double amplitude,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // 录音状态指示器
          _buildStatusIndicator(
            theme: theme,
            colorScheme: colorScheme,
            isRecording: isRecording,
            isPaused: isPaused,
            isTotalPaused: isTotalPaused,
            isLoading: isLoading,
            recordingState: recordingState,
          ),

          const SizedBox(height: 12),

          // 总时间轴时间显示（大字体）
          Text(
            _formatTimeWithMs(totalMs),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 4),

          // 录音时间显示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic,
                size: 14,
                color: isRecording
                    ? const Color(0xFFFF4444)
                    : isPaused
                        ? Colors.grey
                        : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 4),
              Text(
                '录音时长: ${DateFormatUtil.formatDuration(audioMs)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: isRecording
                      ? const Color(0xFFFF4444)
                      : isPaused
                          ? Colors.grey
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 波形指示器
          WaveformIndicator(
            isActive: isRecording,
            color: isRecording
                ? const Color(0xFFFF4444)
                : colorScheme.primary.withValues(alpha: 0.3),
            amplitude: amplitude,
          ),
        ],
      ),
    );
  }

  /// 构建录音状态指示器
  Widget _buildStatusIndicator({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required bool isRecording,
    required bool isPaused,
    required bool isTotalPaused,
    required bool isLoading,
    required RecordingState recordingState,
  }) {
    Color dotColor;
    String statusText;

    if (isLoading) {
      dotColor = colorScheme.primary;
      statusText = '准备中...';
    } else if (isTotalPaused) {
      dotColor = Colors.orange;
      statusText = '时间轴已暂停';
    } else if (isRecording) {
      dotColor = const Color(0xFFFF4444);
      statusText = '录音中';
    } else if (isPaused) {
      dotColor = Colors.amber;
      statusText = '已暂停';
    } else {
      dotColor = Colors.grey;
      statusText = '准备录音';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 脉冲圆点（录音中时显示脉冲效果）
        if (isRecording)
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),

        const SizedBox(width: 8),

        Text(
          statusText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: dotColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 构建底部操作栏
  Widget _buildBottomBar({
    required BuildContext context,
    required RecordingState recordingState,
    required bool isActive,
    required bool isRecording,
    required bool isTotalPaused,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: isTotalPaused
                ? Colors.orange.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 总时间轴暂停提示
          if (isTotalPaused)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '时间轴已暂停，无法添加事件',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 快捷操作按钮组
          _buildQuickActions(
            context: context,
            isActive: isActive,
            isTotalPaused: isTotalPaused,
            colorScheme: colorScheme,
            theme: theme,
          ),

          const SizedBox(height: 12),

          // 录音控制按钮组（含总时间轴暂停按钮）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 总时间轴暂停/继续按钮
              if (isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: IconButton.filled(
                    onPressed: () {
                      if (isTotalPaused) {
                        ref.read(recordingControlProvider.notifier).resumeTotalTimeline();
                      } else {
                        ref.read(recordingControlProvider.notifier).pauseTotalTimeline();
                      }
                    },
                    icon: Icon(
                      isTotalPaused ? Icons.play_arrow : Icons.pause_circle_filled,
                      size: 28,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: isTotalPaused
                          ? Colors.green
                          : Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    tooltip: isTotalPaused ? '继续时间轴' : '暂停时间轴',
                  ),
                ),

              // 录音控制按钮组
              Expanded(
                child: RecordingControls(
                  state: recordingState,
                  onStart: () => _startNewSession(),
                  onPause: () {
                    ref.read(recordingControlProvider.notifier).pauseRecording();
                  },
                  onResume: () {
                    ref.read(recordingControlProvider.notifier).resumeRecording();
                  },
                  onStop: () => _showStopConfirmDialog(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建快捷操作按钮组
  Widget _buildQuickActions({
    required BuildContext context,
    required bool isActive,
    required bool isTotalPaused,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    // 总时间轴暂停时禁用快捷操作
    final quickActionsEnabled = isActive && !isTotalPaused;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _QuickActionButton(
          icon: Icons.camera_alt,
          label: '拍照',
          enabled: quickActionsEnabled,
          color: colorScheme.primary,
          onPressed: () => _handleTakePhoto(),
          isLocked: isTotalPaused,
        ),
        _QuickActionButton(
          icon: Icons.videocam,
          label: '录视频',
          enabled: quickActionsEnabled,
          color: colorScheme.tertiary,
          onPressed: () => _handleRecordVideo(),
          isLocked: isTotalPaused,
        ),
        _QuickActionButton(
          icon: Icons.edit_note,
          label: '笔记',
          enabled: quickActionsEnabled,
          color: colorScheme.secondary,
          onPressed: () => _showTextNoteBottomSheet(),
          isLocked: isTotalPaused,
        ),
        _QuickActionButton(
          icon: Icons.bookmark,
          label: '书签',
          enabled: quickActionsEnabled,
          color: const Color(0xFFFF6B6B),
          onPressed: () => _showBookmarkBottomSheet(),
          isLocked: isTotalPaused,
        ),
      ],
    );
  }

  // ==================== 事件处理 ====================

  /// 处理时间轴事件点击
  ///
  /// 显示事件详情面板，支持编辑和删除操作。
  void _handleEventTap(TimelineEvent event) {
    EventDetailPanel.show(
      context: context,
      event: event,
      onEdit: (updatedEvent) async {
        final eventsNotifier = ref.read(timelineEventsProvider.notifier);
        if (event.type == TimelineEventType.textNote) {
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
        final eventsNotifier = ref.read(timelineEventsProvider.notifier);
        await eventsNotifier.removeEvent(event.id, event.type);
      },
    );
  }

  /// 处理拍照
  Future<void> _handleTakePhoto() async {
    await ref.read(recordingControlProvider.notifier).takePhoto();
  }

  /// 处理录制短视频
  Future<void> _handleRecordVideo() async {
    await ref.read(recordingControlProvider.notifier).recordVideo();
  }

  /// 显示文字笔记底部 Sheet
  void _showTextNoteBottomSheet() {
    final contentController = TextEditingController();
    final titleController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '添加文字笔记',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 标题输入框（可选）
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLength: 50,
              ),

              const SizedBox(height: 8),

              // 内容输入框
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: '笔记内容',
                  border: OutlineInputBorder(),
                  isDense: true,
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                minLines: 3,
                maxLength: 500,
                autofocus: true,
              ),

              const SizedBox(height: 12),

              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      // 先获取所有需要的值
                      final content = contentController.text.trim();
                      final title = titleController.text.trim().isEmpty
                          ? null
                          : titleController.text.trim();

                      if (content.isEmpty) return;

                      // 再关闭 Sheet
                      Navigator.pop(context);

                      // 使用已获取的值
                      ref
                          .read(recordingControlProvider.notifier)
                          .addTextNote(content, title: title);
                    },
                    child: const Text('确认'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示书签添加底部 Sheet
  void _showBookmarkBottomSheet() {
    final labelController = TextEditingController();
    String selectedColor = '#FF6B6B';

    // 预设颜色列表
    const presetColors = [
      '#FF6B6B', // 红色
      '#FFB347', // 橙色
      '#FFEB3B', // 黄色
      '#66BB6A', // 绿色
      '#42A5F5', // 蓝色
      '#AB47BC', // 紫色
      '#FF7043', // 深橙
      '#26C6DA', // 青色
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '添加书签',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 标签输入框
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: '标签（可选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLength: 30,
                    autofocus: true,
                  ),

                  const SizedBox(height: 12),

                  // 颜色选择
                  Text(
                    '选择颜色',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presetColors.map((colorStr) {
                      final color = _parseColor(colorStr);
                      final isSelected = colorStr == selectedColor;
                      return GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            selectedColor = colorStr;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: Theme.of(context).colorScheme.onSurface,
                                    width: 3,
                                  )
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 操作按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          // 先获取所有需要的值
                          final label = labelController.text.trim().isEmpty
                              ? null
                              : labelController.text.trim();

                          // 再关闭 Sheet
                          Navigator.pop(context);

                          // 使用已获取的值
                          ref
                              .read(recordingControlProvider.notifier)
                              .addBookmark(
                                label: label,
                                color: selectedColor,
                              );
                        },
                        child: const Text('确认'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 显示放弃录音确认对话框
  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃录音？'),
        content: const Text('当前录音内容将不会被保存，确定要放弃吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('继续录音'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // 先等待录音状态完全重置，再返回主页
              await ref.read(recordingControlProvider.notifier).stopSession();
              if (mounted) {
                this.context.pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
  }

  /// 显示停止录音确认对话框
  void _showStopConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次录音？'),
        content: const Text('确定结束本次录音？结束后将保存录音并返回首页。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // 停止会话并保存录音
              await ref.read(recordingControlProvider.notifier).stopSession();
              if (mounted) {
                // 保存后返回首页
                this.context.go('/');
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 显示编辑标题对话框
  ///
  /// 使用 [Overlay] 替代 [showDialog]，避免 push 新路由导致 InheritedWidget
  /// 依赖追踪异常（_dependents.isEmpty 断言错误）。
  void _showEditTitleDialog() {
    if (!mounted) return;

    final currentName =
        _titleController.text.isEmpty ? '新建录音' : _titleController.text;

    _EditTitleOverlay.show(
      context: context,
      currentTitle: currentName,
      onConfirmed: (newName) async {
        if (!mounted) return;
        
        // 先更新本地 UI
        setState(() {
          _titleController.text = newName;
        });
        
        // 保存到数据库
        try {
          final recordingService = ref.read(recordingServiceProvider);
          final sessionId = recordingService.currentSessionId;
          
          if (sessionId != null) {
            final storageService = await ref.read(storageServiceProvider.future);
            final session = await storageService.getSession(sessionId);
            
            if (session != null && mounted) {
              await storageService.updateSession(
                session.copyWith(
                  title: newName,
                  updatedAt: DateTime.now(),
                ),
              );
            }
          }
        } catch (e) {
          // 保存失败时不影响本地 UI 更新
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('保存标题失败：$e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      onDismissed: () {
        // Overlay 已关闭，无需额外操作
      },
    );
  }

  // ==================== 工具方法 ====================

  /// 格式化时间（带毫秒）HH:MM:SS.mm
  String _formatTimeWithMs(int ms) {
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final millis = ((ms % 1000) ~/ 100).toString();
    return '$hours:$minutes:$seconds.$millis';
  }

  /// 解析十六进制颜色字符串
  Color _parseColor(String colorStr) {
    try {
      final hex = colorStr.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFFF6B6B);
    }
  }
}

/// 编辑录音名称 Overlay
///
/// 使用 [Overlay.insert] 在当前路由上叠加对话框，避免 push 新路由
/// 导致的 InheritedWidget 依赖追踪异常（_dependents.isEmpty 断言错误）。
///
/// Author: GDNDZZK
class _EditTitleOverlay extends StatefulWidget {
  final String currentTitle;
  final ValueChanged<String> onConfirmed;
  final VoidCallback onDismissed;

  const _EditTitleOverlay({
    required this.currentTitle,
    required this.onConfirmed,
    required this.onDismissed,
  });

  @override
  State<_EditTitleOverlay> createState() => _EditTitleOverlayState();

  /// 显示编辑标题 Overlay
  static void show({
    required BuildContext context,
    required String currentTitle,
    required ValueChanged<String> onConfirmed,
    required VoidCallback onDismissed,
  }) {
    final overlay = Overlay.of(context);
    OverlayEntry? entryRef;
    
    final entry = OverlayEntry(
      builder: (context) => _EditTitleOverlay(
        currentTitle: currentTitle,
        onConfirmed: (newTitle) {
          entryRef?.remove();
          onConfirmed(newTitle);
        },
        onDismissed: () {
          entryRef?.remove();
          onDismissed();
        },
      ),
    );
    
    entryRef = entry;
    overlay.insert(entry);
  }
}

class _EditTitleOverlayState extends State<_EditTitleOverlay> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.onDismissed(),
      child: Stack(
        children: [
          // 半透明遮罩
          Container(color: Colors.black54),
          // Dialog 内容
          Center(
            child: GestureDetector(
              onTap: () {}, // 阻止点击事件冒泡到遮罩
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints:
                      const BoxConstraints(maxWidth: 400, maxHeight: 500),
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '编辑录音名称',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: '输入新名称',
                              border: OutlineInputBorder(),
                            ),
                            autofocus: true,
                            maxLength: 50,
                            onSubmitted: (_) => _confirm(),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => widget.onDismissed(),
                                child: const Text('取消'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _confirm,
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty) {
      widget.onConfirmed(newName);
    }
  }
}

/// 快捷操作按钮
///
/// 圆形图标按钮 + 文字标签。
/// [isLocked] 为 true 时显示锁定图标覆盖。
/// Author: GDNDZZK
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;
  final bool isLocked;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = enabled ? color : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                onPressed: enabled ? onPressed : null,
                icon: Icon(icon, size: 24),
                style: IconButton.styleFrom(
                  foregroundColor: effectiveColor,
                  backgroundColor: effectiveColor.withValues(alpha: 0.1),
                  disabledForegroundColor: Colors.grey.withValues(alpha: 0.5),
                  disabledBackgroundColor: Colors.grey.withValues(alpha: 0.05),
                ),
              ),
              if (isLocked)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: enabled
                ? effectiveColor
                : Colors.grey.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
