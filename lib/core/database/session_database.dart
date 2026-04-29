import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/ai_result.dart';
import '../../models/audio_chunk.dart';
import '../../models/bookmark.dart';
import '../../models/photo.dart';
import '../../models/session.dart';
import '../../models/text_note.dart';
import '../../models/timeline_event.dart';
import '../../models/video_chunk.dart';
import 'database_helper.dart';

/// 会话数据库操作类
///
/// 封装对单个会话目录中 session.db 数据库的所有 CRUD 操作。
/// 数据库只存储元数据和文件路径引用，实际媒体数据存储在文件系统中。
/// Author: GDNDZZK
class SessionDatabase {
  final Database _db;
  final String _sessionId;

  SessionDatabase._(this._db, this._sessionId);

  /// 创建 SessionDatabase 实例
  ///
  /// [sessionId] 会话唯一标识，用于打开对应的 session.db 文件
  static Future<SessionDatabase> create(String sessionId) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.openSessionDatabase(sessionId);
    return SessionDatabase._(db, sessionId);
  }

  /// 从已有的 Database 实例创建
  static SessionDatabase fromDatabase(Database db, String sessionId) {
    return SessionDatabase._(db, sessionId);
  }

  /// 获取会话目录的绝对路径
  Future<String> get sessionDirPath async {
    final dbHelper = DatabaseHelper();
    return dbHelper.sessionDirPath(_sessionId);
  }

  /// 将相对路径转换为绝对路径
  Future<String> resolvePath(String relativePath) async {
    final dir = await sessionDirPath;
    return p.join(dir, relativePath);
  }

  // ==================== info 表操作 ====================

  /// 设置 info 表的键值对
  Future<void> setInfo(String key, String value) async {
    await _db.insert(
      'info',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取 info 表的值
  Future<String?> getInfo(String key) async {
    final results = await _db.query(
      'info',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  /// 获取 info 表的所有键值对
  Future<Map<String, String>> getAllInfo() async {
    final results = await _db.query('info');
    return {for (final row in results) row['key'] as String: row['value'] as String};
  }

  // ==================== Session 元信息 ====================

  /// 保存会话元信息到 info 表
  Future<void> saveSessionInfo(Session session) async {
    final infoMap = session.toInfoMap();
    await _db.transaction((txn) async {
      for (final entry in infoMap.entries) {
        await txn.insert(
          'info',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 获取会话元信息
  Future<Session?> getSessionInfo() async {
    final info = await getAllInfo();
    if (info.isEmpty || !info.containsKey('session_id')) return null;
    return Session.fromInfoMap(info);
  }

  // ==================== AudioChunk 操作 ====================

  /// 插入音频分片
  Future<void> insertAudioChunk(AudioChunk chunk) async {
    await _db.insert('audio_chunks', chunk.toMap());
  }

  /// 获取所有音频分片（按序号排序）
  Future<List<AudioChunk>> getAudioChunks() async {
    final results = await _db.query(
      'audio_chunks',
      orderBy: 'chunk_index ASC',
    );
    return results.map((map) => AudioChunk.fromMap(map)).toList();
  }

  /// 根据序号获取音频分片
  Future<AudioChunk?> getAudioChunkByIndex(int index) async {
    final results = await _db.query(
      'audio_chunks',
      where: 'chunk_index = ?',
      whereArgs: [index],
    );
    if (results.isEmpty) return null;
    return AudioChunk.fromMap(results.first);
  }

  /// 删除音频分片
  Future<void> deleteAudioChunk(String id) async {
    await _db.delete('audio_chunks', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== Photo 操作 ====================

  /// 插入照片
  Future<void> insertPhoto(Photo photo) async {
    await _db.insert('photos', photo.toMap());
  }

  /// 获取所有照片（按时间戳排序）
  Future<List<Photo>> getPhotos() async {
    final results = await _db.query('photos', orderBy: 'timestamp ASC');
    return results.map((map) => Photo.fromMap(map)).toList();
  }

  /// 根据 ID 获取照片
  Future<Photo?> getPhotoById(String id) async {
    final results = await _db.query(
      'photos',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return Photo.fromMap(results.first);
  }

  /// 获取指定时间范围内的照片
  Future<List<Photo>> getPhotosByTimeRange(int startMs, int endMs) async {
    final results = await _db.query(
      'photos',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    return results.map((map) => Photo.fromMap(map)).toList();
  }

  /// 更新照片
  Future<void> updatePhoto(Photo photo) async {
    await _db.update(
      'photos',
      photo.toMap(),
      where: 'id = ?',
      whereArgs: [photo.id],
    );
  }

  /// 删除照片
  Future<void> deletePhoto(String id) async {
    await _db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== VideoChunk 操作 ====================

  /// 插入视频分片
  Future<void> insertVideoChunk(VideoChunk chunk) async {
    await _db.insert('video_chunks', chunk.toMap());
  }

  /// 获取所有视频分片（按开始时间排序）
  Future<List<VideoChunk>> getVideoChunks() async {
    final results = await _db.query(
      'video_chunks',
      orderBy: 'start_time ASC',
    );
    return results.map((map) => VideoChunk.fromMap(map)).toList();
  }

  /// 根据 videoId 获取视频分片
  Future<List<VideoChunk>> getVideoChunksByVideoId(String videoId) async {
    final results = await _db.query(
      'video_chunks',
      where: 'video_id = ?',
      whereArgs: [videoId],
      orderBy: 'chunk_index ASC',
    );
    return results.map((map) => VideoChunk.fromMap(map)).toList();
  }

  /// 根据 ID 获取视频分片
  Future<VideoChunk?> getVideoChunkById(String id) async {
    final results = await _db.query(
      'video_chunks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return VideoChunk.fromMap(results.first);
  }

  /// 更新视频分片
  Future<void> updateVideoChunk(VideoChunk chunk) async {
    await _db.update(
      'video_chunks',
      chunk.toMap(),
      where: 'id = ?',
      whereArgs: [chunk.id],
    );
  }

  /// 删除视频分片
  Future<void> deleteVideoChunk(String id) async {
    await _db.delete('video_chunks', where: 'id = ?', whereArgs: [id]);
  }

  /// 根据 videoId 删除所有相关视频分片
  Future<void> deleteVideoChunksByVideoId(String videoId) async {
    await _db.delete(
      'video_chunks',
      where: 'video_id = ?',
      whereArgs: [videoId],
    );
  }

  // ==================== TextNote 操作 ====================

  /// 插入文字笔记
  Future<void> insertTextNote(TextNote note) async {
    await _db.insert('text_notes', note.toMap());
  }

  /// 获取所有文字笔记（按时间戳排序）
  Future<List<TextNote>> getTextNotes() async {
    final results = await _db.query('text_notes', orderBy: 'timestamp ASC');
    return results.map((map) => TextNote.fromMap(map)).toList();
  }

  /// 根据 ID 获取文字笔记
  Future<TextNote?> getTextNoteById(String id) async {
    final results = await _db.query(
      'text_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return TextNote.fromMap(results.first);
  }

  /// 获取指定时间范围内的文字笔记
  Future<List<TextNote>> getTextNotesByTimeRange(int startMs, int endMs) async {
    final results = await _db.query(
      'text_notes',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    return results.map((map) => TextNote.fromMap(map)).toList();
  }

  /// 更新文字笔记
  Future<void> updateTextNote(TextNote note) async {
    await _db.update(
      'text_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  /// 删除文字笔记
  Future<void> deleteTextNote(String id) async {
    await _db.delete('text_notes', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== Bookmark 操作 ====================

  /// 插入书签
  Future<void> insertBookmark(Bookmark bookmark) async {
    await _db.insert('bookmarks', bookmark.toMap());
  }

  /// 获取所有书签（按时间戳排序）
  Future<List<Bookmark>> getBookmarks() async {
    final results = await _db.query('bookmarks', orderBy: 'timestamp ASC');
    return results.map((map) => Bookmark.fromMap(map)).toList();
  }

  /// 根据 ID 获取书签
  Future<Bookmark?> getBookmarkById(String id) async {
    final results = await _db.query(
      'bookmarks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return Bookmark.fromMap(results.first);
  }

  /// 更新书签
  Future<void> updateBookmark(Bookmark bookmark) async {
    await _db.update(
      'bookmarks',
      bookmark.toMap(),
      where: 'id = ?',
      whereArgs: [bookmark.id],
    );
  }

  /// 删除书签
  Future<void> deleteBookmark(String id) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== AiResult 操作 ====================

  /// 插入 AI 结果
  Future<void> insertAiResult(AiResult result) async {
    await _db.insert('ai_results', result.toMap());
  }

  /// 获取所有 AI 结果（按创建时间排序）
  Future<List<AiResult>> getAiResults() async {
    final results = await _db.query(
      'ai_results',
      orderBy: 'created_at DESC',
    );
    return results.map((map) => AiResult.fromMap(map)).toList();
  }

  /// 根据任务类型获取 AI 结果
  Future<List<AiResult>> getAiResultsByType(String taskType) async {
    final results = await _db.query(
      'ai_results',
      where: 'task_type = ?',
      whereArgs: [taskType],
      orderBy: 'created_at DESC',
    );
    return results.map((map) => AiResult.fromMap(map)).toList();
  }

  /// 删除 AI 结果
  Future<void> deleteAiResult(String id) async {
    await _db.delete('ai_results', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 时间轴事件（聚合查询） ====================

  /// 获取所有时间轴事件（按时间戳排序）
  ///
  /// 聚合照片、视频、笔记、书签和录音区间数据为统一的 TimelineEvent 列表。
  /// 照片和视频的缩略图使用文件路径引用。
  Future<List<TimelineEvent>> getTimelineEvents() async {
    final events = <TimelineEvent>[];

    // 获取照片事件
    final photos = await _db.query('photos', orderBy: 'timestamp ASC');
    for (final map in photos) {
      final thumbnailPath = map['thumbnail_path'] as String?;
      final filePath = map['file_path'] as String?;
      final title = map['title'] as String?;
      events.add(
        TimelineEvent.fromPhoto(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          thumbnailPath: thumbnailPath != null
              ? await resolvePath(thumbnailPath)
              : null,
          mediaFilePath: filePath != null
              ? await resolvePath(filePath)
              : null,
          title: title,
        ),
      );
    }

    // 获取视频事件（取每个 videoId 的第一个分片）
    final videoResults = await _db.rawQuery('''
      SELECT id, start_time, thumbnail_path, file_path, title
      FROM video_chunks
      WHERE chunk_index = (
        SELECT MIN(chunk_index)
        FROM video_chunks v2
        WHERE v2.video_id = video_chunks.video_id
      )
      ORDER BY start_time ASC
    ''');
    for (final map in videoResults) {
      final thumbnailPath = map['thumbnail_path'] as String?;
      final filePath = map['file_path'] as String?;
      final title = map['title'] as String?;
      events.add(
        TimelineEvent.fromVideo(
          id: map['id'] as String,
          timestamp: map['start_time'] as int,
          thumbnailPath: thumbnailPath != null
              ? await resolvePath(thumbnailPath)
              : null,
          mediaFilePath: filePath != null
              ? await resolvePath(filePath)
              : null,
          title: title,
        ),
      );
    }

    // 获取笔记事件
    final notes = await _db.query('text_notes', orderBy: 'timestamp ASC');
    for (final map in notes) {
      events.add(
        TimelineEvent.fromTextNote(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          title: map['title'] as String?,
          content: map['content'] as String,
        ),
      );
    }

    // 获取书签事件
    final bookmarks = await _db.query('bookmarks', orderBy: 'timestamp ASC');
    for (final map in bookmarks) {
      events.add(
        TimelineEvent.fromBookmark(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          label: map['label'] as String?,
          color: map['color'] as String? ?? '#FF6B6B',
        ),
      );
    }

    // 获取录音区间事件（每个 audio_chunk 作为独立事件）
    final audioChunks = await _db.query(
      'audio_chunks',
      orderBy: 'chunk_index ASC',
    );
    for (final map in audioChunks) {
      final chunkIndex = (map['chunk_index'] as int?) ?? 0;
      events.add(
        TimelineEvent.fromAudio(
          id: map['id'] as String,
          startTime: map['start_time'] as int,
          endTime: map['end_time'] as int,
          label: '录音 #${chunkIndex + 1}',
        ),
      );
    }

    // 按时间戳排序
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return events;
  }

  /// 获取指定时间范围内的时间轴事件
  Future<List<TimelineEvent>> getTimelineEventsByTimeRange(
    int startMs,
    int endMs,
  ) async {
    final events = <TimelineEvent>[];

    // 照片
    final photos = await _db.query(
      'photos',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    for (final map in photos) {
      final thumbnailPath = map['thumbnail_path'] as String?;
      final filePath = map['file_path'] as String?;
      final title = map['title'] as String?;
      events.add(
        TimelineEvent.fromPhoto(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          thumbnailPath: thumbnailPath != null
              ? await resolvePath(thumbnailPath)
              : null,
          mediaFilePath: filePath != null
              ? await resolvePath(filePath)
              : null,
          title: title,
        ),
      );
    }

    // 视频
    final videos = await _db.query(
      'video_chunks',
      where: 'start_time >= ? AND start_time <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'start_time ASC',
    );
    for (final map in videos) {
      final thumbnailPath = map['thumbnail_path'] as String?;
      final filePath = map['file_path'] as String?;
      final title = map['title'] as String?;
      events.add(
        TimelineEvent.fromVideo(
          id: map['id'] as String,
          timestamp: map['start_time'] as int,
          thumbnailPath: thumbnailPath != null
              ? await resolvePath(thumbnailPath)
              : null,
          mediaFilePath: filePath != null
              ? await resolvePath(filePath)
              : null,
          title: title,
        ),
      );
    }

    // 笔记
    final notes = await _db.query(
      'text_notes',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    for (final map in notes) {
      events.add(
        TimelineEvent.fromTextNote(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          title: map['title'] as String?,
          content: map['content'] as String,
        ),
      );
    }

    // 书签
    final bookmarks = await _db.query(
      'bookmarks',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'timestamp ASC',
    );
    for (final map in bookmarks) {
      events.add(
        TimelineEvent.fromBookmark(
          id: map['id'] as String,
          timestamp: map['timestamp'] as int,
          label: map['label'] as String?,
          color: map['color'] as String? ?? '#FF6B6B',
        ),
      );
    }

    // 录音区间事件（每个 audio_chunk 作为独立事件，与时间范围有交集的）
    final audioChunks = await _db.query(
      'audio_chunks',
      where: 'start_time <= ? AND end_time >= ?',
      whereArgs: [endMs, startMs],
      orderBy: 'chunk_index ASC',
    );
    for (final map in audioChunks) {
      final chunkIndex = (map['chunk_index'] as int?) ?? 0;
      events.add(
        TimelineEvent.fromAudio(
          id: map['id'] as String,
          startTime: map['start_time'] as int,
          endTime: map['end_time'] as int,
          label: '录音 #${chunkIndex + 1}',
        ),
      );
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return events;
  }

  // ==================== 统计 ====================

  /// 获取事件总数（照片 + 视频 + 笔记 + 书签）
  Future<int> getEventCount() async {
    int count = 0;

    final photoCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM photos'),
    );
    count += photoCount ?? 0;

    final videoCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(DISTINCT video_id) FROM video_chunks'),
    );
    count += videoCount ?? 0;

    final noteCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM text_notes'),
    );
    count += noteCount ?? 0;

    final bookmarkCount = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM bookmarks'),
    );
    count += bookmarkCount ?? 0;

    return count;
  }

  /// 获取总录音时长（毫秒）
  ///
  /// 通过最后一个音频分片的结束时间计算
  Future<int> getAudioDuration() async {
    final result = await _db.rawQuery(
      'SELECT MAX(end_time) as max_end FROM audio_chunks',
    );
    if (result.isEmpty) return 0;
    return (result.first['max_end'] as int?) ?? 0;
  }

  /// 获取数据库文件大小（字节）
  Future<int> getDatabaseSize() async {
    final path = _db.path;
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }
}
