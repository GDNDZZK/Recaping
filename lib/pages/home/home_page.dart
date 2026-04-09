import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/session.dart';
import '../../providers/session_provider.dart';
import '../../widgets/common/session_card.dart';

/// 首页
///
/// 显示会话列表，提供搜索、新建录音入口。
/// 支持搜索、滑动删除、长按菜单、编辑标题等操作。
/// Author: GDNDZZK
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 搜索栏是否展开
  bool _isSearchExpanded = false;

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 编辑标题控制器
  final TextEditingController _editTitleController = TextEditingController();

  /// 搜索焦点节点
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 页面初始化时自动加载会话列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionListProvider.notifier).loadSessions();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _editTitleController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionListProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recaping',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        actions: [
          // 搜索按钮
          IconButton(
            icon: Icon(_isSearchExpanded ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
        bottom: _isSearchExpanded
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索录音...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
              )
            : null,
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _buildErrorState(error, colorScheme),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _buildEmptyState(colorScheme);
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(sessionListProvider.notifier).loadSessions(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return SessionCard(
                  session: session,
                  onTap: () => context.go('/playback/${session.sessionId}'),
                  onLongPress: () => _showBottomMenu(session),
                  onDelete: () => _confirmDelete(session),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/record'),
        icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
        label: const Text('开始录音'),
      ),
    );
  }

  /// 切换搜索栏展开/收起
  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        _searchFocusNode.unfocus();
        // 收起搜索栏时重新加载全部会话
        ref.read(sessionListProvider.notifier).loadSessions();
      } else {
        // 展开搜索栏时自动聚焦
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// 清空搜索内容
  void _clearSearch() {
    _searchController.clear();
    ref.read(sessionListProvider.notifier).loadSessions();
  }

  /// 搜索内容变化回调
  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      ref.read(sessionListProvider.notifier).loadSessions();
    } else {
      ref.read(sessionListProvider.notifier).searchSessions(query);
    }
  }

  /// 构建空状态
  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none,
            size: 80,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有录音记录',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮开始第一次录音',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误状态
  Widget _buildErrorState(Object error, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () =>
                ref.read(sessionListProvider.notifier).loadSessions(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 显示底部菜单（长按触发）
  void _showBottomMenu(Session session) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              // 编辑标题
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑标题'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(session);
                },
              ),
              // 删除
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(session);
                },
              ),
              // 查看详情
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('查看详情'),
                onTap: () {
                  Navigator.pop(context);
                  _showDetailDialog(session);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 确认删除对话框
  void _confirmDelete(Session session) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('确定要删除「${session.title}」吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () {
                Navigator.pop(context);
                ref.read(sessionListProvider.notifier).deleteSession(session.sessionId);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  /// 显示编辑标题对话框
  void _showEditDialog(Session session) {
    _editTitleController.text = session.title;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑标题'),
          content: TextField(
            controller: _editTitleController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '输入新标题',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final newTitle = _editTitleController.text.trim();
                if (newTitle.isNotEmpty) {
                  Navigator.pop(context);
                  ref.read(sessionListProvider.notifier).updateSession(
                        session.copyWith(title: newTitle),
                      );
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  /// 显示详情对话框
  void _showDetailDialog(Session session) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('会话详情'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('标题', session.title),
                _buildDetailRow('创建时间', session.createdAt.toString()),
                _buildDetailRow('更新时间', session.updatedAt.toString()),
                _buildDetailRow('时长', '${session.audioDuration} ms'),
                _buildDetailRow('事件数', '${session.eventCount}'),
                if (session.tags.isNotEmpty)
                  _buildDetailRow('标签', session.tags.join(', ')),
                if (session.description != null)
                  _buildDetailRow('描述', session.description!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
