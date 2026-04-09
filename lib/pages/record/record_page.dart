import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format_util.dart';
import '../../providers/recording_provider.dart';
import '../../services/recording_service.dart';
import '../../widgets/recording_controls/recording_controls.dart';
import '../../widgets/recording_controls/waveform_indicator.dart';
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  /// 开始新的录音会话
  Future<void> _startNewSession() async {
    if (_sessionInitialized) return;
    _sessionInitialized = true;
    await ref.read(recordingControlProvider.notifier).startSession();
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

    final totalMs = totalMsAsync.valueOrNull ?? 0;
    final audioMs = audioMsAsync.valueOrNull ?? 0;
    final isRecording = recordingState == RecordingState.recording;
    final isPaused = recordingState == RecordingState.paused;
    final isActive = isRecording || isPaused;

    // 监听控制状态错误
    ref.listen<AsyncValue<void>>(recordingControlProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: ${next.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

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
              isLoading: controlState.isLoading,
            ),

            // 分隔线
            const Divider(height: 1),

            // 中部：实时时间轴
            Expanded(
              child: RecordingTimeline(events: events),
            ),

            // 分隔线
            const Divider(height: 1),

            // 底部操作栏
            _buildBottomBar(
              context: context,
              recordingState: recordingState,
              isActive: isActive,
              isRecording: isRecording,
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
    required bool isLoading,
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
    required bool isLoading,
    required RecordingState recordingState,
  }) {
    Color dotColor;
    String statusText;

    if (isLoading) {
      dotColor = colorScheme.primary;
      statusText = '准备中...';
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
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 快捷操作按钮组
          _buildQuickActions(
            context: context,
            isActive: isActive,
            colorScheme: colorScheme,
            theme: theme,
          ),

          const SizedBox(height: 12),

          // 录音控制按钮组
          RecordingControls(
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
        ],
      ),
    );
  }

  /// 构建快捷操作按钮组
  Widget _buildQuickActions({
    required BuildContext context,
    required bool isActive,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _QuickActionButton(
          icon: Icons.camera_alt,
          label: '拍照',
          enabled: isActive,
          color: colorScheme.primary,
          onPressed: () => _handleTakePhoto(),
        ),
        _QuickActionButton(
          icon: Icons.videocam,
          label: '录视频',
          enabled: false, // 暂不支持
          color: colorScheme.tertiary,
          onPressed: () {
            // TODO(GDNDZZK): 实现录视频功能
          },
        ),
        _QuickActionButton(
          icon: Icons.edit_note,
          label: '笔记',
          enabled: isActive,
          color: colorScheme.secondary,
          onPressed: () => _showTextNoteBottomSheet(),
        ),
        _QuickActionButton(
          icon: Icons.bookmark,
          label: '书签',
          enabled: isActive,
          color: const Color(0xFFFF6B6B),
          onPressed: () => _showBookmarkBottomSheet(),
        ),
      ],
    );
  }

  // ==================== 事件处理 ====================

  /// 处理拍照
  Future<void> _handleTakePhoto() async {
    await ref.read(recordingControlProvider.notifier).takePhoto();
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
                      final content = contentController.text.trim();
                      if (content.isEmpty) return;
                      Navigator.pop(context);
                      ref
                          .read(recordingControlProvider.notifier)
                          .addTextNote(
                            content,
                            title: titleController.text.trim().isEmpty
                                ? null
                                : titleController.text.trim(),
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
    ).then((_) {
      contentController.dispose();
      titleController.dispose();
    });
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
                          Navigator.pop(context);
                          ref
                              .read(recordingControlProvider.notifier)
                              .addBookmark(
                                label: labelController.text.trim().isEmpty
                                    ? null
                                    : labelController.text.trim(),
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
    ).then((_) {
      labelController.dispose();
    });
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
            onPressed: () => Navigator.pop(context),
            child: const Text('继续录音'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(recordingControlProvider.notifier).stopSession();
              this.context.pop();
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
        content: const Text('确定结束本次录音？结束后将保存录音并跳转到回放页面。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(recordingControlProvider.notifier).stopSession();
              if (mounted) {
                final sessionId = ref.read(currentSessionIdProvider);
                if (sessionId != null) {
                  this.context.go('/playback/$sessionId');
                } else {
                  this.context.go('/');
                }
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 显示编辑标题对话框
  void _showEditTitleDialog() {
    final editController = TextEditingController(
      text: _titleController.text.isEmpty ? '新建录音' : _titleController.text,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑标题'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(
            labelText: '会话标题',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final title = editController.text.trim();
              if (title.isNotEmpty) {
                setState(() {
                  _titleController.text = title;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    ).then((_) {
      editController.dispose();
    });
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

/// 快捷操作按钮
///
/// 圆形图标按钮 + 文字标签。
/// Author: GDNDZZK
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
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
          child: IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 24),
            style: IconButton.styleFrom(
              foregroundColor: effectiveColor,
              backgroundColor: effectiveColor.withValues(alpha: 0.1),
              disabledForegroundColor: Colors.grey.withValues(alpha: 0.5),
              disabledBackgroundColor: Colors.grey.withValues(alpha: 0.05),
            ),
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
