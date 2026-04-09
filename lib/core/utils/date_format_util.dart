import 'package:intl/intl.dart';

/// 日期格式化工具类
///
/// 提供时长、日期时间和相对时间的格式化方法。
/// Author: GDNDZZK
class DateFormatUtil {
  DateFormatUtil._();

  /// 格式化时长（毫秒 → HH:mm:ss）
  ///
  /// [milliseconds] 时长毫秒数
  ///
  /// 返回格式为 `HH:mm:ss` 的字符串。
  static String formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// 格式化日期时间
  ///
  /// [dateTime] 要格式化的日期时间
  /// [pattern] 格式模式，默认为 `yyyy-MM-dd HH:mm`
  ///
  /// 返回格式化后的字符串。
  static String formatDateTime(DateTime dateTime, {String pattern = 'yyyy-MM-dd HH:mm'}) {
    return DateFormat(pattern).format(dateTime);
  }

  /// 格式化相对时间
  ///
  /// [dateTime] 要格式化的日期时间
  ///
  /// 返回相对时间描述，如"刚刚"、"3分钟前"、"昨天"等。
  static String formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24 && now.day == dateTime.day) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 1) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays < 2 &&
        now.subtract(const Duration(days: 1)).day == dateTime.day) {
      return '昨天 ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks周前';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months个月前';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years年前';
    }
  }
}
