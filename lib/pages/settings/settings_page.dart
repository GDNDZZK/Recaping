import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';

/// 设置页面
///
/// 提供外观设置、录音设置、AI API 配置、存储管理和关于信息。
/// 使用 Riverpod 进行状态管理，所有设置项持久化到数据库。
/// Author: GDNDZZK
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // AI 配置控制器
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;

  /// API Key 是否显示明文
  bool _obscureApiKey = true;

  /// AI 配置是否已修改（用于显示保存按钮）
  bool _aiSettingsModified = false;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController();

    // 初始化后加载存储统计
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storageStatsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// 显示 SnackBar 确认消息
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==================== 外观设置 ====================

  /// 构建外观设置 Section
  Widget _buildAppearanceSection(Color primaryColor) {
    final themeMode = ref.watch(themeModeProvider);

    return _SettingsCard(
      title: '外观',
      primaryColor: primaryColor,
      children: [
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              label: Text('亮色'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              label: Text('暗色'),
              icon: Icon(Icons.dark_mode),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              label: Text('系统'),
              icon: Icon(Icons.brightness_auto),
            ),
          ],
          selected: {themeMode},
          onSelectionChanged: (selection) {
            final mode = selection.first;
            ref.read(themeModeProvider.notifier).setThemeMode(mode);
            final modeName = switch (mode) {
              ThemeMode.light => '亮色模式',
              ThemeMode.dark => '暗色模式',
              ThemeMode.system => '跟随系统',
            };
            _showSnackBar('已切换为$modeName');
          },
        ),
      ],
    );
  }

  // ==================== 录音设置 ====================

  /// 构建录音设置 Section
  Widget _buildRecordingSection(Color primaryColor) {
    final audioSettings = ref.watch(audioSettingsProvider);
    final sampleRate = audioSettings['sampleRate'] as int? ?? AppConstants.defaultSampleRate;
    final channels = audioSettings['channels'] as int? ?? AppConstants.defaultChannels;

    return _SettingsCard(
      title: '录音',
      primaryColor: primaryColor,
      children: [
        // 音频格式（只读）
        const ListTile(
          leading: Icon(Icons.audio_file),
          title: Text('音频格式'),
          subtitle: Text('AAC'),
          trailing: Icon(Icons.lock_outline, size: 18),
        ),
        const Divider(height: 1),

        // 采样率选择
        ListTile(
          leading: const Icon(Icons.graphic_eq),
          title: const Text('采样率'),
          subtitle: Text(_sampleRateLabel(sampleRate)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showSampleRateDialog(sampleRate),
        ),
        const Divider(height: 1),

        // 声道数选择
        ListTile(
          leading: const Icon(Icons.surround_sound),
          title: const Text('声道数'),
          subtitle: Text(_channelLabel(channels)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showChannelDialog(channels),
        ),
      ],
    );
  }

  /// 采样率标签
  String _sampleRateLabel(int rate) {
    return switch (rate) {
      44100 => '44100 Hz（推荐，CD 音质）',
      22050 => '22050 Hz（节省空间）',
      _ => '$rate Hz',
    };
  }

  /// 声道数标签
  String _channelLabel(int channels) {
    return switch (channels) {
      1 => '单声道（推荐，节省空间）',
      2 => '双声道（立体声）',
      _ => '$channels 声道',
    };
  }

  /// 显示采样率选择对话框
  Future<void> _showSampleRateDialog(int currentRate) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择采样率'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 44100),
            child: _RadioOption(
              label: '44100 Hz',
              description: '推荐，CD 音质',
              selected: currentRate == 44100,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 22050),
            child: _RadioOption(
              label: '22050 Hz',
              description: '节省空间',
              selected: currentRate == 22050,
            ),
          ),
        ],
      ),
    );

    if (result != null && result != currentRate) {
      ref.read(audioSettingsProvider.notifier).updateSettings({'sampleRate': result});
      _showSnackBar('采样率已更改为 ${result}Hz');
    }
  }

  /// 显示声道数选择对话框
  Future<void> _showChannelDialog(int currentChannels) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择声道数'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 1),
            child: _RadioOption(
              label: '单声道',
              description: '推荐，节省空间',
              selected: currentChannels == 1,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 2),
            child: _RadioOption(
              label: '双声道',
              description: '立体声',
              selected: currentChannels == 2,
            ),
          ),
        ],
      ),
    );

    if (result != null && result != currentChannels) {
      ref.read(audioSettingsProvider.notifier).updateSettings({'channels': result});
      _showSnackBar('声道数已更改为 ${_channelLabel(result).split('（').first}');
    }
  }

  // ==================== AI 配置 ====================

  /// 构建 AI 配置 Section
  Widget _buildAiSection(Color primaryColor) {
    final aiSettings = ref.watch(aiSettingsProvider);

    // 当 AI 设置从数据库加载后，初始化控制器文本
    // 使用 addPostFrameCallback 避免在 build 中修改状态
    if (!_aiSettingsModified) {
      final apiBaseUrl = aiSettings['apiBaseUrl'] ?? '';
      final apiKey = aiSettings['apiKey'] ?? '';
      final model = aiSettings['model'] ?? '';

      if (_apiBaseUrlController.text != apiBaseUrl) {
        _apiBaseUrlController.text = apiBaseUrl;
      }
      if (_apiKeyController.text != apiKey) {
        _apiKeyController.text = apiKey;
      }
      if (_modelController.text != model) {
        _modelController.text = model;
      }
    }

    return _SettingsCard(
      title: 'AI 功能',
      primaryColor: primaryColor,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '配置 OpenAI 兼容格式的 API，用于语音转文字和会议记录功能',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),

        // API Base URL
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _apiBaseUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.openai.com/v1',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            onChanged: (_) => _markAiModified(),
          ),
        ),
        const SizedBox(height: 12),

        // API Key
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureApiKey = !_obscureApiKey;
                  });
                },
              ),
            ),
            onChanged: (_) => _markAiModified(),
          ),
        ),
        const SizedBox(height: 12),

        // 模型名称
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: '模型名称',
              hintText: 'gpt-4o',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.smart_toy),
            ),
            onChanged: (_) => _markAiModified(),
          ),
        ),
        const SizedBox(height: 12),

        // 保存按钮
        if (_aiSettingsModified)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveAiSettings,
                icon: const Icon(Icons.save),
                label: const Text('保存 AI 配置'),
              ),
            ),
          ),
      ],
    );
  }

  /// 标记 AI 配置已修改
  void _markAiModified() {
    if (!_aiSettingsModified) {
      setState(() {
        _aiSettingsModified = true;
      });
    }
  }

  /// 保存 AI 配置
  Future<void> _saveAiSettings() async {
    final apiBaseUrl = _apiBaseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    await ref.read(aiSettingsProvider.notifier).updateApiBaseUrl(apiBaseUrl);
    await ref.read(aiSettingsProvider.notifier).updateApiKey(apiKey);
    await ref.read(aiSettingsProvider.notifier).updateModel(model);

    setState(() {
      _aiSettingsModified = false;
    });

    _showSnackBar('AI 配置已保存');
  }

  // ==================== 存储管理 ====================

  /// 构建存储管理 Section
  Widget _buildStorageSection(Color primaryColor) {
    final statsAsync = ref.watch(storageStatsProvider);

    return _SettingsCard(
      title: '存储',
      primaryColor: primaryColor,
      children: [
        statsAsync.when(
          data: (stats) {
            if (stats == null) {
              return const ListTile(
                leading: Icon(Icons.storage),
                title: Text('暂无存储数据'),
              );
            }

            final totalSizeStr = _formatBytes(stats.totalSizeBytes);
            final audioSizeStr = _formatBytes(stats.audioSizeBytes);
            final photosSizeStr = _formatBytes(stats.photosSizeBytes);
            final videosSizeStr = _formatBytes(stats.videosSizeBytes);

            return Column(
              children: [
                // 总使用空间
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: const Text('总使用空间'),
                  trailing: Text(
                    totalSizeStr,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),

                // 会话数量
                ListTile(
                  leading: const Icon(Icons.library_books),
                  title: const Text('会话数量'),
                  trailing: Text(
                    '${stats.totalSessions} 个',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),

                // 存储空间可视化
                if (stats.totalSizeBytes > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _StorageLegend(color: primaryColor, label: '音频 $audioSizeStr'),
                            const SizedBox(width: 16),
                            _StorageLegend(color: Colors.green, label: '照片 $photosSizeStr'),
                            const SizedBox(width: 16),
                            _StorageLegend(color: Colors.orange, label: '视频 $videosSizeStr'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: 1.0,
                            minHeight: 8,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (stats.totalSizeBytes > 0) const Divider(height: 1),

                // 清除缓存按钮
                ListTile(
                  leading: Icon(
                    Icons.cleaning_services,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '清除缓存',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  subtitle: const Text('清除临时文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showClearCacheDialog,
                ),
              ],
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('加载存储信息失败'),
            subtitle: Text(error.toString()),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(storageStatsProvider.notifier).refresh(),
            ),
          ),
        ),
      ],
    );
  }

  /// 格式化字节大小
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 ? 2 : 1)} ${units[unitIndex]}';
  }

  /// 显示清除缓存确认对话框
  Future<void> _showClearCacheDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有临时文件吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 清除临时目录
        final tempDir = Directory.systemTemp;
        if (await tempDir.exists()) {
          await tempDir.list().forEach((entity) {
            if (entity is File) {
              entity.deleteSync();
            }
          });
        }
        // 刷新存储统计
        ref.read(storageStatsProvider.notifier).refresh();
        _showSnackBar('缓存已清除');
      } catch (e) {
        if (mounted) {
          _showSnackBar('清除缓存失败：$e');
        }
      }
    }
  }

  // ==================== 关于 ====================

  /// 构建关于 Section
  Widget _buildAboutSection(Color primaryColor) {
    return _SettingsCard(
      title: '关于',
      primaryColor: primaryColor,
      children: [
        // 应用名称
        const ListTile(
          leading: Icon(Icons.apps),
          title: Text('应用名称'),
          subtitle: Text(AppConstants.appName),
        ),
        const Divider(height: 1),

        // 版本号
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('版本号'),
          subtitle: Text(AppConstants.appVersion),
        ),
        const Divider(height: 1),

        // 作者
        const ListTile(
          leading: Icon(Icons.person),
          title: Text('作者'),
          subtitle: Text('GDNDZZK'),
        ),
        const Divider(height: 1),

        // 开源许可
        ListTile(
          leading: const Icon(Icons.description),
          title: const Text('开源许可'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: AppConstants.appVersion,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.mic,
                  size: 48,
                  color: primaryColor,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 外观设置
            _buildAppearanceSection(primaryColor),
            const SizedBox(height: 16),

            // 录音设置
            _buildRecordingSection(primaryColor),
            const SizedBox(height: 16),

            // AI 配置
            _buildAiSection(primaryColor),
            const SizedBox(height: 16),

            // 存储管理
            _buildStorageSection(primaryColor),
            const SizedBox(height: 16),

            // 关于
            _buildAboutSection(primaryColor),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ==================== 辅助组件 ====================

/// 设置卡片组件
///
/// 使用 [Card] 包裹，包含标题和子组件列表。
/// Author: GDNDZZK
class _SettingsCard extends StatelessWidget {
  final String title;
  final Color primaryColor;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    required this.primaryColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
            // 子组件
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 单选项组件（带 Radio 效果）
///
/// 用于选择对话框中的选项展示。
/// Author: GDNDZZK
class _RadioOption extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;

  const _RadioOption({
    required this.label,
    required this.description,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 存储图例组件
///
/// 显示颜色圆点 + 标签文字。
/// Author: GDNDZZK
class _StorageLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _StorageLegend({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
