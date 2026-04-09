# Recaping

<p align="center">
  <strong>多媒体录音记录应用</strong>
</p>

Recaping 是一款专注于多媒体录音记录的 Flutter 应用程序。它允许用户在录音过程中同时拍摄照片、录制短视频片段和添加文字笔记，形成完整的多媒体时间轴记录。录音完成后，用户可以回放录音并查看所有关联的多媒体内容，还可以使用 AI 功能进行语音转文字、智能摘要和会议记录生成。

## 功能特性

### 🎙️ 录音功能
- 持续录音，15 秒自动分段存储（AAC 格式）
- 支持暂停/继续录音
- 实时波形动画指示器
- 录音状态实时显示

### 📸 多媒体记录
- 拍照记录（录音过程中随时拍摄）
- 短视频片段录制
- 文字笔记添加（标题 + 内容）
- 书签标记（标签 + 颜色）

### ⏱️ 时间轴展示
- 录音实时时间轴（录音过程中同步显示）
- 回放时间轴（播放进度同步高亮）
- 多类型事件展示（照片/视频/笔记/书签）
- 事件点击跳转到对应时间点

### ▶️ 回放功能
- 音频分片无缝衔接播放
- 播放/暂停/跳转控制
- 变速播放（0.5x ~ 2.0x）
- 快退 15 秒 / 快进 15 秒
- 多媒体内容同步显示

### 🤖 AI 功能
- 语音转文字（Whisper API）
- 智能摘要生成
- 会议记录生成
- 支持任何 OpenAI 兼容 API

### ⚙️ 设置
- 主题切换（亮色/暗色/跟随系统）
- 录音设置（采样率、声道数）
- AI API 配置
- 存储空间管理

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.41.6 + Dart 3.11.4 |
| 数据库 | sqflite（SQLite） |
| 音频录制 | record |
| 音频播放 | just_audio |
| 相机 | image_picker |
| 状态管理 | flutter_riverpod |
| 路由 | go_router |
| 网络请求 | http |
| 国际化 | intl |

## 项目结构

```
lib/
├── main.dart                  # 应用入口
├── app.dart                   # 应用配置（路由、主题）
├── core/
│   ├── constants/
│   │   └── app_constants.dart # 应用常量
│   ├── database/
│   │   ├── database_helper.dart   # 数据库管理器
│   │   ├── session_database.dart  # 会话数据库操作
│   │   └── config_database.dart   # 配置数据库操作
│   └── utils/
│       ├── date_format_util.dart  # 日期格式化工具
│       └── thumbnail_util.dart    # 缩略图生成工具
├── models/
│   ├── session.dart           # 会话模型
│   ├── audio_chunk.dart       # 音频分片模型
│   ├── video_chunk.dart       # 视频分片模型
│   ├── photo.dart             # 照片模型
│   ├── text_note.dart         # 文字笔记模型
│   ├── bookmark.dart          # 书签模型
│   ├── ai_result.dart         # AI 结果模型
│   └── timeline_event.dart    # 时间轴事件模型
├── services/
│   ├── recording_service.dart     # 录音服务
│   ├── audio_playback_service.dart # 音频回放服务
│   ├── camera_service.dart        # 相机服务
│   ├── timeline_service.dart      # 时间轴服务
│   ├── storage_service.dart       # 存储管理服务
│   └── ai_service.dart            # AI 服务
├── providers/
│   ├── recording_provider.dart    # 录音状态管理
│   ├── session_provider.dart      # 会话列表状态管理
│   ├── playback_provider.dart     # 回放状态管理
│   ├── settings_provider.dart     # 设置状态管理
│   └── ai_provider.dart           # AI 状态管理
├── pages/
│   ├── home/home_page.dart        # 首页（会话列表）
│   ├── record/record_page.dart    # 录音页面
│   ├── playback/playback_page.dart # 回放页面
│   ├── settings/settings_page.dart # 设置页面
│   └── ai/ai_page.dart            # AI 功能页面
└── widgets/
    ├── audio/
    │   └── audio_player_controls.dart  # 音频播放控制组件
    ├── common/
    │   ├── image_viewer.dart           # 图片查看组件
    │   └── session_card.dart           # 会话卡片组件
    ├── recording_controls/
    │   ├── recording_controls.dart     # 录音控制按钮组
    │   └── waveform_indicator.dart     # 波形动画指示器
    └── timeline/
        ├── recording_timeline.dart     # 录音时间轴组件
        ├── playback_timeline.dart      # 回放时间轴组件
        └── timeline_event_item.dart    # 时间轴事件项组件
```

## 如何运行

### 环境要求

- Flutter SDK >= 3.41.6
- Dart SDK >= 3.11.4
- Android Studio / VS Code
- Xcode（iOS 开发）
- Android SDK（Android 开发）

### 安装步骤

1. **克隆项目**
   ```bash
   git clone <repository-url>
   cd Recaping
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行应用**
   ```bash
   # Android
   flutter run

   # iOS
   cd ios && pod install && cd ..
   flutter run
   ```

4. **代码分析**
   ```bash
   flutter analyze
   ```

### 权限说明

应用需要以下权限：
- **麦克风**：录音功能
- **相机**：拍照和录像功能
- **存储**：保存录音和媒体文件（Android）

## 作者

**GDNDZZK**

## 许可证

本项目基于 GPL-3.0 许可证开源。详见 [LICENSE](LICENSE) 文件。
