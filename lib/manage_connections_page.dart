// manage_connections_page.dart
import 'package:flutter/material.dart';
// ignore: unused_import
import 'package:uuid/uuid.dart';
import 'models/connection_model.dart';
import 'services/storage_service.dart';
import 'quick_connect_dialog.dart';

class ManageConnectionsPage extends StatefulWidget {
  const ManageConnectionsPage({super.key});

  @override
  State<ManageConnectionsPage> createState() => _ManageConnectionsPageState();
}

class _ManageConnectionsPageState extends State<ManageConnectionsPage> {
  final _storageService = StorageService();
  List<ConnectionInfo> _connections = [];

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
    builder: (context) => QuickConnectDialog(connection: connection), // 传入连接进行编辑
  ).then((_) => _loadConnections());
}

void _deleteConnection(ConnectionInfo connection) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除连接'),
      content: Text('确定要删除连接 "${connection.name}" 吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            await _storageService.deleteConnection(connection.id);
            if (mounted) {
              setState(() {
                _loadConnections(); // 立即重新加载
              });
            }
            Navigator.of(context).pop();
          },
          child: const Text('删除'),
        ),
      ],
    ),
  );
}

  void _connectTo(ConnectionInfo connection) {
    // 应该暂时不需要了
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理连接'),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const QuickConnectDialog(),
              ).then((_) => _loadConnections());
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _connections.isEmpty
          ? const Center(
              child: Text('暂无保存的连接'),
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
                          onPressed: () => _connectTo(connection),
                          icon: const Icon(Icons.play_arrow),
                          tooltip: '连接',
                        ),
                        IconButton(
                          onPressed: () => _editConnection(connection),
                          icon: const Icon(Icons.edit),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          onPressed: () => _deleteConnection(connection),
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