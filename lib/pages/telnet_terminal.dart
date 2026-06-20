import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import '../models/telnet_connection_model.dart';
import '../services/telnet_service.dart';
import '../services/setting_service.dart';
import '../widgets/app_style.dart';
import '../widgets/app_toast.dart';

class TelnetTerminalPage extends StatefulWidget {
  final TelnetConnectionInfo connection;

  const TelnetTerminalPage({super.key, required this.connection});

  @override
  State<TelnetTerminalPage> createState() => _TelnetTerminalPageState();
}

class _TelnetTerminalPageState extends State<TelnetTerminalPage> {
  late Terminal _terminal;
  TelnetService? _telnetService;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = '未连接';
  bool _isClosing = false;

  // 焦点控制
  final FocusNode _terminalFocusNode = FocusNode();

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;
  bool _isSliderVisible = false;
  bool _menuIsOpen = false;

  bool _isThemeSelectorVisible = false;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme;
  String _selectedThemeName = 'dark';
  String _defaultFonts = 'maple';

  // 设置服务
  final SettingsService _settingsService = SettingsService();

  // 快捷栏控制
  bool _showToolbar = false;
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

  // 返回按钮处理
  DateTime? _lastBackPressedTime;

  // 是否为移动端
  bool _ismobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.ohos ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // 是否只读
  bool get _shouldBeReadOnly {
    return !_isConnected ||
        _menuIsOpen ||
        _isSliderVisible ||
        _isThemeSelectorVisible;
  }

  // 行分隔符映射
  String get _lineSeparatorValue {
    switch (widget.connection.lineSeparator) {
      case TelnetLineSeparator.cr:
        return '\r';
      case TelnetLineSeparator.lf:
        return '\n';
      case TelnetLineSeparator.crlf:
        return '\r\n';
    }
  }

  void _setupKeyboardListeners() {
    // 监听键盘事件
    // ignore: deprecated_member_use
    RawKeyboard.instance.addListener((event) {
      if (!_isConnected) return;

      // ignore: deprecated_member_use
      if (event is RawKeyDownEvent) {
        final logicalKey = event.logicalKey;

        // 处理回车键
        if (logicalKey == LogicalKeyboardKey.enter) {
          debugPrint('检测到物理回车键，发送换行符');
          _telnetService!.send(_lineSeparatorValue);
          return;
        }

        // 处理其他特殊按键
        // ignore: deprecated_member_use
        if (event.isControlPressed) {
          switch (logicalKey) {
            case LogicalKeyboardKey.keyC:
              _sendCtrlC();
              break;
            case LogicalKeyboardKey.keyD:
              _sendCtrlD();
              break;
            // 添加其他控制键处理
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // 初始化快捷栏显示状态，默认与设备类型一致
    _showToolbar = _ismobile;

    _setupKeyboardListeners();

    _terminal = Terminal(maxLines: 10000);

    // 设置终端回调
    _terminal.onOutput = (data) {
      if (_isConnected && _telnetService != null) {
        try {
          // 处理特殊控制字符
          String processedData = data;
          processedData = _processControlCharacters(processedData);

          _telnetService!.send(processedData);
        } catch (e) {
          debugPrint('发送数据失败: $e');
        }
      }
    };

    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      debugPrint('终端大小调整为: ${width}x$height');
    };

    // 异步加载设置并连接
    _loadSettings().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initFontSize();
        _connectToHost();
      });
    });
  }

  // 处理控制字符
  String _processControlCharacters(String data) {
    return data;
  }

  // 加载设置
  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsService.getSettings();

      // 设置字体大小
      _fontSize = settings.defaultFontSize;
      _defaultFonts = settings.defaultFonts;

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

      _toolbarLayout = settings.toolbarLayout;

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
      _currentTheme = TerminalThemes.defaultTheme;
      _selectedThemeName = 'dark';
      _fontSize = 14.0;
      _defaultFonts = 'maple';
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

  Future<void> _connectToHost() async {
    if (_isConnecting || _isConnected) return;

    try {
      if (!mounted) return;

      setState(() {
        _isConnecting = true;
        _status = '连接中...';
      });

      _terminal.write(
        '正在连接到 ${widget.connection.host}:${widget.connection.port}...\r\n',
      );

      // 先断开旧的连接
      _telnetService?.disconnect();
      _telnetService = null;

      _telnetService = TelnetService(
        onConnected: () {
          if (mounted) {
            setState(() {
              _isConnected = true;
              _isConnecting = false;
              _status = '已连接';
              _isClosing = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _terminalFocusNode.requestFocus();
            });
          }
        },
        onDisconnected: () {
          if (_isClosing) return;

          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
              _status = '连接已断开';
            });
          }

          _terminal.write('\r\n\r\n连接已断开\r\n');
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
              _status = '连接错误';
            });
          }

          _terminal.write('\r\n连接错误: $error\r\n');
        },
        onDataReceived: (data) {
          if (!mounted) return;
          try {
            // 直接写入接收到的数据
            _terminal.write(data);
          } catch (e) {
            debugPrint('写入终端数据失败: $e');
          }
        },
      );

      await _telnetService!.connect(widget.connection);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接失败';
        });
      }

      _terminal.write('连接失败: $e\r\n');
    }
  }

  Future<void> _reconnect() async {
    if (_isConnecting) return;

    debugPrint('开始重新连接...');

    // 清理旧连接
    _telnetService?.disconnect();
    _telnetService = null;

    // 清空终端
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);

    // 重置状态
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _status = '重新连接中...';
        _isClosing = false;
      });
    }

    // 短暂延迟后重新连接
    await Future.delayed(const Duration(milliseconds: 100));

    // 开始连接
    await _connectToHost();
  }

  Future<void> _disconnect() async {
    if (_isClosing) return;

    _isClosing = true;

    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _status = '断开连接中...';
      });
    }

    _telnetService?.disconnect();
    _telnetService = null;

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _clearTerminal() {
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);

    if (_isConnected) {
      _terminal.write('\x1B[2J\x1B[H'); // VT100清屏序列
    }
  }

  void _sendTelnetCommand(List<int> bytes) {
    if (_isConnected && _telnetService != null) {
      _telnetService!.sendBytes(bytes);
    }
  }

  void _sendCtrlC() => _sendTelnetCommand([0x03]); // ETX
  void _sendCtrlD() => _sendTelnetCommand([0x04]); // EOT
  void _sendTab() => _sendTelnetCommand([0x09]); // HT
  void _sendEnter() => _sendTelnetCommand([0x0D]); // CR
  void _sendBackspace() => _sendTelnetCommand([0x08]); // BS - 退格键

  // Telnet特殊命令
  void _sendTelnetInterrupt() => _sendTelnetCommand([0xFF, 0xF4]); // IAC IP
  void _sendTelnetAbort() => _sendTelnetCommand([0xFF, 0xF6]); // IAC AO
  void _sendTelnetEraseLine() => _sendTelnetCommand([0xFF, 0xF8]); // IAC EL
  void _sendTelnetEraseCharacter() =>
      _sendTelnetCommand([0xFF, 0xF7]); // IAC EC

  // 字体大小控制
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
    if (_isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _terminalFocusNode.requestFocus();
      });
    }
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

  // 主题选择
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
              title: const Text('纯黑'),
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

  Future<void> _switchTheme(TerminalTheme newTheme, String themeName) async {
    try {
      setState(() {
        _currentTheme = newTheme;
        _selectedThemeName = themeName;
      });

      final settings = await _settingsService.getSettings();
      final updatedSettings = settings.copyWith(defaultTermTheme: themeName);
      await _settingsService.saveSettings(updatedSettings);

      if (_isConnected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _terminalFocusNode.requestFocus();
        });
      }
    } catch (e) {
      debugPrint('切换主题失败: $e');
      if (mounted) {
        AppToast.show(
          context,
          message: '切换主题失败: $e',
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  void _hideThemeSelector() {
    setState(() {
      _menuIsOpen = false;
      _isThemeSelectorVisible = false;
    });
    if (_isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _terminalFocusNode.requestFocus();
      });
    }
    _hideThemeSelectorTimer?.cancel();
  }

  // 快捷栏切换
  void _toggleToolbar() {
    setState(() {
      _showToolbar = !_showToolbar;
    });
    // 切换后恢复焦点到终端
    if (_isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _terminalFocusNode.requestFocus();
      });
    }
  }

  // 菜单项
  List<AppActionSheetItem<String>> _buildMenuActionItems() {
    return [
      const AppActionSheetItem<String>(
        value: 'reconnect',
        label: '重新连接',
        icon: Icons.refresh_rounded,
      ),
      const AppActionSheetItem<String>(
        value: 'commands',
        label: '发送命令',
        icon: Icons.keyboard_command_key_rounded,
      ),
      const AppActionSheetItem<String>(
        value: 'clear',
        label: '清屏',
        icon: Icons.cleaning_services_rounded,
      ),
      const AppActionSheetItem<String>(
        value: 'fontsize',
        label: '字体大小',
        icon: Icons.format_size_rounded,
      ),
      const AppActionSheetItem<String>(
        value: 'theme',
        label: '主题',
        icon: Icons.palette_rounded,
      ),
      AppActionSheetItem<String>(
        value: 'toggle_toolbar',
        label: _showToolbar ? '收起快捷栏' : '展示快捷栏',
        icon: _showToolbar
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
      ),
      const AppActionSheetItem<String>(
        value: 'disconnect',
        label: '断开连接并返回',
        icon: Icons.logout_rounded,
        destructive: true,
      ),
    ];
  }

  Future<void> _showTerminalActionSheet() async {
    setState(() => _menuIsOpen = true);
    final value = await showAppActionSheet<String>(
      context,
      title: widget.connection.name,
      items: _buildMenuActionItems(),
    );
    if (!mounted) return;
    setState(() => _menuIsOpen = false);
    if (value != null) _onMenuSelected(value);
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
      case 'toggle_toolbar': // 添加快捷栏切换处理
        _toggleToolbar();
        break;
      case 'disconnect':
        _disconnect();
        break;
    }
  }

  Future<void> _showCommandsSubMenu() async {
    final value = await showAppActionSheet<String>(
      context,
      title: '发送命令',
      items: const [
        AppActionSheetItem<String>(
          value: 'enter',
          label: '发送 Enter',
          icon: Icons.subdirectory_arrow_left_rounded,
        ),
        AppActionSheetItem<String>(
          value: 'tab',
          label: '发送 Tab',
          icon: Icons.keyboard_tab_rounded,
        ),
        AppActionSheetItem<String>(
          value: 'ctrlc',
          label: '发送 Ctrl+C',
          icon: Icons.cancel_rounded,
        ),
        AppActionSheetItem<String>(
          value: 'ctrld',
          label: '发送 Ctrl+D',
          icon: Icons.exit_to_app_rounded,
        ),
        AppActionSheetItem<String>(
          value: 'backspace',
          label: '发送 Backspace',
          icon: Icons.backspace_outlined,
        ),
        AppActionSheetItem<String>(
          value: 'telnet_ip',
          label: 'Telnet中断进程',
          icon: Icons.stop_circle_outlined,
        ),
        AppActionSheetItem<String>(
          value: 'telnet_ao',
          label: 'Telnet中止输出',
          icon: Icons.block_rounded,
        ),
        AppActionSheetItem<String>(
          value: 'telnet_el',
          label: 'Telnet擦除行',
          icon: Icons.cleaning_services_outlined,
        ),
        AppActionSheetItem<String>(
          value: 'telnet_ec',
          label: 'Telnet擦除字符',
          icon: Icons.backspace_rounded,
        ),
      ],
    );
    if (!mounted) return;
    if (value != null) _handleCommand(value);
    setState(() => _menuIsOpen = false);
    if (_isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _terminalFocusNode.requestFocus();
      });
    }
  }


  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _sendEnter();
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
      case 'backspace':
        _sendBackspace();
        break;
      case 'telnet_ip':
        _sendTelnetInterrupt();
        break;
      case 'telnet_ao':
        _sendTelnetAbort();
        break;
      case 'telnet_el':
        _sendTelnetEraseLine();
        break;
      case 'telnet_ec':
        _sendTelnetEraseCharacter();
        break;
    }
  }

  @override
  void dispose() {
    _isClosing = true;
    _telnetService?.disconnect();
    _telnetService = null;
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
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
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
          AppToast.show(
            context,
            message: '再按一次退出',
            icon: Icons.info_outline_rounded,
            duration: const Duration(seconds: 2),
          );
        } else {
          _disconnect();
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
                  onPressed: _disconnect,
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
                    widget.connection.name,
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
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: '更多',
              onPressed: _showTerminalActionSheet,
            ),
          ],
        ),
        body: SafeArea(
          child: TerminalView(
            _terminal,
            focusNode: _terminalFocusNode,
            autofocus: true,
            textStyle: TerminalStyle(
              fontSize: _fontSize,
              fontFamily: _defaultFonts,
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
