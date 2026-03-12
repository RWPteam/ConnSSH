// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/telnet_storage_service.dart';
import '../../models/telnet_connection_model.dart';
import '../services/telnet_service.dart';
import 'telnet_terminal.dart';
import '../components/telnet_connect_dialog.dart';

class ManageTelnetConnectionsPage extends StatefulWidget {
  const ManageTelnetConnectionsPage({super.key});

  @override
  State<ManageTelnetConnectionsPage> createState() =>
      _ManageTelnetConnectionsPageState();
}

class _ManageTelnetConnectionsPageState
    extends State<ManageTelnetConnectionsPage> {
  final _telnetStorageService = TelnetStorageService();
  List<TelnetConnectionInfo> _connections = [];
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final connections = await _telnetStorageService.getConnections();
    setState(() {
      _connections = connections;
    });
  }

  void _editConnection(TelnetConnectionInfo connection) {
    showDialog(
      context: context,
      builder: (context) => TelnetConnectDialog(
        connection: connection,
        isNewConnection: false,
      ),
    ).then((_) => _loadConnections());
  }

  void _deleteConnection(TelnetConnectionInfo connection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除Telnet连接'),
        content: Text('要删除连接 "${connection.name}" 吗？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              await _telnetStorageService.deleteConnection(connection.id);
              if (mounted) {
                _loadConnections();
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

  void _connectTo(TelnetConnectionInfo connection) async {
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
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在连接到Telnet服务器...'),
            ],
          ),
        );
      },
    );

    try {
      final testService = TelnetService();
      await testService.connect(connection);
      await Future.delayed(const Duration(milliseconds: 500));
      testService.disconnect();

      await _telnetStorageService.addRecentConnection(connection);

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TelnetTerminalPage(
              connection: connection,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text('无法连接到服务器: $e'),
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
      builder: (context) => const TelnetConnectDialog(isNewConnection: true),
    ).then((_) => _loadConnections());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理Telnet连接'),
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
                      // 修改后的图标样式：圆形背景 + 主题色图标
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.terminal,
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
                      // 修改后的操作按钮：使用 PopupMenuButton 替代 Row
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'connect':
                              _connectTo(connection);
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
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              title: Text('编辑'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              title: Text(
                                '删除',
                                style: TextStyle(color: Colors.red),
                              ),
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
          Icon(Icons.terminal_outlined, size: 64, color: Colors.blueGrey),
          SizedBox(height: 16),
          Text('暂无保存的Telnet连接', style: TextStyle(fontSize: 16)),
          Text('点击右上角 + 按钮添加新的连接', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
