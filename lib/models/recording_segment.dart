/// 录音段数据模型
///
/// 表示录音时间轴上的一段录音或暂停区间。
/// [isRecording] 为 true 时表示正在录音（红色），false 时表示暂停间隔（灰色）。
/// [endMs] 为 null 时表示该段仍在进行中。
/// Author: GDNDZZK
class RecordingSegment {
  /// 段开始时间（相对于会话开始的毫秒偏移）
  final int startMs;

  /// 段结束时间（相对于会话开始的毫秒偏移），null 表示仍在进行
  final int? endMs;

  /// true = 录音中（红色），false = 暂停间隔（灰色）
  final bool isRecording;

  const RecordingSegment({
    required this.startMs,
    this.endMs,
    required this.isRecording,
  });

  /// 复制并修改部分字段
  RecordingSegment copyWith({int? startMs, int? endMs, bool? isRecording}) {
    return RecordingSegment(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      isRecording: isRecording ?? this.isRecording,
    );
  }

  /// 获取该段的持续时长（毫秒）
  ///
  /// 如果 [endMs] 为 null（仍在进行），则返回从 [startMs] 到 [startMs] 的 0。
  /// 调用方应在使用前用当前时间更新 [endMs]。
  int get durationMs => (endMs ?? startMs) - startMs;

  @override
  String toString() {
    return 'RecordingSegment('
        'startMs: $startMs, '
        'endMs: $endMs, '
        'isRecording: $isRecording'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecordingSegment &&
        other.startMs == startMs &&
        other.endMs == endMs &&
        other.isRecording == isRecording;
  }

  @override
  int get hashCode => Object.hash(startMs, endMs, isRecording);
}
