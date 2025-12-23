import 'dart:async';

import 'package:flutter/material.dart';
import 'terminal_page.dart';
// ignore: unused_import
import 'package:uuid/uuid.dart';
import 'models/connection_model.dart';
import 'services/storage_service.dart';
import 'components/quick_connect_dialog.dart';
import 'services/ssh_service.dart';
import 'sftp_page.dart';

class ManageConnectionsPage extends StatefulWidget {
  const ManageConnectionsPage({super.key});

  @override
  State<ManageConnectionsPage> createState() => _ManageConnectionsPageState();
}

class _ManageConnectionsPageState extends State<ManageConnectionsPage> {
  final _storageService = StorageService();
  List<ConnectionInfo> _connections = [];
  bool _isConnecting = false;
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
  }

  Future<void> _loadConnections() async {
    final connections = await _storageService.getConnections();
    setState(() {
      _connections = connections;
    });
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
      id: _uuid.v4(), // 生成新的唯一ID
      name: '${connection.name}',
      host: connection.host,
      port: connection.port,
      type: targetType,
      credentialId: connection.credentialId, remember: true,
    );

    await _storageService.saveConnection(newConnection);
    await _loadConnections(); // 重新加载列表

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
                setState(() {
                  _loadConnections();
                });
              }
              // ignore: use_build_context_synchronously
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
      final sshService = SshService();

      final credentials = await storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      // 设置3秒超时
      await sshService
          .connect(connection, credential)
          .timeout(const Duration(seconds: 3), onTimeout: () {
        throw TimeoutException('连接超时，请检查网络或主机是否可达');
      });

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
        Navigator.of(context).pop(); // 关闭加载对话框
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理连接'),
        actions: [
          IconButton(
            onPressed: _showNewConnectionDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _connections.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              itemCount: _connections.length,
              itemBuilder: (context, index) {
                final connection = _connections[index];
                final canDup = _canDuplicate(connection);

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: Icon(
                        connection.type == ConnectionType.ssh
                            ? Icons.terminal
                            : Icons.folder,
                      ),
                      title: Text(
                        connection.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${connection.host}:${connection.port}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
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
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'connect',
                            child: ListTile(
                              title: Text('连接'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'duplicate',
                            enabled: canDup, // 如果已存在则禁用
                            child: ListTile(
                              title: Text(connection.type == ConnectionType.ssh
                                  ? '复制为 SFTP'
                                  : '复制为 SSH'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              title: Text('编辑'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              title: Text('删除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _connectTo(connection),
                    ),
                  ),
                );
              }),
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
          Text('点击右上角 + 按钮添加新的连接', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
