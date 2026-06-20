// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:connssh/pages/transfer/info.dart';
import 'package:connssh/pages/transfer/util.dart';
import 'setting.dart';
import 'package:flutter/material.dart';
import '../components/quick_connect_dialog.dart';
import '../models/connection_model.dart';
import '../services/setting_service.dart';
import '../services/storage_service.dart';
import 'help.dart';
import 'terminal.dart';
import 'sftpview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import '../widgets/app_style.dart';
import '../widgets/app_toast.dart';

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
  const MainPage({
    super.key,
    required void Function() onSettingsChanged,
    required SettingsService settingsService,
  });

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
    _initApp();
  }

  Future<void> _initApp() async {
    if (Platform.isAndroid) {
      await _checkAndRequestPermissions();
    } else {
      setState(() {
        _permissionsGranted = true;
      });
      await _loadRecentConnections();
      await _checkFirstRun();
    }
  }

  Future<void> _checkAndRequestPermissions() async {
    final storageStatus = await Permission.storage.status;
    //final storageStatusHigh = await Permission.manageExternalStorage.status;
    final notificationStatus = await Permission.notification.status;
    final mediaStatus = await Permission.photos.status;
    if (storageStatus.isGranted ||
        mediaStatus.isGranted && notificationStatus.isGranted) {
      setState(() {
        _permissionsGranted = true;
      });
      await _checkFirstRun();
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
            content: const Text('请授予相关权限，用于凭据存储、SFTP文件上传下载和后台运行功能'),
            actions: [
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('取消'),
              ),
              OutlinedButton(
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
    await Permission.storage.request();
    await Permission.photos.request();
    //final storageStatusHigh = await Permission.manageExternalStorage.request();
    await Permission.notification.request();
    //sawait Permission.backgroundRefresh.request();
    final storageStatus = await Permission.storage.status;
    //final storageStatusHigh = await Permission.manageExternalStorage.status;
    final notificationStatus = await Permission.notification.status;
    final mediaStatus = await Permission.photos.status;
    if (storageStatus.isGranted ||
        mediaStatus.isGranted && notificationStatus.isGranted) {
      setState(() {
        _permissionsGranted = true;
      });
      await _checkFirstRun();
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
            OutlinedButton(onPressed: _exitApp, child: const Text('退出应用')),
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
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }

  void _showHelp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const HelpPage()));
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
        AppToast.show(
          context,
          message: '读取最近连接失败：$e',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _deleteRecentConnection(ConnectionInfo connection) async {
    try {
      await _storageService.deleteRecentConnection(connection.id);
      _loadRecentConnections();
    } catch (e) {
      AppToast.show(
        context,
        message: '删除最近连接失败：$e',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _saveConnection(ConnectionInfo connection) async {
    try {
      // 检查连接是否已存在
      final savedConnections = await _storageService.getConnections();
      final bool connectionExists = savedConnections.any(
        (c) => c.id == connection.id,
      );

      if (connectionExists) {
        AppToast.show(
          context,
          message: '连接已存在',
          icon: Icons.info_outline_rounded,
        );
        return;
      }

      // 保存连接
      await _storageService.saveConnection(connection);

      AppToast.show(
        context,
        message: '保存连接${connection.name}成功',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (e) {
      AppToast.show(
        context,
        message: '保存连接失败：$e',
        icon: Icons.error_outline_rounded,
      );
    }
  }

  Future<void> _togglePinConnection(ConnectionInfo connection) async {
    try {
      await _storageService.togglePinConnection(connection.id);
      _loadRecentConnections();
    } catch (e) {
      AppToast.show(
        context,
        message: e.toString(),
        icon: Icons.info_outline_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsGranted) {
      return const AppPageScaffold(
        title: Text('ConnSSH'),
        automaticallyImplyLeading: false,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AppPageScaffold(
      title: const Text('ConnSSH'),
      automaticallyImplyLeading: false,
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
    final buttons = _buildButtons(context, showButtonSubtitle, screenHeight);

    if (!showRecentConnections) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                          for (
                            int i = 0;
                            i < _recentConnections.take(4).length;
                            i++
                          )
                            Container(
                              height: 50,
                              margin: EdgeInsets.only(
                                bottom:
                                    i < _recentConnections.take(4).length - 1
                                    ? 12
                                    : 0,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 0.2,
                                ),
                                borderRadius: AppRadius.largeRadius,
                              ),
                              child: _buildSmallConnectionTile(
                                context,
                                _recentConnections[i],
                              ),
                            ),
                        ],
                      )
                    else
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 0.2),
                          borderRadius: AppRadius.largeRadius,
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Text(
                      '连接管理',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                          child: Center(child: CircularProgressIndicator()),
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
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            child: ListView.builder(
                              primary: false,
                              padding: EdgeInsets.zero,
                              itemCount: _recentConnections.length,
                              itemBuilder: (context, index) {
                                final connection = _recentConnections[index];
                                return _buildConnectionTile(
                                  context,
                                  connection,
                                  showButtonSubtitle,
                                );
                              },
                            ),
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

  Widget _buildSmallConnectionTile(
    BuildContext context,
    ConnectionInfo connection,
  ) {
    final isConnectingThis =
        _isConnecting && _connectingConnection?.id == connection.id;

    return Container(
      height: 50,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.largeRadius,
          onTap: () {
            _connectTo(connection);
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey, width: 1),
              borderRadius: AppRadius.largeRadius,
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        connection.isPinned
                            ? Icons.vertical_align_top
                            : _getConnectionIcon(connection.type),
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
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
                    Builder(
                      builder: (buttonContext) => AppIconActionButton(
                        tooltip: '更多',
                        icon: Icons.more_vert_rounded,
                        iconSize: 20,
                        onPressed: () =>
                            _showConnectionActionMenu(buttonContext, connection),
                      ),
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
    BuildContext context,
    ConnectionInfo connection,
    bool isLargeHeight,
  ) {
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
        border: Border.all(color: Colors.grey, width: 1),
        borderRadius: AppRadius.largeRadius,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.largeRadius,
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
                // 左侧图标 - 已修改为圆形背景样式
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    connection.isPinned
                        ? Icons.vertical_align_top
                        : _getConnectionIcon(connection.type),
                    color: Theme.of(context).colorScheme.primary,
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
                Builder(
                  builder: (buttonContext) => AppIconActionButton(
                    tooltip: '更多',
                    icon: Icons.more_vert_rounded,
                    iconSize: isLargeHeight ? 24 : 20,
                    onPressed: () =>
                        _showConnectionActionMenu(buttonContext, connection),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showConnectionActionMenu(
    BuildContext anchorContext,
    ConnectionInfo connection,
  ) {
    showAppAnchoredActionMenu(
      context,
      anchorContext: anchorContext,
      width: 174,
      entries: [
        AppActionMenuEntry(
          icon: Icons.play_arrow_rounded,
          label: '连接',
          onTap: () => _handleMenuAction('connect', connection),
        ),
        AppActionMenuEntry(
          icon: connection.isPinned
              ? Icons.vertical_align_center_rounded
              : Icons.vertical_align_top_rounded,
          label: connection.isPinned ? '取消置顶' : '置顶',
          onTap: () => _handleMenuAction('pin', connection),
        ),
        AppActionMenuEntry(
          icon: Icons.bookmark_add_outlined,
          label: '保存该连接',
          onTap: () => _handleMenuAction('save', connection),
        ),
        AppActionMenuEntry(
          icon: Icons.delete_outline_rounded,
          label: '删除',
          destructive: true,
          onTap: () => _handleMenuAction('delete', connection),
        ),
      ],
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
            child: const Text('删除', style: TextStyle(color: Colors.red)),
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
              children: [Text('正在测试连接...')],
            ),
          );
        },
      );
    }

    try {
      final storageService = StorageService();

      final credentials = await storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      //await sshService.connect(connection, credential).timeout(
      //      const Duration(seconds: 3),
      //    ); //onTimeout: () {
      //throw TimeoutException('连接超时，请检查网络或主机是否可达');
      //});

      // 添加到最近连接（不等待完成），不然巨卡无比
      unawaited(storageService.addRecentConnection(connection));

      if (mounted) {
        Navigator.of(context).pop();

        if (connection.type == ConnectionType.sftp) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  SftpPage(connection: connection, credential: credential),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  TerminalPage(connection: connection, credential: credential),
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
              borderRadius: AppRadius.largeRadius,
            ),
            alignment: Alignment.centerLeft,
            side: const BorderSide(color: Colors.grey),
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
            MaterialPageRoute(builder: (context) => const ManageInfoPage()),
          ).then((_) {
            _loadRecentConnections();
          });
        },
        title: '管理信息',
        subtitle: '管理连接配置、认证凭证',
      ),
      const SizedBox(height: 16),
      buildButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UtilityToolsPage()),
          );
        },
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
}
