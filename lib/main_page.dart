// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'monitor_server_page.dart';
import 'read_key_info_page.dart';
import 'setting_page.dart';
import 'package:flutter/material.dart';
import 'manage_connections_page.dart';
import 'manage_credentials_page.dart';
import 'components/quick_connect_dialog.dart';
import 'models/connection_model.dart';
import 'services/setting_service.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'help_page.dart';
import 'terminal_page.dart';
import 'sftp_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static const platform = MethodChannel('com.samuioto.ConnSSH/native');

  Future<String> getNativeMessage() async {
    try {
      final String result = await platform.invokeMethod('getMessage');
      debugPrint('${result}');
      return result;
    } on PlatformException catch (e) {
      return "调用失败: ${e.message}";
    }
  }
}

class MainPage extends StatefulWidget {
  const MainPage(
      {super.key,
      required void Function() onSettingsChanged,
      required SettingsService settingsService});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<ConnectionInfo> _recentConnections = [];
  bool _isLoading = true;
  final StorageService _storageService = StorageService();
  bool _isConnecting = false;
  ConnectionInfo? _connectingConnection;
  bool _permissionsGranted = false;
  final SettingsService _settingsService = SettingsService();
  bool _isFirstRun = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _checkAndRequestPermissions();
    } else {
      setState(() {
        _permissionsGranted = true;
      });
      _loadRecentConnections();
      _checkFirstRun();
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    final storageStatus = await Permission.storage.status;
    final storageStatusHigh = await Permission.manageExternalStorage.status;

    if (storageStatus.isGranted || storageStatusHigh.isGranted) {
      setState(() {
        _permissionsGranted = true;
      });
      _loadRecentConnections();
      return;
    } else {
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('权限申请'),
            content: const Text('请授予存储权限，用于凭据存储和SFTP文件上传、下载功能'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: const Text('确定授权'),
              ),
            ],
          );
        },
      );

      if (shouldRequest == true) {
        _requestPermissions();
      } else {
        _exitApp();
      }
    });
  }

  Future<void> _requestPermissions() async {
    final storageStatus = await Permission.storage.request();
    final storageStatusHigh = await Permission.manageExternalStorage.request();
    if (storageStatus.isGranted || storageStatusHigh.isGranted) {
      setState(() {
        _permissionsGranted = true;
      });
      _loadRecentConnections();
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('权限未授予'),
          content: const Text('应用需要存储和后台运行权限才能正常工作'),
          actions: [
            TextButton(
              onPressed: _exitApp,
              child: const Text('退出应用'),
            ),
          ],
        );
      },
    );
  }

  void _exitApp() {
    exit(0);
  }

  Future<void> _checkFirstRun() async {
    final settings = await _settingsService.getSettings();
    setState(() {
      _isFirstRun = settings.isFirstRun;
    });

    if (_isFirstRun) {
      _showWelcome();
      _settingsService.markAsNotFirstRun();
    }
  }

  void _showWelcome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('欢迎使用ConnSSH'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('看起来您是第一次使用该应用'),
              const SizedBox(height: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _showHelp,
                  child: const Text(
                    '点击查看帮助',
                    style: TextStyle(
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }

  void _showHelp() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const HelpPage(),
      ),
    );
  }

  Future<void> _loadRecentConnections() async {
    try {
      final recentConnections = await _storageService.getRecentConnections();

      final seen = <String>{};
      final uniqueConnections = recentConnections.where((connection) {
        final String key =
            '${connection.host}:${connection.port}:${connection.credentialId}:${connection.type}';
        if (seen.contains(key)) {
          return false;
        } else {
          seen.add(key);
          return true;
        }
      }).toList();

      setState(() {
        _recentConnections = uniqueConnections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取最近连接失败：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  Future<void> _saveConnection(ConnectionInfo connection) async {
    try {
      // 检查连接是否已存在
      final savedConnections = await _storageService.getConnections();
      final bool connectionExists =
          savedConnections.any((c) => c.id == connection.id);

      if (connectionExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接已存在'),
          ),
        );
        return;
      }

      // 保存连接
      await _storageService.saveConnection(connection);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存连接${connection.name}成功'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存连接失败：$e'),
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
    if (!_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('ConnSSH'),
          //backgroundColor: Colors.transparent,
          //elevation: 0,
          //foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('ConnSSH'),
        //backgroundColor: Colors.transparent,
        //elevation: 0,
        //foregroundColor: Theme.of(context).colorScheme.onSurface,
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
            constraints.maxWidth,
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
    double screenWidth,
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
            // 移除小屏模式下的"连接管理"标题
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buttons[0],
                    const SizedBox(height: 16),
                    if (_recentConnections.isNotEmpty)
                      Column(
                        children: [
                          for (int i = 0;
                              i < _recentConnections.take(4).length;
                              i++)
                            Container(
                              height: 50,
                              margin: EdgeInsets.only(
                                  bottom:
                                      i < _recentConnections.take(4).length - 1
                                          ? 12
                                          : 0),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _buildSmallConnectionTile(
                                  context, _recentConnections[i]),
                            ),
                        ],
                      )
                    else
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey,
                            width: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '无最近连接',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ...buttons.sublist(1),
                  ],
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
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                                  return _buildConnectionTile(
                                      context, connection, showButtonSubtitle);
                                },
                              ),
                            )
                ],
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildSmallConnectionTile(
      BuildContext context, ConnectionInfo connection) {
    final isConnectingThis =
        _isConnecting && _connectingConnection?.id == connection.id;

    return Container(
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _connectTo(connection);
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Icon(
                        connection.isPinned
                            ? Icons.vertical_align_top
                            : _getConnectionIcon(connection.type),
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        connection.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isConnectingThis ? Colors.grey : null,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Colors.grey, size: 20),
                      onSelected: (value) {
                        _handleMenuAction(value, connection);
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'connect',
                          child: Row(
                            children: [
                              Text('连接'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'pin',
                          child: Row(
                            children: [
                              Text(connection.isPinned ? '取消置顶' : '置顶'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'save',
                          child: Row(
                            children: [
                              Text('保存该连接'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Text('删除', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionTile(
      BuildContext context, ConnectionInfo connection, bool isLargeHeight) {
    final isConnectingThis =
        _isConnecting && _connectingConnection?.id == connection.id;

    // 根据屏幕高度动态调整容器高度
    final double containerHeight = isLargeHeight ? 100 : 80;
    // 根据屏幕高度动态调整字体大小
    final double titleFontSize = isLargeHeight ? 16 : 14;
    final double subtitleFontSize = isLargeHeight ? 14 : 12;

    return Container(
      height: containerHeight,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _connectTo(connection);
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isLargeHeight ? 16 : 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 左侧图标
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    connection.isPinned
                        ? Icons.vertical_align_top
                        : _getConnectionIcon(connection.type),
                    color: Colors.grey,
                    size: isLargeHeight ? 24 : 20,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: titleFontSize,
                          color: isConnectingThis ? Colors.grey : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // 副标题
                      if (isLargeHeight) // 只有在高度足够时才显示副标题
                        const SizedBox(height: 4),
                      if (isLargeHeight)
                        Text(
                          '${connection.host}:${connection.port} - ${connection.type.displayName}',
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: isConnectingThis ? Colors.grey : Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // 右侧菜单按钮
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: Colors.grey,
                    size: isLargeHeight ? 24 : 20,
                  ),
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
                          SizedBox(width: 8),
                          Text(connection.isPinned ? '取消置顶' : '置顶'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'save',
                      child: Row(
                        children: [
                          SizedBox(width: 8),
                          Text('保存该连接'),
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
              ],
            ),
          ),
        ),
      ),
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
      case 'save':
        _saveConnection(connection);
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
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
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
      _connectingConnection = connection;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      await _performConnection(connection);
    } catch (e) {
      _handleConnectionError(connection, e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingConnection = null;
        });
      }
    }
  }

  Future<void> _performConnection(ConnectionInfo connection) async {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('正在测试连接...'),
              ],
            ),
          );
        },
      );
    }

    try {
      final storageService = StorageService();
      final sshService = SshService();

      final credentials = await storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      await sshService.connect(connection, credential).timeout(
            const Duration(seconds: 3),
          ); //onTimeout: () {
      //throw TimeoutException('连接超时，请检查网络或主机是否可达');
      //});

      // 添加到最近连接（不等待完成），不然巨卡无比
      unawaited(storageService.addRecentConnection(connection));

      if (mounted) {
        Navigator.of(context).pop();

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
      if (mounted) {
        Navigator.of(context).pop();
      }
      rethrow;
    }
  }

  void _handleConnectionError(ConnectionInfo connection, String error) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接失败'),
        content: Text(error),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
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
    final double buttonHeight = screenHeight >= 500 ? 100 : 80;

    Widget buildButton({
      required VoidCallback onPressed,
      required String title,
      required String subtitle,
    }) {
      final buttonChild = showSubtitle
          ? Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: screenHeight >= 500 ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: screenHeight >= 500 ? 14 : 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: screenHeight >= 500 ? 18 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );

      return SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.all(screenHeight >= 500 ? 14 : 12),
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
        onPressed: _showManagementOptions,
        title: '管理信息',
        subtitle: '管理连接配置、认证凭证',
      ),
      const SizedBox(height: 16),
      buildButton(
        onPressed: _showUtilityTools,
        title: '实用工具',
        subtitle: '服务器数据面板、密钥和证书工具',
      ),
      const SizedBox(height: 16),
      buildButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          );
        },
        title: "设置",
        subtitle: "查看设置、教程和版本信息",
      ),
    ];
  }

  void _showManagementOptions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('管理信息'),
          content: const Text('请选择：'),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ManageConnectionsPage(),
                          ),
                        ).then((_) {
                          _loadRecentConnections();
                        });
                      },
                      label: const Text('保存的连接'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ManageCredentialsPage(),
                          ),
                        );
                      },
                      label: const Text('保存的凭证'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  void _showUtilityTools() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('实用工具'),
          content: const Text('请选择：'),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MonitorServerPage(),
                          ),
                        );
                      },
                      label: const Text('数据面板'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReadKeyInfoPage(),
                          ),
                        );
                      },
                      label: const Text('密钥和证书工具'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }
}
