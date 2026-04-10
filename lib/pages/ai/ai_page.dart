import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/session_database.dart';
import '../../core/utils/date_format_util.dart';
import '../../models/ai_result.dart';
import '../../providers/ai_provider.dart';
import '../../providers/settings_provider.dart';

/// AI 功能页面
///
/// 提供语音转文字、智能摘要、会议记录等 AI 功能的入口和结果展示。
/// Author: GDNDZZK
class AiPage extends ConsumerStatefulWidget {
  /// 关联的会话 ID
  final String sessionId;

  const AiPage({super.key, required this.sessionId});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  /// 主色调
  static const Color _primaryColor = Color(0xFF6B6BFF);

  /// 展开状态的管理（AiResult.id -> 是否展开）
  final Map<String, bool> _expandedState = {};

  @override
  void initState() {
    super.initState();
    // 初始化时加载 AI 结果
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshResults();
    });
  }

  /// 刷新 AI 结果列表
  void _refreshResults() {
    ref.invalidate(aiResultsRefreshableProvider(widget.sessionId));
  }

  /// 执行语音转文字
  Future<void> _startTranscription() async {
    final aiServiceAsync = ref.read(aiServiceProvider);

    await aiServiceAsync.when(
      data: (aiService) async {
        if (aiService == null) {
          _showSnackBar('AI 服务未配置');
          return;
        }

        // 检查是否有音频数据
        final hasAudio = await _checkAudioData();
        if (!hasAudio) {
          if (mounted) {
            _showSnackBar('没有可用的音频数据');
          }
          return;
        }

        // 获取音频数据
        final audioData = await _getAudioData();
        if (audioData == null || audioData.isEmpty) {
          if (mounted) {
            _showSnackBar('音频数据读取失败');
          }
          return;
        }

        ref.read(aiTaskStateProvider.notifier).setLoading();
        ref.read(aiLoadingMessageProvider.notifier).state = '正在转录音频...';

        try {
          final resultText = await aiService.transcribe(audioData);
          await _saveAiResult('transcription', resultText, aiService.model);
          ref.read(aiTaskStateProvider.notifier).setSuccess();

          if (mounted) {
            _showSnackBar('语音转文字完成');
            _refreshResults();
          }
        } catch (e) {
          ref.read(aiTaskStateProvider.notifier).setError();
          if (mounted) {
            _showSnackBar('转录失败：$e');
          }
        }
      },
      loading: () {
        _showSnackBar('AI 服务加载中...');
      },
      error: (error, _) {
        _showSnackBar('AI 服务错误：$error');
      },
    );
  }

  /// 生成摘要
  Future<void> _generateSummary() async {
    final transcriptionText = await _getLatestTranscription();
    if (transcriptionText == null || transcriptionText.isEmpty) {
      _showSnackBar('请先进行语音转文字');
      return;
    }

    final aiServiceAsync = ref.read(aiServiceProvider);
    await aiServiceAsync.when(
      data: (aiService) async {
        if (aiService == null) {
          _showSnackBar('AI 服务未配置');
          return;
        }

        ref.read(aiTaskStateProvider.notifier).setLoading();
        ref.read(aiLoadingMessageProvider.notifier).state = '正在生成摘要...';

        try {
          final resultText = await aiService.generateSummary(transcriptionText);
          await _saveAiResult('summary', resultText, aiService.model);
          ref.read(aiTaskStateProvider.notifier).setSuccess();

          if (mounted) {
            _showSnackBar('摘要生成完成');
            _refreshResults();
          }
        } catch (e) {
          ref.read(aiTaskStateProvider.notifier).setError();
          if (mounted) {
            _showSnackBar('摘要生成失败：$e');
          }
        }
      },
      loading: () {
        _showSnackBar('AI 服务加载中...');
      },
      error: (error, _) {
        _showSnackBar('AI 服务错误：$error');
      },
    );
  }

  /// 生成会议记录
  Future<void> _generateMeetingMinutes() async {
    final transcriptionText = await _getLatestTranscription();
    if (transcriptionText == null || transcriptionText.isEmpty) {
      _showSnackBar('请先进行语音转文字');
      return;
    }

    final aiServiceAsync = ref.read(aiServiceProvider);
    await aiServiceAsync.when(
      data: (aiService) async {
        if (aiService == null) {
          _showSnackBar('AI 服务未配置');
          return;
        }

        ref.read(aiTaskStateProvider.notifier).setLoading();
        ref.read(aiLoadingMessageProvider.notifier).state = '正在生成会议记录...';

        try {
          final resultText =
              await aiService.generateMeetingMinutes(transcriptionText);
          await _saveAiResult('meeting_minutes', resultText, aiService.model);
          ref.read(aiTaskStateProvider.notifier).setSuccess();

          if (mounted) {
            _showSnackBar('会议记录生成完成');
            _refreshResults();
          }
        } catch (e) {
          ref.read(aiTaskStateProvider.notifier).setError();
          if (mounted) {
            _showSnackBar('会议记录生成失败：$e');
          }
        }
      },
      loading: () {
        _showSnackBar('AI 服务加载中...');
      },
      error: (error, _) {
        _showSnackBar('AI 服务错误：$error');
      },
    );
  }

  /// 检查是否有音频数据
  Future<bool> _checkAudioData() async {
    try {
      final sessionDb = await SessionDatabase.create(widget.sessionId);
      final chunks = await sessionDb.getAudioChunks();
      return chunks.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 获取合并的音频数据
  Future<Uint8List?> _getAudioData() async {
    try {
      final sessionDb = await SessionDatabase.create(widget.sessionId);
      final chunks = await sessionDb.getAudioChunks();
      if (chunks.isEmpty) return null;

      final allBytes = <int>[];
      for (final chunk in chunks) {
        final absPath = await sessionDb.resolvePath(chunk.filePath);
        final file = File(absPath);
        if (await file.exists()) {
          allBytes.addAll(await file.readAsBytes());
        }
      }
      return allBytes.isNotEmpty ? Uint8List.fromList(allBytes) : null;
    } catch (_) {
      return null;
    }
  }

  /// 获取最新的转录文本
  Future<String?> _getLatestTranscription() async {
    try {
      final sessionDb = await SessionDatabase.create(widget.sessionId);
      final results = await sessionDb.getAiResultsByType('transcription');
      if (results.isEmpty) return null;
      return results.first.resultText;
    } catch (_) {
      return null;
    }
  }

  /// 保存 AI 结果到数据库
  Future<void> _saveAiResult(
    String taskType,
    String resultText,
    String modelName,
  ) async {
    final result = AiResult(
      id: const Uuid().v4(),
      taskType: taskType,
      resultText: resultText,
      modelName: modelName,
      createdAt: DateTime.now(),
    );

    final sessionDb = await SessionDatabase.create(widget.sessionId);
    await sessionDb.insertAiResult(result);
  }

  /// 删除 AI 结果
  Future<void> _deleteAiResult(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条 AI 结果吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final sessionDb = await SessionDatabase.create(widget.sessionId);
      await sessionDb.deleteAiResult(id);
      _refreshResults();
      if (mounted) {
        _showSnackBar('已删除');
      }
    }
  }

  /// 复制文本到剪贴板
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('已复制到剪贴板');
  }

  /// 显示 SnackBar
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiSettings = ref.watch(aiSettingsProvider);
    final isApiConfigured = aiSettings['apiBaseUrl'] != null &&
        aiSettings['apiBaseUrl']!.isNotEmpty &&
        aiSettings['apiKey'] != null &&
        aiSettings['apiKey']!.isNotEmpty &&
        aiSettings['model'] != null &&
        aiSettings['model']!.isNotEmpty;

    final taskState = ref.watch(aiTaskStateProvider);
    final loadingMessage = ref.watch(aiLoadingMessageProvider);
    final resultsAsync = ref.watch(aiResultsRefreshableProvider(widget.sessionId));

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        title: const Text('AI 功能'),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isApiConfigured
                ? _buildConfiguredBody(context, resultsAsync, colorScheme)
                : _buildUnconfiguredBody(context, colorScheme),
          ),
          // 加载遮罩
          if (taskState == AiTaskState.loading)
            _buildLoadingOverlay(context, loadingMessage, colorScheme),
        ],
      ),
    );
  }

  /// 构建 API 未配置时的提示界面
  Widget _buildUnconfiguredBody(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Center(
      key: const ValueKey('unconfigured'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'AI 功能未配置',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '请先在设置中配置 AI API（OpenAI 兼容格式）',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 API 已配置时的功能界面
  Widget _buildConfiguredBody(
    BuildContext context,
    AsyncValue<List<AiResult>> resultsAsync,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        _refreshResults();
      },
      child: SingleChildScrollView(
        key: const ValueKey('configured'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 功能入口卡片
            Text(
              'AI 功能',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            _buildTranscriptionCard(context, colorScheme),
            const SizedBox(height: 12),
            _buildSummaryCard(context, colorScheme),
            const SizedBox(height: 12),
            _buildMeetingMinutesCard(context, colorScheme),
            const SizedBox(height: 24),

            // AI 结果列表
            Text(
              'AI 结果',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            resultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  return _buildEmptyResults(context, colorScheme);
                }
                return Column(
                  children: results
                      .map((result) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildResultCard(context, result, colorScheme),
                          ))
                      .toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '加载失败：$error',
                        style: TextStyle(color: colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _refreshResults,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建语音转文字卡片
  Widget _buildTranscriptionCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.transcribe,
                color: _primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '语音转文字',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '将录音转换为文字稿，支持时间戳对齐',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _startTranscription,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('开始转换'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建会议摘要卡片
  Widget _buildSummaryCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.summarize,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '会议摘要',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '自动生成会议摘要，提取关键议题',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _generateSummary,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('生成摘要'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建会议记录卡片
  Widget _buildMeetingMinutesCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.description,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '会议记录',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '生成结构化会议记录，包含决议和待办事项',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _generateMeetingMinutes,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('生成记录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建空结果提示
  Widget _buildEmptyResults(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.article_outlined,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无 AI 结果',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '使用上方功能生成 AI 结果',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 AI 结果卡片
  Widget _buildResultCard(
    BuildContext context,
    AiResult result,
    ColorScheme colorScheme,
  ) {
    final isExpanded = _expandedState[result.id] ?? false;
    final typeColor = _getTypeColor(result.taskType);
    final typeLabel = _getTypeLabel(result.taskType);
    final typeIcon = _getTypeIcon(result.taskType);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：类型标签 + 时间
            Row(
              children: [
                Chip(
                  avatar: Icon(typeIcon, size: 16, color: typeColor),
                  label: Text(
                    typeLabel,
                    style: TextStyle(
                      color: typeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: typeColor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Spacer(),
                Text(
                  DateFormatUtil.formatDateTime(result.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 结果文本
            GestureDetector(
              onTap: () {
                setState(() {
                  _expandedState[result.id] = !isExpanded;
                });
              },
              child: AnimatedCrossFade(
                firstChild: Text(
                  result.resultText,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.5,
                      ),
                ),
                secondChild: Text(
                  result.resultText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.5,
                      ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ),
            if (result.resultText.length > 100)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _expandedState[result.id] = !isExpanded;
                    });
                  },
                  child: Text(
                    isExpanded ? '收起' : '展开全部',
                    style: const TextStyle(color: _primaryColor, fontSize: 12),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 底部操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 模型名称
                if (result.modelName != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      result.modelName!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                const Spacer(),
                // 复制按钮
                IconButton(
                  onPressed: () => _copyToClipboard(result.resultText),
                  icon: Icon(
                    Icons.copy,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  tooltip: '复制',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                // 删除按钮
                IconButton(
                  onPressed: () => _deleteAiResult(result.id),
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: colorScheme.error,
                  ),
                  tooltip: '删除',
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建加载遮罩
  Widget _buildLoadingOverlay(
    BuildContext context,
    String message,
    ColorScheme colorScheme,
  ) {
    return Container(
      color: colorScheme.scrim.withValues(alpha: 0.5),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: _primaryColor,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 获取任务类型对应的颜色
  Color _getTypeColor(String taskType) {
    switch (taskType) {
      case 'transcription':
        return Colors.blue;
      case 'summary':
        return Colors.green;
      case 'meeting_minutes':
        return Colors.orange;
      default:
        return _primaryColor;
    }
  }

  /// 获取任务类型对应的标签
  String _getTypeLabel(String taskType) {
    switch (taskType) {
      case 'transcription':
        return '语音转文字';
      case 'summary':
        return '摘要';
      case 'meeting_minutes':
        return '会议记录';
      default:
        return taskType;
    }
  }

  /// 获取任务类型对应的图标
  IconData _getTypeIcon(String taskType) {
    switch (taskType) {
      case 'transcription':
        return Icons.transcribe;
      case 'summary':
        return Icons.summarize;
      case 'meeting_minutes':
        return Icons.description;
      default:
        return Icons.smart_toy;
    }
  }
}
