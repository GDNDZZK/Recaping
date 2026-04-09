import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// AI 任务类型
///
/// Author: GDNDZZK
enum AiTaskType {
  /// 语音转文字
  transcription,

  /// 摘要
  summary,

  /// 会议记录
  meetingMinutes,
}

/// AI 服务 - 调用 OpenAI 兼容 API
///
/// 提供语音转文字、摘要生成、会议记录生成等功能。
/// Author: GDNDZZK
class AiService {
  /// API 基础 URL
  final String baseUrl;

  /// API Key
  final String apiKey;

  /// 模型名称
  final String model;

  AiService({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// 语音转文字
  ///
  /// 将音频数据发送到 Whisper API 进行转录。
  /// [audioData] 音频二进制数据
  /// [format] 音频格式（默认 aac）
  Future<String> transcribe(
    Uint8List audioData, {
    String format = 'aac',
  }) async {
    final uri = Uri.parse('$baseUrl/audio/transcriptions');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files.add(
      http.MultipartFile.fromBytes('file', audioData, filename: 'audio.$format'),
    );
    request.fields['model'] = model;
    request.fields['response_format'] = 'verbose_json';
    request.fields['timestamp_granularities[]'] = 'segment';

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      return (json['text'] as String?) ?? '';
    } else {
      throw Exception(
        'Transcription failed: ${response.statusCode} - $responseBody',
      );
    }
  }

  /// 生成摘要
  ///
  /// 根据转录文本生成简洁的摘要。
  /// [transcriptionText] 转录文本
  Future<String> generateSummary(String transcriptionText) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个专业的会议记录助手。请根据提供的文字稿生成简洁的摘要，包括主要议题、关键观点和结论。',
          },
          {
            'role': 'user',
            'content': '请为以下内容生成摘要：\n\n$transcriptionText',
          },
        ],
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['choices'][0]['message']['content'] as String?) ?? '';
    } else {
      throw Exception(
        'Summary generation failed: ${response.statusCode}',
      );
    }
  }

  /// 生成会议记录
  ///
  /// 根据转录文本生成结构化的会议记录。
  /// [transcriptionText] 转录文本
  Future<String> generateMeetingMinutes(String transcriptionText) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个专业的会议记录助手。请根据提供的文字稿生成结构化的会议记录，包括：\n'
                '1. 会议主题\n'
                '2. 参与者（如可识别）\n'
                '3. 主要议题\n'
                '4. 关键讨论点\n'
                '5. 决议和结论\n'
                '6. 待办事项',
          },
          {
            'role': 'user',
            'content': '请为以下会议内容生成会议记录：\n\n$transcriptionText',
          },
        ],
        'temperature': 0.3,
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['choices'][0]['message']['content'] as String?) ?? '';
    } else {
      throw Exception(
        'Meeting minutes generation failed: ${response.statusCode}',
      );
    }
  }

  /// 测试 API 连接
  ///
  /// 尝试访问 /models 端点验证 API 配置是否正确。
  Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('$baseUrl/models');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
