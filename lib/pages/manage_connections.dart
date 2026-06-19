// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'terminal.dart';
import 'package:uuid/uuid.dart';
import '../models/connection_model.dart';
import '../services/storage_service.dart';
import '../components/quick_connect_dialog.dart';
import 'sftpview.dart';
import '../widgets/app_style.dart';

class ManageConnectionsPage extends StatefulWidget {
  const ManageConnectionsPage({super.key});

  @override
  State<ManageConnectionsPage> createState() => _ManageConnectionsPageState();
}

class _ManageConnectionsPageState extends State<ManageConnectionsPage> {
  final _storageService = StorageService();
  List<ConnectionInfo> _connections = [];
  List<ArchiveGroup> _archiveGroups = [];
  bool _isConnecting = false;
  bool _isUngroupedExpanded = true; // 添加未分组展开状态
  final _uuid = const Uuid();

  bool _canDuplicate(ConnectionInfo current) {
    final targetType = current.type == ConnectionType.ssh
        ? ConnectionType.sftp
        : ConnectionType.ssh;

    return !_connections.any((c) =>
        c.host == current.host &&
        c.port == current.port &&
        c.credentialId == current.credentialId &&
        c.type == targetType);
  }

  @override
  void initState() {
    super.initState();
    _loadConnections();
    _loadArchiveGroups();
  }

  Future<void> _loadConnections() async {
    final connections = await _storageService.getConnections();
    connections
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _connections = connections;
    });
  }

  Future<void> _loadArchiveGroups() async {
    final groups = await _storageService.getArchiveGroups();
    setState(() {
      _archiveGroups = groups;
    });
  }

  void _createArchiveGroup() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建分组'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入分组名称',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  Navigator.of(context).pop();
                  _saveArchiveGroup(text);
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveArchiveGroup(String name) async {
    final newGroup = ArchiveGroup(
      id: _uuid.v4(),
      name: name,
    );
    await _storageService.saveArchiveGroup(newGroup);
    await _loadArchiveGroups();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分组 "$name" 创建成功')),
      );
    }
  }

  void _editArchiveGroup(ArchiveGroup group) {
    showDialog(
      context: context,
      builder: (context) => ArchiveGroupEditDialog(
        group: group,
        connections: _connections,
        onSave: (updatedGroup, selectedConnections) async {
          final updated = ArchiveGroup(
            id: group.id,
            name: updatedGroup.name,
            connectionIds: selectedConnections.map((c) => c.id).toList(),
            isExpanded: group.isExpanded,
          );

          await _storageService.saveArchiveGroup(updated);

          for (var connection in _connections) {
            if (selectedConnections.contains(connection)) {
              connection.archive = updatedGroup.name;
            } else if (connection.archive == group.name) {
              connection.archive = null;
            }
            await _storageService.saveConnection(connection);
          }

          await _loadConnections();
          await _loadArchiveGroups();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('分组 "${updatedGroup.name}" 已更新')),
            );
          }
        },
      ),
    );
  }

  void _deleteArchiveGroup(ArchiveGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('要删除分组 "${group.name}" 吗？分组内的连接不会被删除'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              await _storageService.deleteArchiveGroup(group.id);
              await _loadArchiveGroups();
              await _loadConnections();
              Navigator.of(context).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGroupExpanded(ArchiveGroup group) async {
    final updated = ArchiveGroup(
      id: group.id,
      name: group.name,
      connectionIds: group.connectionIds,
      isExpanded: !group.isExpanded,
    );
    await _storageService.saveArchiveGroup(updated);
    await _loadArchiveGroups();
  }

  void _editConnection(ConnectionInfo connection) {
    showDialog(
      context: context,
      builder: (context) => QuickConnectDialog(connection: connection),
    ).then((_) => _loadConnections());
  }

  Future<void> _duplicateConnection(ConnectionInfo connection) async {
    final targetType = connection.type == ConnectionType.ssh
        ? ConnectionType.sftp
        : ConnectionType.ssh;
    final typeName = targetType == ConnectionType.ssh ? 'SSH' : 'SFTP';

    final newConnection = ConnectionInfo(
      id: _uuid.v4(),
      name: '${connection.name}',
      host: connection.host,
      port: connection.port,
      type: targetType,
      credentialId: connection.credentialId,
      remember: true,
      archive: connection.archive,
    );

    await _storageService.saveConnection(newConnection);

    if (connection.archive != null && connection.archive!.isNotEmpty) {
      final groups = await _storageService.getArchiveGroups();
      final targetGroup = groups.firstWhere(
        (g) => g.name == connection.archive,
        orElse: () => throw Exception('分组不存在'),
      );
      final updatedGroup = ArchiveGroup(
        id: targetGroup.id,
        name: targetGroup.name,
        connectionIds: [...targetGroup.connectionIds, newConnection.id],
        isExpanded: targetGroup.isExpanded,
      );
      await _storageService.saveArchiveGroup(updatedGroup);
    }

    await _loadConnections();
    await _loadArchiveGroups();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功复制为 $typeName 连接')),
      );
    }
  }

  void _deleteConnection(ConnectionInfo connection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('要删除连接 "${connection.name}" 吗？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              await _storageService.deleteConnection(connection.id);
              if (mounted) {
                await _loadConnections();
              }
              Navigator.of(context).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _connectTo(ConnectionInfo connection) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          backgroundColor: Colors.transparent,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('正在测试连接...'),
            ],
          ),
        );
      },
    );

    try {
      final storageService = StorageService();
      //final sshService = SshService();

      final credentials = await storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      //await sshService
      //    .connect(connection, credential)
      //    .timeout(const Duration(seconds: 3), onTimeout: () {
      //  throw TimeoutException('连接超时，请检查网络或主机是否可达');
      //});

      unawaited(storageService.addRecentConnection(connection));

      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        if (connection.type == ConnectionType.sftp) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SftpPage(
                connection: connection,
                credential: credential,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TerminalPage(
                connection: connection,
                credential: credential,
              ),
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(e.message ?? '连接超时'),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(e.toString()),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _showNewConnectionDialog() {
    showDialog(
      context: context,
      builder: (context) => const QuickConnectDialog(isNewConnection: true),
    ).then((_) => _loadConnections());
  }

  @override
  Widget build(BuildContext context) {
    final groupedConnections = <String, List<ConnectionInfo>>{};
    final ungroupedConnections = <ConnectionInfo>[];

    for (var connection in _connections) {
      if (connection.archive != null && connection.archive!.isNotEmpty) {
        groupedConnections.putIfAbsent(connection.archive!, () => []);
        groupedConnections[connection.archive]!.add(connection);
      } else {
        ungroupedConnections.add(connection);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理连接'),
        actions: [
          IconButton(
            onPressed: _createArchiveGroup,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '创建分组',
          ),
          IconButton(
            onPressed: _showNewConnectionDialog,
            icon: const Icon(Icons.add),
            tooltip: '新建连接',
          ),
        ],
      ),
      body: _connections.isEmpty && _archiveGroups.isEmpty
          ? _buildEmptyState()
          : ListView(
              children: [
                ..._archiveGroups.map((group) {
                  final groupConnections = groupedConnections[group.name] ?? [];
                  return _buildGroupTile(group, groupConnections);
                }).toList(),
                if (ungroupedConnections.isNotEmpty) ...[
                  _buildUngroupedHeaderTile(ungroupedConnections.length),
                  if (_isUngroupedExpanded) // 根据展开状态显示连接列表
                    ...ungroupedConnections
                        .map((connection) =>
                            _buildConnectionTile(connection, withMargin: true))
                        .toList(),
                ],
              ],
            ),
    );
  }

  Widget _buildUngroupedHeaderTile(int count) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: AppRadius.largeRadius,
            ),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isUngroupedExpanded = !_isUngroupedExpanded;
                });
              },
              borderRadius: AppRadius.largeRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isUngroupedExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '未分组',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '$count 个连接',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTile(ArchiveGroup group, List<ConnectionInfo> connections) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _toggleGroupExpanded(group),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: AppRadius.largeRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        group.isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${connections.length} 个连接',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _editArchiveGroup(group),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.edit, size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _deleteArchiveGroup(group),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.delete, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (group.isExpanded && connections.isNotEmpty)
            ...connections
                .map((connection) => Container(
                      margin: const EdgeInsets.only(top: 6),
                      child:
                          _buildConnectionTile(connection, withMargin: false),
                    ))
                .toList(),
        ],
      ),
    );
  }

  Future<void> _showConnectionActionSheet(
    ConnectionInfo connection,
    bool canDup,
  ) async {
    final value = await showAppActionSheet<String>(
      context,
      title: connection.name,
      items: [
        const AppActionSheetItem<String>(
          value: 'connect',
          label: '连接',
          icon: Icons.play_arrow_rounded,
        ),
        if (canDup)
          AppActionSheetItem<String>(
            value: 'duplicate',
            label: connection.type == ConnectionType.ssh ? '复制为 SFTP' : '复制为 SSH',
            icon: Icons.copy_all_rounded,
          ),
        const AppActionSheetItem<String>(
          value: 'edit',
          label: '编辑',
          icon: Icons.edit_outlined,
        ),
        const AppActionSheetItem<String>(
          value: 'delete',
          label: '删除',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );

    switch (value) {
      case 'connect':
        _connectTo(connection);
        break;
      case 'duplicate':
        _duplicateConnection(connection);
        break;
      case 'edit':
        _editConnection(connection);
        break;
      case 'delete':
        _deleteConnection(connection);
        break;
    }
  }

  Widget _buildConnectionTile(ConnectionInfo connection,
      {bool withMargin = true}) {
    final canDup = _canDuplicate(connection);

    return Container(
      margin: withMargin
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(
          color: Colors.grey,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.largeRadius,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              connection.type == ConnectionType.ssh
                  ? Icons.terminal
                  : Icons.folder,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            connection.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${connection.host}:${connection.port}',
            style: TextStyle(color: Colors.grey[600]),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: '更多',
            onPressed: () => _showConnectionActionSheet(connection, canDup),
          ),
          onTap: () => _connectTo(connection),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.no_encryption_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('暂无保存的连接', style: TextStyle(fontSize: 16)),
          Text('点击右上角按钮添加连接', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class ArchiveGroupEditDialog extends StatefulWidget {
  final ArchiveGroup group;
  final List<ConnectionInfo> connections;
  final Function(ArchiveGroup, List<ConnectionInfo>) onSave;

  const ArchiveGroupEditDialog({
    super.key,
    required this.group,
    required this.connections,
    required this.onSave,
  });

  @override
  State<ArchiveGroupEditDialog> createState() => _ArchiveGroupEditDialogState();
}

class _ArchiveGroupEditDialogState extends State<ArchiveGroupEditDialog> {
  late TextEditingController _nameController;
  late List<ConnectionInfo> _selectedConnections;
  late List<ConnectionInfo> _sortedConnections;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _selectedConnections = widget.connections
        .where((c) => widget.group.connectionIds.contains(c.id))
        .toList();
    _sortedConnections = List<ConnectionInfo>.from(widget.connections)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggleConnection(ConnectionInfo connection) {
    setState(() {
      if (_selectedConnections.contains(connection)) {
        _selectedConnections.remove(connection);
      } else {
        _selectedConnections.add(connection);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '编辑分组',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '分组名称',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                '选择连接',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.connections.length,
                itemBuilder: (context, index) {
                  final connection = widget.connections[index];
                  final isSelected = _selectedConnections.contains(connection);

                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: AppRadius.largeRadius,
                      border: Border.all(
                        color: Colors.grey,
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.largeRadius,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _toggleConnection(connection),
                          borderRadius: AppRadius.largeRadius,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    connection.type == ConnectionType.ssh
                                        ? Icons.terminal
                                        : Icons.folder,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        connection.name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: null),
                                      ),
                                      Text(
                                        '${connection.host}:${connection.port}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      final updatedGroup = ArchiveGroup(
                        id: widget.group.id,
                        name: _nameController.text.trim(),
                        connectionIds:
                            _selectedConnections.map((c) => c.id).toList(),
                        isExpanded: widget.group.isExpanded,
                      );
                      widget.onSave(updatedGroup, _selectedConnections);
                      Navigator.of(context).pop();
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
