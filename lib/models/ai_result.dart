/// AI 结果模型
///
/// 代表 AI 处理的结果，包括转文字、摘要、会议纪要等类型。
/// Author: GDNDZZK
class AiResult {
  /// 结果唯一标识（UUID）
  final String id;

  /// 任务类型
  ///
  /// 支持的类型：
  /// - `transcription`：语音转文字
  /// - `summary`：智能摘要
  /// - `meeting_minutes`：会议纪要
  final String taskType;

  /// 结果文本内容
  final String resultText;

  /// 使用的 AI 模型名称（可选）
  final String? modelName;

  /// 创建时间
  final DateTime createdAt;

  const AiResult({
    required this.id,
    required this.taskType,
    required this.resultText,
    this.modelName,
    required this.createdAt,
  });

  /// 从数据库 Map 创建 AiResult 实例
  factory AiResult.fromMap(Map<String, dynamic> map) {
    return AiResult(
      id: map['id'] as String,
      taskType: map['task_type'] as String,
      resultText: map['result_text'] as String,
      modelName: map['model_name'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_type': taskType,
      'result_text': resultText,
      'model_name': modelName,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改部分字段
  AiResult copyWith({
    String? id,
    String? taskType,
    String? resultText,
    String? modelName,
    DateTime? createdAt,
  }) {
    return AiResult(
      id: id ?? this.id,
      taskType: taskType ?? this.taskType,
      resultText: resultText ?? this.resultText,
      modelName: modelName ?? this.modelName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'AiResult('
        'id: $id, '
        'taskType: $taskType, '
        'modelName: $modelName'
        ')';
  }
}
