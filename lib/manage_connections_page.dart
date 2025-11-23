import 'dart:async';

import 'package:flutter/material.dart';
import 'terminal_page.dart';
// ignore: unused_import
import 'package:uuid/uuid.dart';
import 'models/connection_model.dart';
import 'services/storage_service.dart';
import 'quick_connect_dialog.dart';
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
      await sshService.connect(connection, credential)
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
          Container(
            margin: const EdgeInsets.only(right: 10),
            child: IconButton(
              onPressed: _showNewConnectionDialog,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      body: _connections.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.no_encryption_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无保存的连接', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 8),
                  Text(
                    '点击右上角 + 按钮添加新的连接',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _connections.length,
              itemBuilder: (context, index) {
                final connection = _connections[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.computer),
                    title: Text(connection.name),
                    subtitle: Text(
                      '${connection.host}:${connection.port} - ${connection.type.displayName}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _isConnecting ? null : () => _connectTo(connection),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: '连接',
                        ),
                        IconButton(
                          onPressed: _isConnecting ? null : () => _editConnection(connection),
                          icon: const Icon(Icons.edit),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          onPressed: _isConnecting ? null : () => _deleteConnection(connection),
                          icon: const Icon(Icons.delete),
                          tooltip: '删除',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}