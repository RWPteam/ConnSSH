import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/ssh_service.dart';
import '../services/setting_service.dart';
import '../services/notification_service.dart';
import '../components/twofa_dialog.dart';
import '../widgets/app_style.dart';
import '../widgets/app_toast.dart';

class TerminalPage extends StatefulWidget {
  final ConnectionInfo connection;
  final Credential credential;

  const TerminalPage({
    super.key,
    required this.connection,
    required this.credential,
  });

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

const int _maxSessions = 2;

class _TerminalPageState extends State<TerminalPage> {
  late List<Terminal> _terminals;
  final List<SSHClient?> _sshClients = List.filled(_maxSessions, null);
  final List<SSHSession?> _sessions = List.filled(_maxSessions, null);
  final List<bool> _isConnecteds = List.filled(_maxSessions, false);
  final List<bool> _isConnectings = List.filled(_maxSessions, false);
  final List<String> _statuses = List.filled(_maxSessions, '未连接');
  final List<StreamSubscription?> _stdoutSubs = List.filled(_maxSessions, null);
  final List<StreamSubscription?> _stderrSubs = List.filled(_maxSessions, null);
  final List<StringBuffer> _terminalOutputBuffers = List.generate(
    _maxSessions,
    (_) => StringBuffer(),
  );
  final List<Timer?> _terminalFlushTimers = List.filled(_maxSessions, null);

  final List<Completer<String?>?> _twoFactorCompleters = List.filled(
    _maxSessions,
    null,
  );
  final List<bool> _needsTwoFactorAuth = List.filled(_maxSessions, false);

  int _activeIndex = 0;
  bool _isMultiWindowMode = false;

  Terminal get terminal => _terminals[_activeIndex];
  SSHSession? get _session => _sessions[_activeIndex];
  bool get _isConnected => _isConnecteds[_activeIndex];
  bool get _isConnecting => _isConnectings[_activeIndex];
  String get _status => _statuses[_activeIndex];

  final FocusNode _terminalFocusNode = FocusNode();

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;

  bool _isSliderVisible = false;
  bool _menuIsOpen = false;
  String _terminalMenuPanel = 'main';
  bool _ismobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  bool _showToolbar = false;

  bool _isThemeSelectorVisible = false;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme;
  String _termType = 'xterm-256color';
  String _defaultfonts = 'maple';
  List<int> _toolbarLayout = const [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
  ];

  final SettingsService _settingsService = SettingsService();
  final NotificationService _notificationService = NotificationService();

  DateTime? _lastBackPressedTime;
  bool _isHandlingBackGesture = false;

  bool get _shouldBeReadOnly {
    return !_isConnected ||
        _menuIsOpen ||
        _isSliderVisible ||
        _isThemeSelectorVisible;
  }

  @override
  void initState() {
    super.initState();
    _showToolbar = _ismobile;

    // 初始化通知服务
    _notificationService.initialize();
    _terminals = List.generate(_maxSessions, (index) {
      final t = Terminal(maxLines: 10000);

      t.onOutput = (data) {
        if (_sessions[index] != null && _isConnecteds[index]) {
          try {
            _sessions[index]!.write(utf8.encode(data));
          } catch (_) {}
        }
      };

      t.onResize = (width, height, pixelWidth, pixelHeight) {
        _sessions[index]?.resizeTerminal(
          width,
          height,
          pixelWidth,
          pixelHeight,
        );
      };

      return t;
    });

    _statuses[0] = '连接中...';
    _isConnectings[0] = true;

    // 异步加载设置
    _loadSettings().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initFontSize();
        _connectToHost(0);
      });
    });
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.getSettings();

      // 设置字体
      _fontSize = settings.defaultFontSize;
      _defaultfonts = settings.defaultFonts;

      // 设置主题
      final themeName = settings.defaultTermTheme;
      switch (themeName) {
        case 'dark':
          _currentTheme = TerminalThemes.defaultTheme;
          break;
        case 'black':
          _currentTheme = TerminalThemes.whiteOnBlack;
          break;
        case 'light':
          _currentTheme = TerminalThemes.LightTheme;
          break;
        case 'xshell':
          _currentTheme = TerminalThemes.xshell;
          break;
        case 'dracula':
          _currentTheme = TerminalThemes.dracula;
          break;
        case 'gruvbox':
          _currentTheme = TerminalThemes.gruvbox;
          break;
        default:
          _currentTheme = TerminalThemes.defaultTheme;
      }

      // 设置终端类型
      _termType = settings.termType;

      // 设置工具栏布局
      _toolbarLayout = settings.toolbarLayout;

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
      // 使用默认值
      _currentTheme = TerminalThemes.defaultTheme;
      _termType = 'xterm-256color';
      _fontSize = 14.0;
      _toolbarLayout = const [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ];
    }
  }

  void _initFontSize() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    if (_fontSize == 14.0 && !isWideScreen) {
      _fontSize = 10.0;
    } else if (_fontSize == 10.0 && isWideScreen) {
      _fontSize = 14.0;
    }
  }

  Future<void> _connectToHost(int index) async {
    try {
      if (!mounted) return;
      setState(() {
        _isConnectings[index] = true;
        _statuses[index] = '连接中...';
      });

      final sshService = SshService();

      final client = await sshService.connect(
        widget.connection,
        widget.credential,
        onTwoFactorAuth: (connectionName, host, prompt) async {
          return await _showTwoFactorAuthDialog(
            index,
            connectionName,
            host,
            prompt,
          );
        },
      );

      _sshClients[index] = client;

      final t = _terminals[index];

      final width = t.viewWidth > 0 ? t.viewWidth : 80;
      final height = t.viewHeight > 0 ? t.viewHeight : 24;

      final session = await client.shell(
        pty: SSHPtyConfig(width: width, height: height, type: _termType),
      );
      _sessions[index] = session;

      // 监听输出。SSH 登录脚本或大段输出可能在短时间内产生大量小块数据，
      // 逐块写入 xterm 会造成明显掉帧，因此先合并到每帧最多刷新一次。
      _stdoutSubs[index] = session.stdout.listen((data) {
        _appendTerminalOutput(index, utf8.decode(data, allowMalformed: true));
      });

      _stderrSubs[index] = session.stderr.listen((data) {
        _appendTerminalOutput(index, utf8.decode(data, allowMalformed: true));
      });

      session.done.then((_) {
        _flushTerminalOutput(index);
        if (!mounted) return;
        setState(() {
          _isConnecteds[index] = false;
          _isConnectings[index] = false;
          _statuses[index] = '连接已断开';
        });
        // 取消通知
        _notificationService.cancelConnectionNotification();
        t.write('\r\n连接已断开\r\n');
      });

      if (mounted) {
        setState(() {
          _isConnecteds[index] = true;
          _isConnectings[index] = false;
          _statuses[index] = '已连接';
        });
        // 显示保持后台活动的通知
        _notificationService.updateConnectionNotification(
          connectionName: widget.connection.name,
          host: widget.connection.host,
          port: widget.connection.port,
          status: '已连接',
        );
        if (_activeIndex == index) _terminalFocusNode.requestFocus();
      }

      t.write('\x1B[2J\x1B[1;1H');
      t.buffer.clear();
      t.write('连接到 ${widget.connection.name}-${index + 1} 成功\r\n');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecteds[index] = false;
          _isConnectings[index] = false;
          _statuses[index] = '连接失败: $e';
        });
        // 取消通知
        _notificationService.cancelConnectionNotification();
        _terminals[index].write('连接失败: $e\r\n');
      }
    }
  }

  void _appendTerminalOutput(int index, String text) {
    if (!mounted || text.isEmpty) return;

    final buffer = _terminalOutputBuffers[index];
    buffer.write(text);

    _terminalFlushTimers[index] ??= Timer(
      const Duration(milliseconds: 16),
      () => _flushTerminalOutput(index),
    );
  }

  void _flushTerminalOutput(int index) {
    _terminalFlushTimers[index]?.cancel();
    _terminalFlushTimers[index] = null;

    if (!mounted) {
      _terminalOutputBuffers[index].clear();
      return;
    }

    final buffer = _terminalOutputBuffers[index];
    if (buffer.isEmpty) return;

    final text = buffer.toString();
    buffer.clear();

    try {
      _terminals[index].write(text);
    } catch (_) {}
  }

  // 显示 2FA 验证码对话框
  Future<String?> _showTwoFactorAuthDialog(
    int sessionIndex,
    String connectionName,
    String host,
    String prompt,
  ) async {
    if (sessionIndex != _activeIndex && _isMultiWindowMode) {
      setState(() {
        _activeIndex = sessionIndex;
      });
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final completer = Completer<String?>();
    _twoFactorCompleters[sessionIndex] = completer;
    setState(() {
      _needsTwoFactorAuth[sessionIndex] = true;
    });

    {
      final code = await TwoFactorAuthDialog.show(
        context,
        connectionName: connectionName,
        host: host,
        prompt: prompt,
      );
      _twoFactorCompleters[sessionIndex] = null;
      setState(() {
        _needsTwoFactorAuth[sessionIndex] = false;
      });
      return code;
    }
  }

  void _enableMultiWindow() {
    setState(() {
      _isMultiWindowMode = true;
      _activeIndex = 1;
      _statuses[1] = '连接中...';
      _isConnectings[1] = true;
    });
    _connectToHost(1);
  }

  Future<void> _disableMultiWindow() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('即将关闭第二个连接，请确认工作已保存'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认关闭', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _stdoutSubs[1]?.cancel();
      _stderrSubs[1]?.cancel();
      _sessions[1]?.close();
      _sshClients[1]?.close();

      setState(() {
        _isMultiWindowMode = false;
        _activeIndex = 0;
        _isConnecteds[1] = false;
        _isConnectings[1] = false;
        _statuses[1] = '未连接';
        _needsTwoFactorAuth[1] = false;
        _twoFactorCompleters[1] = null;
      });
      _terminalFocusNode.requestFocus();
    }
  }

  void _clearTerminal() {
    terminal.buffer.clear();
    terminal.setCursor(0, 0);
    if (_isConnected) {
      _session?.write(Uint8List.fromList(utf8.encode('\x1B[2J\x1B[Hclear\r')));
    }
  }

  void _sendCtrlC() => _session?.write(Uint8List.fromList([3]));
  void _sendCtrlD() => _session?.write(Uint8List.fromList([4]));
  void _sendTab() => _session?.write(Uint8List.fromList([9]));

  @override
  void dispose() {
    for (var i = 0; i < _maxSessions; i++) {
      _terminalFlushTimers[i]?.cancel();
      _terminalOutputBuffers[i].clear();
    }
    for (var sub in _stdoutSubs) {
      sub?.cancel();
    }
    for (var sub in _stderrSubs) {
      sub?.cancel();
    }
    for (var s in _sessions) {
      s?.close();
    }
    for (var c in _sshClients) {
      c?.close();
    }
    // 清理 2FA Completers
    for (var completer in _twoFactorCompleters) {
      if (completer != null && !completer.isCompleted) {
        completer.complete(null);
      }
    }
    // 退出时取消通知
    _notificationService.cancelConnectionNotification();
    _terminalFocusNode.dispose();
    _hideSliderTimer?.cancel();
    _hideThemeSelectorTimer?.cancel();
    try {
      _fontSliderOverlay?.remove();
    } catch (_) {}
    super.dispose();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Theme.of(context).primaryColor;
    if (_needsTwoFactorAuth[_activeIndex]) return Colors.orange;
    return Colors.red;
  }

  Future<void> _showTerminalActionSheet() async {
    setState(() {
      _menuIsOpen = !_menuIsOpen;
      _terminalMenuPanel = 'main';
    });
    if (!_menuIsOpen && _isConnected) {
      _terminalFocusNode.requestFocus();
    }
  }

  void _closeTerminalMenu({bool requestFocus = true}) {
    if (!mounted) return;
    setState(() {
      _menuIsOpen = false;
      _terminalMenuPanel = 'main';
      _isThemeSelectorVisible = false;
    });
    if (requestFocus && _isConnected) {
      _terminalFocusNode.requestFocus();
    }
  }

  void _showTerminalMenuPanel(String panel) {
    setState(() {
      _menuIsOpen = true;
      _terminalMenuPanel = panel;
    });
  }

  void _toggleToolbar() {
    setState(() {
      _showToolbar = !_showToolbar;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();
  }

  void _selectTerminalTheme(String value) {
    switch (value) {
      case 'dark':
        _switchTheme(TerminalThemes.defaultTheme, 'dark');
        break;
      case 'light':
        _switchTheme(TerminalThemes.LightTheme, 'light');
        break;
      case 'xshell':
        _switchTheme(TerminalThemes.xshell, 'xshell');
        break;
      case 'dracula':
        _switchTheme(TerminalThemes.dracula, 'dracula');
        break;
      case 'gruvbox':
        _switchTheme(TerminalThemes.gruvbox, 'gruvbox');
        break;
    }
    _closeTerminalMenu();
  }

  void _switchTheme(TerminalTheme newTheme, String themeName) {
    setState(() {
      _currentTheme = newTheme;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();
  }

  void _reconnect() {
    _sessions[_activeIndex]?.close();
    _sshClients[_activeIndex]?.close();

    _stdoutSubs[_activeIndex]?.cancel();
    _stderrSubs[_activeIndex]?.cancel();

    if (_twoFactorCompleters[_activeIndex] != null &&
        !_twoFactorCompleters[_activeIndex]!.isCompleted) {
      _twoFactorCompleters[_activeIndex]!.complete(null);
    }

    final t = _terminals[_activeIndex];

    t.buffer.clear();

    t.write('\x1B[2J\x1B[3J\x1B[H');

    t.setCursor(0, 0);

    setState(() {
      _isConnecteds[_activeIndex] = false;
      _isConnectings[_activeIndex] = true;
      _statuses[_activeIndex] = '重新连接中...';
      _needsTwoFactorAuth[_activeIndex] = false;
      _twoFactorCompleters[_activeIndex] = null;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        t.write('\r\n正在重新连接...\r\n');
        _connectToHost(_activeIndex);
      }
    });
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _session?.write(Uint8List.fromList([13]));
        break;
      case 'tab':
        _sendTab();
        break;
      case 'ctrlc':
        _sendCtrlC();
        break;
      case 'ctrld':
        _sendCtrlD();
        break;
    }
  }

  void _showFontSlider() {
    if (_isSliderVisible) return;
    setState(() => _isSliderVisible = true);
    FocusScope.of(context).unfocus();
    _hideSliderTimer?.cancel();

    _fontSliderOverlay ??= OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hideFontSlider,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  bottom: 50,
                  left: 20,
                  right: 20,
                  child: GestureDetector(
                    onTap: () {},
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey[900]!.withOpacity(0.9),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '字体大小',
                                  style: TextStyle(color: Colors.white),
                                ),
                                Text(
                                  '${_fontSize.toInt()}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            Slider(
                              value: _fontSize,
                              min: 8,
                              max: 24,
                              divisions: 16,
                              onChanged: (v) {
                                setStateOverlay(() => _fontSize = v);
                                if (mounted) setState(() => _fontSize = v);
                                _resetHideSliderTimer();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_fontSliderOverlay!);
    _resetHideSliderTimer();
  }

  void _hideFontSlider() {
    setState(() {
      _menuIsOpen = false;
      _isSliderVisible = false;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();

    _hideSliderTimer?.cancel();
    try {
      _fontSliderOverlay?.remove();
    } catch (_) {}
    _fontSliderOverlay = null;
  }

  void _resetHideSliderTimer() {
    _hideSliderTimer?.cancel();
    _hideSliderTimer = Timer(const Duration(seconds: 3), _hideFontSlider);
  }

  Widget _buildTerminalFloatingMenu() {
    List<AppActionMenuEntry> entries;
    double width = 160;

    if (_terminalMenuPanel == 'commands') {
      width = 152;
      entries = [
        AppActionMenuEntry(
          icon: Icons.arrow_back_rounded,
          label: '返回',
          onTap: () => _showTerminalMenuPanel('main'),
        ),
        AppActionMenuEntry(
          icon: Icons.keyboard_return_rounded,
          label: '发送 Enter',
          onTap: () {
            _handleCommand('enter');
            _closeTerminalMenu();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.keyboard_tab_rounded,
          label: '发送 Tab',
          onTap: () {
            _handleCommand('tab');
            _closeTerminalMenu();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.copy_rounded,
          label: '发送 Ctrl+C',
          onTap: () {
            _handleCommand('ctrlc');
            _closeTerminalMenu();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.logout_rounded,
          label: '发送 Ctrl+D',
          onTap: () {
            _handleCommand('ctrld');
            _closeTerminalMenu();
          },
        ),
      ];
    } else if (_terminalMenuPanel == 'theme') {
      width = 158;
      entries = [
        AppActionMenuEntry(
          icon: Icons.arrow_back_rounded,
          label: '返回',
          onTap: () => _showTerminalMenuPanel('main'),
        ),
        AppActionMenuEntry(
          icon: Icons.dark_mode_rounded,
          label: '深色',
          onTap: () => _selectTerminalTheme('dark'),
        ),
        AppActionMenuEntry(
          icon: Icons.light_mode_rounded,
          label: '浅色',
          onTap: () => _selectTerminalTheme('light'),
        ),
        AppActionMenuEntry(
          icon: Icons.terminal_rounded,
          label: 'XShell',
          onTap: () => _selectTerminalTheme('xshell'),
        ),
        AppActionMenuEntry(
          icon: Icons.palette_outlined,
          label: 'Dracula',
          onTap: () => _selectTerminalTheme('dracula'),
        ),
        AppActionMenuEntry(
          icon: Icons.palette_rounded,
          label: 'Gruvbox',
          onTap: () => _selectTerminalTheme('gruvbox'),
        ),
      ];
    } else {
      entries = [
        AppActionMenuEntry(
          icon: Icons.refresh_rounded,
          label: '重新连接',
          onTap: () {
            _closeTerminalMenu(requestFocus: false);
            _reconnect();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.keyboard_command_key_rounded,
          label: '发送命令',
          onTap: () => _showTerminalMenuPanel('commands'),
        ),
        AppActionMenuEntry(
          icon: Icons.cleaning_services_outlined,
          label: '清屏',
          onTap: () {
            _clearTerminal();
            _closeTerminalMenu();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.format_size_rounded,
          label: '字体大小',
          onTap: () {
            _closeTerminalMenu(requestFocus: false);
            _showFontSlider();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.palette_outlined,
          label: '主题',
          onTap: () => _showTerminalMenuPanel('theme'),
        ),
        AppActionMenuEntry(
          icon: Icons.tune_rounded,
          label: _showToolbar ? '收起快捷栏' : '展示快捷栏',
          onTap: () {
            _closeTerminalMenu(requestFocus: false);
            _toggleToolbar();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.splitscreen_rounded,
          label: _isMultiWindowMode ? '关闭多会话' : '多会话',
          onTap: () {
            _closeTerminalMenu(requestFocus: false);
            _isMultiWindowMode ? _disableMultiWindow() : _enableMultiWindow();
          },
        ),
        AppActionMenuEntry(
          icon: Icons.logout_rounded,
          label: '断开连接并返回',
          destructive: true,
          onTap: () {
            _closeTerminalMenu(requestFocus: false);
            Navigator.of(context).pop();
          },
        ),
      ];
    }

    return Positioned(
      right: 10,
      top: 8,
      child: AppAnimatedActionMenu(
        visible: _menuIsOpen,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: AppActionMenu(
            key: ValueKey(_terminalMenuPanel),
            width: width,
            entries: entries,
          ),
        ),
      ),
    );
  }

  Future<void> _handleBackNavigationAttempt() async {
    final now = DateTime.now();

    final bool shouldExit =
        _lastBackPressedTime == null ||
        now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

    if (shouldExit) {
      _lastBackPressedTime = now;
      AppToast.show(
        context,
        message: '再按一次退出',
        icon: Icons.info_outline_rounded,
        duration: const Duration(seconds: 2),
      );
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _buildIOSBackGestureWrapper({required Widget child}) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return child;
    }

    double dragStartX = 0;
    double dragDistance = 0;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 32,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              dragStartX = details.globalPosition.dx;
              dragDistance = 0;
            },
            onHorizontalDragUpdate: (details) {
              if (dragStartX > 32) return;

              final delta = details.primaryDelta ?? 0;
              if (delta > 0) {
                dragDistance += delta;
              }
            },
            onHorizontalDragEnd: (details) async {
              if (_isHandlingBackGesture) return;

              final velocity = details.primaryVelocity ?? 0;
              final shouldTriggerBack =
                  dragStartX <= 32 && (dragDistance > 70 || velocity > 450);

              if (!shouldTriggerBack) return;

              _isHandlingBackGesture = true;

              try {
                await _handleBackNavigationAttempt();
              } finally {
                if (mounted) {
                  _isHandlingBackGesture = false;
                }
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayTitle = _isMultiWindowMode
        ? "${widget.connection.name}-${_activeIndex + 1}"
        : widget.connection.name;
    final Color appBarColor = _getAppBarColor();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleBackNavigationAttempt();
      },
      child: _buildIOSBackGestureWrapper(
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            toolbarHeight: 40,
            backgroundColor: appBarColor,
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            leading: _ismobile
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    padding: const EdgeInsets.all(8),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
            title: Container(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(left: _ismobile ? 18.0 : 0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _isConnected ? Icons.circle : Icons.circle_outlined,
                          color: Colors.white,
                          size: 8,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _status,
                          style: TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                        if (_needsTwoFactorAuth[_activeIndex])
                          Padding(padding: const EdgeInsets.only(left: 8.0)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (_isMultiWindowMode)
                IconButton(
                  icon: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: _activeIndex == 0
                                    ? Colors.white
                                    : Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: _activeIndex == 1
                                    ? Colors.white
                                    : Colors.white54,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  iconSize: 24,
                  padding: const EdgeInsets.all(8),
                  onPressed: () {
                    setState(() => _activeIndex = _activeIndex == 0 ? 1 : 0);
                    _terminalFocusNode.requestFocus();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: '菜单',
                padding: const EdgeInsets.all(8),
                onPressed: _showTerminalActionSheet,
              ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                RepaintBoundary(
                  child: TerminalView(
                    terminal,
                    key: ValueKey(_activeIndex),
                    focusNode: _terminalFocusNode,
                    autofocus: true,
                    textStyle: TerminalStyle(
                      fontSize: _fontSize,
                      fontFamily: _defaultfonts,
                    ),
                    theme: _currentTheme,
                    showToolbar: _showToolbar,
                    toolbarLayout: _toolbarLayout,
                    readOnly: _shouldBeReadOnly,
                  ),
                ),
                _buildTerminalFloatingMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
