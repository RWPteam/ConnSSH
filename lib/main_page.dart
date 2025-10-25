import 'package:flutter/material.dart';
import 'manage_connections_page.dart';
import 'manage_credentials_page.dart';
import 'quick_connect_dialog.dart';
import 'models/connection_model.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'terminal_page.dart';


class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<ConnectionInfo> _connections = []; 
  bool _isLoading = true; 
  final StorageService _storageService = StorageService();
  final SshService _sshService = SshService();
  bool _isConnecting = false;


  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    try {
      final connections = await _storageService.getConnections();
      setState(() {
        _connections = connections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取最近连接失败: $e'),
            backgroundColor: Colors.red,
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
          
          final bool showRecentConnections = constraints.maxWidth >= 800 ;
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
                      : _connections.isEmpty
                          ? const Expanded(
                              child: Center(
                                child: Text(
                                  '暂无保存的连接',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    
                                    fontSize: 16,
                                  ),
                                
                                ),
                                
                              ),
                              
                            )
                            
                          : Expanded(
                              child: ListView.builder(
                                itemCount: _connections.length,
                                itemBuilder: (context, index) {
                                  final connection = _connections[index];
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

  ConnectionInfo? _connectingConnection;
  Widget _buildConnectionTile(BuildContext context, ConnectionInfo connection) {
    final isConnectingThis = _isConnecting && _connectingConnection?.id == connection.id;
    return ListTile(
      leading: Icon(
        _getConnectionIcon(connection.type),
        color: isConnectingThis ? Colors.grey : Colors.grey,
      ),
      title: Text(
        connection.name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isConnectingThis ? Colors.grey : null,
        ),
        
      ),

      subtitle: Text(
        '${connection.host}:${connection.port} - ${connection.type.displayName}',
        style: TextStyle(
          color: isConnectingThis ? Colors.grey : Colors.grey,
        ),
      ),
      trailing: Container(
        constraints: const BoxConstraints(
          maxWidth: 40,
        ),
        child: IconButton(
          icon: const Icon(
            Icons.play_arrow,
            color: Colors.grey,
          ),
          iconSize: 20,
          padding: EdgeInsets.zero,
          onPressed: () {
            _connectToServer(connection);
          },
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      onTap: () {
        //_connectToServer(connection);
      },
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

  Future<void> _connectToServer(ConnectionInfo connection) async {
    setState(() {
      _isConnecting = true;
      _connectingConnection = connection;
    });

    try {
      final credentials = await _storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse:() => throw Exception('未找到认证凭证'),
      );
      await _sshService.connect(connection, credential);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder:(context) => TerminalPage(connection: connection, credential: credential)));
      }
    } catch (e) {
      if (mounted) {
        _showConnectionError(connection, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingConnection = null;
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
          TextButton(onPressed: () => Navigator.of(context).pop(),
          child: const Text ('取消'),
          ),
          TextButton(onPressed: (){
            Navigator.of(context).pop();
            _connectToServer(connection);
          },
          child: const Text('重试')),
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
            _loadConnections();
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
            _loadConnections();
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
            applicationVersion: '0.2 Beta',
            children: const [
              SizedBox(height: 8),
              Text(
                '尚在测试中~期待反馈喵',
                style: TextStyle(fontSize: 13,color: Colors.grey),
              )
            ]
          );
        },
        title: '关于',
        subtitle: '查看应用信息和版本详情',
      ),
    ];
  }
}