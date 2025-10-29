import 'package:flutter/material.dart';
import 'manage_connections_page.dart';
import 'manage_credentials_page.dart';
import 'quick_connect_dialog.dart';
import 'models/connection_model.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'terminal_page.dart';
import 'sftp_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<ConnectionInfo> _recentConnections = [];
  bool _isLoading = true; 
  final StorageService _storageService = StorageService();
  bool _isConnecting = false;
  ConnectionInfo? _connectingConnection;

  @override
  void initState() {
    super.initState();
    _loadRecentConnections();
  }

  Future<void> _loadRecentConnections() async {
    try {
      final recentConnections = await _storageService.getRecentConnections();
      setState(() {
        _recentConnections = recentConnections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('读取最近连接失败：$e'),
          backgroundColor: Colors.red 
        ),
      );
    }
  }

  Future<void> _addToRecentConnections(ConnectionInfo connection) async {
    try {
      await _storageService.addRecentConnection(connection);
      _loadRecentConnections();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存到最近连接失败：$e'),
          backgroundColor: Colors.red
        ),
      );
    }
  }

  Future<void> _deleteRecentConnection(ConnectionInfo connection) async {
    try {
      await _storageService.deleteRecentConnection(connection.id);
      _loadRecentConnections();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除最近连接失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _togglePinConnection(ConnectionInfo connection) async {
    try {
      await _storageService.togglePinConnection(connection.id);
      _loadRecentConnections();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connecter'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool showRecentConnections = constraints.maxWidth >= 800;
          final bool showButtonSubtitle = constraints.maxHeight >= 500;
          
          return _buildContent(
            context,
            showRecentConnections,
            showButtonSubtitle,
            constraints.maxHeight,
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool showRecentConnections,
    bool showButtonSubtitle,
    double screenHeight,
  ) {
    final buttons = _buildButtons(
      context, 
      showButtonSubtitle, 
      screenHeight,
    );
    
    if (!showRecentConnections) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Text(
                '连接管理',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: buttons,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Text(
                      '连接管理',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: buttons,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '最近连接',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  _isLoading 
                      ? const Expanded(
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _recentConnections.isEmpty
                          ? const Expanded(
                              child: Center(
                                child: Text(
                                  '无最近连接',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            )
                          : Expanded(
                              child: ListView.builder(
                                itemCount: _recentConnections.length,
                                itemBuilder: (context, index) {
                                  final connection = _recentConnections[index];
                                  return Container(
                                    height: 80, 
                                    margin: const EdgeInsets.only(bottom: 16), 
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: _buildConnectionTile(context, connection),
                                  );
                                },
                              ),
                            ),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildConnectionTile(BuildContext context, ConnectionInfo connection) {
    final isConnectingThis = _isConnecting && _connectingConnection?.id == connection.id;
    
    return ListTile(
      leading: Stack(
        children: [
          Icon(
            connection.isPinned ? Icons.vertical_align_top : _getConnectionIcon(connection.type),
            color: Colors.grey,
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              connection.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isConnectingThis ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${connection.host}:${connection.port} - ${connection.type.displayName}',
        style: TextStyle(
          color: isConnectingThis ? Colors.grey : Colors.grey,
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.grey),
        onSelected: (value) {
          _handleMenuAction(value, connection);
        },
        itemBuilder: (BuildContext context) => [
          const PopupMenuItem<String>(
            value: 'connect',
            child: Row(
              children: [
                SizedBox(width: 8),
                Text('连接'),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'pin',
          child: Row(
          children: [
            const SizedBox(width: 8),
            Text(connection.isPinned ? '取消置顶' : '置顶'),
            ],
          ),
        ),
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                SizedBox(width: 8),
                Text('删除', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      onTap: () {
        _connectTo(connection);
      },
    );
  }

  void _handleMenuAction(String action, ConnectionInfo connection) {
    switch (action) {
      case 'connect':
        _connectTo(connection);
        break;
      case 'pin':
        _togglePinConnection(connection);
        break;
      case 'delete':
        _showDeleteDialog(connection);
        break;
    }
  }

  void _showDeleteDialog(ConnectionInfo connection) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定要从最近连接中删除 "${connection.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteRecentConnection(connection);
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getConnectionIcon(ConnectionType type) {
    switch (type) {
      case ConnectionType.ssh:
        return Icons.terminal;
      case ConnectionType.sftp:
        return Icons.folder;
    }
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
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在连接...'),
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

      await sshService.connect(connection, credential);
      await storageService.addRecentConnection(connection);

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

    } catch (e) {
      // 关闭加载对话框
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
              TextButton(
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

  void _showConnectionError(ConnectionInfo connection, String error) {
    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text('连接失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('连接到 ${connection.name}时发生错误：'),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: Colors.red),
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _connectTo(connection);
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildButtons(
    BuildContext context, 
    bool showSubtitle, 
    double screenHeight,
  ) {
    const double buttonHeight = 80;
    
    Widget buildButton({
      required VoidCallback onPressed,
      required String title,
      required String subtitle,
    }) {
      final buttonChild = showSubtitle 
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            )
          : Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            );
      
      return SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerLeft,
            side: const BorderSide(
              color: Colors.grey,
            ),
          ),
          child: buttonChild,
        ),
      );
    }
    
    return [
      buildButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const QuickConnectDialog(),
          ).then((_) {
            _loadRecentConnections();
          });
        },
        title: '快速连接',
        subtitle: '输入地址和凭证快速建立连接',
      ),
      const SizedBox(height: 16),
      
      buildButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManageConnectionsPage(),
            ),
          ).then((_) {
            _loadRecentConnections();
          });
        },
        title: '管理已保存的连接',
        subtitle: '查看和编辑所有保存的连接配置',
      ),
      const SizedBox(height: 16),
      
      buildButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManageCredentialsPage(),
            ),
          );
        },

        title: '管理认证凭证',
        subtitle: '管理密码和证书凭证',
      ),
      const SizedBox(height: 16),
      
      buildButton(
        onPressed: () {
          showAboutDialog(
            context: context,
            applicationName: 'connecter',
            applicationVersion: '0.3 Beta',
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              ),
              Padding(
                padding: EdgeInsets.only(left: 20, bottom: 20,right: 20),
                child: Text(
                  '尚在测试中~期待反馈喵 本次更新了SFTP功能，由于改动较大可能存在问题，请勿在生产环境中使用',
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
              )
            ],
          );
        },
        title: '关于',
        subtitle: '查看应用信息和版本详情',
      ),
    ];
  }
}