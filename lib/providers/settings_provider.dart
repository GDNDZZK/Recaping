import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/config_database.dart';

/// 配置数据库 Provider
///
/// 异步初始化并缓存 [ConfigDatabase] 实例。
/// Author: GDNDZZK
final configDbProvider = FutureProvider<ConfigDatabase>((ref) async {
  final configDb = await ConfigDatabase.create();
  ref.onDispose(() {
    // ConfigDatabase 由 DatabaseHelper 管理生命周期
  });
  return configDb;
});

/// 主题模式 Notifier
///
/// 管理应用主题模式（亮色/暗色/跟随系统），持久化到配置数据库。
/// Author: GDNDZZK
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final Ref _ref;

  ThemeModeNotifier(this._ref) : super(ThemeMode.system) {
    // 初始化时加载主题设置
    loadThemeMode();
  }

  /// 从配置数据库加载主题模式
  Future<void> loadThemeMode() async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      final modeStr = await configDb.getThemeMode();
      if (mounted) {
        state = _parseThemeMode(modeStr);
      }
    } catch (_) {
      // 加载失败时使用默认值（system）
    }
  }

  /// 设置主题模式
  ///
  /// [mode] 目标主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      await configDb.setThemeMode(_themeModeToString(mode));
      if (mounted) {
        state = mode;
      }
    } catch (_) {
      // 持久化失败时仍然更新内存中的状态
      if (mounted) {
        state = mode;
      }
    }
  }

  /// 将字符串解析为 ThemeMode
  ThemeMode _parseThemeMode(String? modeStr) {
    switch (modeStr) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// 将 ThemeMode 转换为字符串
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

/// 主题模式 Provider
///
/// Author: GDNDZZK
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref);
});

/// 录音设置 Notifier
///
/// 管理录音相关设置（音频格式、采样率、声道数），持久化到配置数据库。
/// Author: GDNDZZK
class AudioSettingsNotifier extends StateNotifier<Map<String, dynamic>> {
  final Ref _ref;

  AudioSettingsNotifier(this._ref)
      : super({
          'format': 'aac',
          'sampleRate': 44100,
          'channels': 1,
        }) {
    loadSettings();
  }

  /// 从配置数据库加载录音设置
  Future<void> loadSettings() async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      final format = await configDb.getAudioFormat();
      final sampleRate = await configDb.getSampleRate();

      if (mounted) {
        state = {
          'format': format,
          'sampleRate': sampleRate,
          'channels': state['channels'] ?? 1,
        };
      }
    } catch (_) {
      // 加载失败时使用默认值
    }
  }

  /// 更新录音设置
  ///
  /// [settings] 新的设置项（会与现有设置合并）
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    try {
      final configDb = await _ref.read(configDbProvider.future);

      final newSettings = {...state, ...settings};

      // 持久化到数据库
      if (settings.containsKey('format')) {
        await configDb.setAudioFormat(settings['format'] as String);
      }
      if (settings.containsKey('sampleRate')) {
        await configDb.setSampleRate(settings['sampleRate'] as int);
      }

      if (mounted) {
        state = newSettings;
      }
    } catch (_) {
      // 持久化失败时仍然更新内存中的状态
      if (mounted) {
        state = {...state, ...settings};
      }
    }
  }
}

/// 录音设置 Provider
///
/// Author: GDNDZZK
final audioSettingsProvider =
    StateNotifierProvider<AudioSettingsNotifier, Map<String, dynamic>>((ref) {
  return AudioSettingsNotifier(ref);
});

/// AI API 设置 Notifier
///
/// 管理 AI API 相关设置（基础 URL、API Key、模型名称），持久化到配置数据库。
/// Author: GDNDZZK
class AiSettingsNotifier extends StateNotifier<Map<String, String?>> {
  final Ref _ref;

  AiSettingsNotifier(this._ref)
      : super({
          'apiBaseUrl': null,
          'apiKey': null,
          'model': null,
        }) {
    loadSettings();
  }

  /// 从配置数据库加载 AI 设置
  Future<void> loadSettings() async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      final apiBaseUrl = await configDb.getAiApiBaseUrl();
      final apiKey = await configDb.getAiApiKey();
      final model = await configDb.getAiModel();

      if (mounted) {
        state = {
          'apiBaseUrl': apiBaseUrl,
          'apiKey': apiKey,
          'model': model,
        };
      }
    } catch (_) {
      // 加载失败时使用默认值
    }
  }

  /// 更新 AI API 基础 URL
  Future<void> updateApiBaseUrl(String url) async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      await configDb.setAiApiBaseUrl(url);
      if (mounted) {
        state = {...state, 'apiBaseUrl': url};
      }
    } catch (_) {
      if (mounted) {
        state = {...state, 'apiBaseUrl': url};
      }
    }
  }

  /// 更新 AI API Key
  Future<void> updateApiKey(String key) async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      await configDb.setAiApiKey(key);
      if (mounted) {
        state = {...state, 'apiKey': key};
      }
    } catch (_) {
      if (mounted) {
        state = {...state, 'apiKey': key};
      }
    }
  }

  /// 更新 AI 模型名称
  Future<void> updateModel(String model) async {
    try {
      final configDb = await _ref.read(configDbProvider.future);
      await configDb.setAiModel(model);
      if (mounted) {
        state = {...state, 'model': model};
      }
    } catch (_) {
      if (mounted) {
        state = {...state, 'model': model};
      }
    }
  }
}

/// AI API 设置 Provider
///
/// Author: GDNDZZK
final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, Map<String, String?>>((ref) {
  return AiSettingsNotifier(ref);
});
