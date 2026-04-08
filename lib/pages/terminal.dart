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
import '../components/twofa_dialog.dart';

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
  bool _ismobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  bool _showToolbar = false;

  bool _isThemeSelectorVisible = false;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme;
  String _selectedThemeName = 'dark';
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

  DateTime? _lastBackPressedTime;

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

    // 立即初始化终端列表
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
      _selectedThemeName = themeName;
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
          _selectedThemeName = 'dark';
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
      _selectedThemeName = 'dark';
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

      // 监听输出
      _stdoutSubs[index] = session.stdout.listen((data) {
        if (!mounted) return;
        try {
          t.write(utf8.decode(data));
        } catch (_) {}
      });

      _stderrSubs[index] = session.stderr.listen((data) {
        if (!mounted) return;
        try {
          t.write(utf8.decode(data));
        } catch (_) {
          t.write('错误: <stderr 解码失败>');
        }
      });

      session.done.then((_) {
        if (!mounted) return;
        setState(() {
          _isConnecteds[index] = false;
          _isConnectings[index] = false;
          _statuses[index] = '连接已断开';
        });
        t.write('\r\n连接已断开\r\n');
      });

      if (mounted) {
        setState(() {
          _isConnecteds[index] = true;
          _isConnectings[index] = false;
          _statuses[index] = '已连接';
        });
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
        _terminals[index].write('连接失败: $e\r\n');
      }
    }
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

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      const PopupMenuItem<String>(value: 'reconnect', child: Text('重新连接')),
      PopupMenuItem<String>(
        value: 'commands',
        child: Row(
          children: const [
            Text('发送命令'),
            SizedBox(width: 8),
            Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
      const PopupMenuItem<String>(value: 'clear', child: Text('清屏')),
      const PopupMenuItem<String>(value: 'fontsize', child: Text('字体大小')),
      const PopupMenuItem<String>(value: 'theme', child: Text('主题')),
      PopupMenuItem<String>(
        value: 'toggle_toolbar',
        child: Text(_showToolbar ? '收起快捷栏' : '展示快捷栏'),
      ),
      const PopupMenuItem<String>(value: 'disconnect', child: Text('断开连接并返回')),
    ];
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'fontsize':
        _showFontSlider();
        break;
      case 'reconnect':
        _reconnect();
        break;
      case 'commands':
        _showCommandsSubMenu();
        break;
      case 'clear':
        _clearTerminal();
        break;
      case 'theme':
        _showThemeSelector();
        break;
      case 'toggle_toolbar':
        _toggleToolbar();
        break;
      case 'disconnect':
        Navigator.of(context).pop();
        break;
    }
  }

  void _toggleToolbar() {
    setState(() {
      _showToolbar = !_showToolbar;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();
  }

  void _showThemeSelector() {
    if (_isThemeSelectorVisible) return;
    setState(() => _isThemeSelectorVisible = true);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('深色'),
              value: 'dark',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.defaultTheme, value);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('高对比度'),
              value: 'black',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.whiteOnBlack, value);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('浅色'),
              value: 'light',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.LightTheme, value);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('XShell'),
              value: 'xshell',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.xshell, value);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Dracula Dark'),
              value: 'dracula',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.dracula, value);
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('Gruvbox Dark'),
              value: 'gruvbox',
              groupValue: _selectedThemeName,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _switchTheme(TerminalThemes.gruvbox, value);
                }
              },
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    ).then((_) {
      _hideThemeSelector();
    });
  }

  void _switchTheme(TerminalTheme newTheme, String themeName) {
    setState(() {
      _currentTheme = newTheme;
      _selectedThemeName = themeName;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();
  }

  void _hideThemeSelector() {
    setState(() {
      _menuIsOpen = false;
      _isThemeSelectorVisible = false;
    });
    if (_isConnected) _terminalFocusNode.requestFocus();

    _hideThemeSelectorTimer?.cancel();
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

  void _showCommandsSubMenu() {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    if (button == null) return;

    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          button.size.topRight(Offset.zero),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(value: 'enter', child: Text('发送 Enter')),
        PopupMenuItem<String>(value: 'tab', child: Text('发送 Tab')),
        PopupMenuItem<String>(value: 'ctrlc', child: Text('发送 Ctrl+C')),
        PopupMenuItem<String>(value: 'ctrld', child: Text('发送 Ctrl+D')),
      ],
    ).then((value) {
      if (value != null) _handleCommand(value);
      setState(() => _menuIsOpen = false);
      if (_isConnected) _terminalFocusNode.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    String displayTitle = _isMultiWindowMode
        ? "${widget.connection.name}-${_activeIndex + 1}"
        : widget.connection.name;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final now = DateTime.now();
        final bool shouldExit =
            _lastBackPressedTime == null ||
            now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

        if (shouldExit) {
          _lastBackPressedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('再按一次退出'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: 40,
          backgroundColor: _getAppBarColor(),
          foregroundColor: Colors.white,
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
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'multi_window') {
                  _isMultiWindowMode
                      ? _disableMultiWindow()
                      : _enableMultiWindow();
                } else {
                  _onMenuSelected(val);
                }
              },
              itemBuilder: (context) => [
                ..._buildMenuItems().where(
                  (item) => (item as PopupMenuItem).value != 'disconnect',
                ),
                PopupMenuItem<String>(
                  value: 'multi_window',
                  child: Text(_isMultiWindowMode ? '关闭多会话' : '多会话（Beta）'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'disconnect',
                  child: Text('断开连接并返回'),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
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
      ),
    );
  }
}
