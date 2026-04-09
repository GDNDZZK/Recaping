import 'package:flutter/material.dart';

import '../../services/recording_service.dart';

/// 录音控制按钮组
///
/// 提供录音/暂停切换按钮和停止按钮。
/// 根据当前录音状态显示不同的按钮样式。
/// Author: GDNDZZK
class RecordingControls extends StatelessWidget {
  /// 当前录音状态
  final RecordingState state;

  /// 开始录音回调
  final VoidCallback onStart;

  /// 暂停录音回调
  final VoidCallback onPause;

  /// 继续录音回调
  final VoidCallback onResume;

  /// 停止录音回调
  final VoidCallback onStop;

  const RecordingControls({
    super.key,
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 停止按钮（录音中或暂停时显示）
        if (state == RecordingState.recording ||
            state == RecordingState.paused)
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: _StopButton(onStop: onStop),
          ),

        // 主录音/暂停按钮
        _MainRecordButton(
          state: state,
          onStart: onStart,
          onPause: onPause,
          onResume: onResume,
          theme: theme,
        ),
      ],
    );
  }
}

/// 主录音/暂停按钮
///
/// 根据录音状态切换显示：
/// - 空闲：大的红色圆形录音按钮
/// - 录音中：大的暂停按钮
/// - 暂停中：大的继续录音按钮
/// Author: GDNDZZK
class _MainRecordButton extends StatelessWidget {
  final RecordingState state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final ThemeData theme;

  const _MainRecordButton({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case RecordingState.idle:
        return _RecordButton(
          icon: Icons.fiber_manual_record,
          color: const Color(0xFFFF4444),
          size: 72,
          onPressed: onStart,
          tooltip: '开始录音',
        );
      case RecordingState.recording:
        return _RecordButton(
          icon: Icons.pause,
          color: theme.colorScheme.primary,
          size: 72,
          onPressed: onPause,
          tooltip: '暂停录音',
        );
      case RecordingState.paused:
        return _RecordButton(
          icon: Icons.fiber_manual_record,
          color: const Color(0xFFFF4444),
          size: 72,
          onPressed: onResume,
          tooltip: '继续录音',
        );
      case RecordingState.stopped:
        return _RecordButton(
          icon: Icons.fiber_manual_record,
          color: Colors.grey,
          size: 72,
          onPressed: onStart,
          tooltip: '开始录音',
        );
    }
  }
}

/// 录音按钮组件
///
/// 圆形按钮，带图标和点击效果。
/// Author: GDNDZZK
class _RecordButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;
  final String tooltip;

  const _RecordButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: FloatingActionButton(
          onPressed: onPressed,
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          highlightElevation: 8,
          child: Icon(icon, size: size * 0.45),
        ),
      ),
    );
  }
}

/// 停止按钮组件
///
/// 小的方形停止按钮。
/// Author: GDNDZZK
class _StopButton extends StatelessWidget {
  final VoidCallback onStop;

  const _StopButton({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '停止录音',
      child: SizedBox(
        width: 52,
        height: 52,
        child: FloatingActionButton(
          onPressed: onStop,
          backgroundColor: Colors.grey.shade700,
          foregroundColor: Colors.white,
          elevation: 2,
          child: const Icon(Icons.stop, size: 28),
        ),
      ),
    );
  }
}
