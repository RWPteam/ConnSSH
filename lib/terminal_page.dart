// TerminalPage.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/ssh_service.dart';

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

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal terminal;
  SSHClient? _sshClient;
  SSHSession? _session;

  bool _isConnected = false;
  bool _isConnecting = true;
  String _status = '连接中...';

  // 用于控制 TerminalView 的焦点
  final FocusNode _terminalFocusNode = FocusNode();

  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;
  
  bool _isSliderVisible = false;
  bool _menuIsOpen = false;
  bool _ismobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  bool _isThemeSelectorVisible = false;
  OverlayEntry? _themeSelectorOverlay;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme; 

  bool get _shouldBeReadOnly {
    // 当菜单或滑块打开时，设为只读以防止误触
    return !_isConnected || _menuIsOpen || _isSliderVisible || _isThemeSelectorVisible;
  }
  
  @override
  void initState() {
    super.initState();
    // 初始化终端
    terminal = Terminal(
      maxLines: 10000,
    );

    // 监听 xterm 的输出流，直接转发给 SSH
    terminal.onOutput = (data) {
      if (_session != null && _isConnected) {
        try {
          // 这里使用 utf8.encode 转换成 Uint8List 发送
          _session!.write(utf8.encode(data));
        } catch (_) {}
      }
    };

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
       _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFontSize();
      _connectToHost();
    });
  }

  void _initFontSize() {
      final screenWidth = MediaQuery.of(context).size.width;
      final isWideScreen = screenWidth >= 800;
      // 保持之前的初始化逻辑
      if (_fontSize == 14.0 && !isWideScreen) {
        _fontSize = 12.0;
      } else if (_fontSize == 10.0 && isWideScreen) {
        _fontSize = 14.0;
      }
  }

  Future<void> _connectToHost() async {
    try {
      if (mounted) {
        setState(() {
          _isConnecting = true;
          _status = '连接中...';
        });
      }
      
      final sshService = SshService();
      _sshClient = await sshService.connect(widget.connection, widget.credential);

      // 获取当前终端的尺寸，如果没有布局完成，给一个默认值
      final width = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      final height = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      _session = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: width,
          height: height,
          type: 'xterm-256color',
        ),
      );

      _stdoutSubscription = _session!.stdout.listen((data) {
        if (!mounted) return;
        try {
          terminal.write(utf8.decode(data));
        } catch (_) {
          // 忽略解码错误
        }
      });

      _stderrSubscription = _session!.stderr.listen((data) {
        if (!mounted) return;
        try {
          terminal.write(utf8.decode(data));
        } catch (_) {
          terminal.write('错误: <stderr 解码失败>');
        }
      });

      _session!.done.then((_) {
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接已断开';
        });
        terminal.write('\r\n连接已断开\r\n');
      });

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = '已连接';
        });
        // 连接成功后请求焦点，弹出键盘
        _terminalFocusNode.requestFocus();
      }
      
      terminal.write('\x1B[2J\x1B[1;1H');
      terminal.buffer.clear();
      terminal.write('连接到 ${widget.connection.host} 成功\r\n');
      
      // 连接建立后稍微延迟一下强制刷新尺寸
      Future.delayed(const Duration(milliseconds: 500), () {
         if(_session != null && terminal.viewWidth > 0) {
             _session!.resizeTerminal(terminal.viewWidth, terminal.viewHeight, 0, 0);
         }
      });

    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接失败: $e';
        });
        terminal.write('连接失败: $e\r\n');
      }
    }
  }

  void _clearTerminal() {
    terminal.buffer.clear();
    terminal.setCursor(0, 0); // 重置光标
    if (_isConnected) {
       // 发送 clear 命令和 VT100 清屏序列
       _session?.write(Uint8List.fromList(utf8.encode('\x1B[2J\x1B[Hclear\r')));
    }
  }

  void _sendCtrlC() => _session?.write(Uint8List.fromList([3])); // ASCII ETX
  void _sendCtrlD() => _session?.write(Uint8List.fromList([4])); // ASCII EOT
  void _sendTab() => _session?.write(Uint8List.fromList([9])); // ASCII HT

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _session?.close();
    _sshClient?.close();
    _terminalFocusNode.dispose();
    _hideSliderTimer?.cancel();
    _hideThemeSelectorTimer?.cancel(); 
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    try { _themeSelectorOverlay?.remove(); } catch (_) {}
    super.dispose();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Colors.green.shade800;
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
      const PopupMenuDivider(),
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
      case 'disconnect':
        Navigator.of(context).pop();
        break;
    }
  }

  void _showThemeSelector() {
    if (_isThemeSelectorVisible) return;
    setState(() => _isThemeSelectorVisible = true);
    FocusScope.of(context).unfocus();
    _hideThemeSelectorTimer?.cancel();

    _themeSelectorOverlay ??= OverlayEntry(builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
             return Stack(
               children: [
                 Positioned.fill(child: GestureDetector(
                   behavior: HitTestBehavior.translucent,
                   onTap: _hideThemeSelector,
                   child: Container(color: Colors.transparent),
                 )),
                 Positioned.fill(
                    child: Center(
                        child: GestureDetector( // 添加 GestureDetector 以阻止内部事件冒泡
                          onTap: () {},
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.grey[900]!.withOpacity(0.9),
                            child: Container(
                              width: MediaQuery.of(context).size.width * 0.7,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('选择主题', style: TextStyle(color: Colors.white, fontSize: 18)),
                                  const SizedBox(height: 16),
                                  _buildThemeOption('默认', TerminalThemes.defaultTheme),
                                  const SizedBox(height: 12),
                                  _buildThemeOption('纯黑', TerminalThemes.whiteOnBlack),
                                ],
                              ),
                            ),
                          ),
                        )
                    )
                 )
               ],
             );
          }
        );
    });
    Overlay.of(context).insert(_themeSelectorOverlay!);
    _resetHideThemeSelectorTimer();
  }

  Widget _buildThemeOption(String title, TerminalTheme theme) {
      final bool isSelected = _currentTheme == theme;
      
      return Material(
        color: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _switchTheme(theme),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  void _switchTheme(TerminalTheme newTheme) {
    setState(() => _currentTheme = newTheme);
    _hideThemeSelector();
  }

  void _hideThemeSelector() {
    setState(() {
      _menuIsOpen = false;
      _isThemeSelectorVisible = false;
    });
    // 恢复焦点到终端
    if (_isConnected) _terminalFocusNode.requestFocus();

    _hideThemeSelectorTimer?.cancel();
    try { _themeSelectorOverlay?.remove(); } catch (_) {}
    _themeSelectorOverlay = null;
  }

  void _resetHideThemeSelectorTimer() {
    _hideThemeSelectorTimer?.cancel();
    _hideThemeSelectorTimer = Timer(const Duration(seconds: 5), _hideThemeSelector);
  }

  void _reconnect() {
    _session?.close();
    _sshClient?.close();
    setState(() {
       _isConnected = false;
       terminal.buffer.clear();
    });
    _connectToHost();
  }

  void _showCommandsSubMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(button.size.topRight(Offset.zero), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
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
        _session?.write(Uint8List.fromList([13])); // Carriage Return (\r)
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
    // 暂时移除焦点
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
                  child: GestureDetector( // 添加 GestureDetector 以阻止内部事件冒泡
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
                                const Text('字体大小', style: TextStyle(color: Colors.white)),
                                Text('${_fontSize.toInt()}', style: const TextStyle(color: Colors.white)),
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
    // 恢复焦点
    if (_isConnected) _terminalFocusNode.requestFocus();
    
    _hideSliderTimer?.cancel();
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    _fontSliderOverlay = null;
  }

  void _resetHideSliderTimer() {
    _hideSliderTimer?.cancel();
    _hideSliderTimer = Timer(const Duration(seconds: 3), _hideFontSlider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _getAppBarColor(),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.connection.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle_outlined,
                  color: _isConnecting ? Colors.grey : Colors.greenAccent,
                  size: 10,
                ),
                const SizedBox(width: 6),
                Text(_status, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (context) => _buildMenuItems(),
            onSelected: _onMenuSelected,
            onOpened: () => setState(() => _menuIsOpen = true),
            onCanceled: () => setState(() => _menuIsOpen = false),
          ),
        ],
      ),
      body: SafeArea(
        child: TerminalView(
          terminal,
          focusNode: _terminalFocusNode,
          autofocus: false,
          backgroundOpacity: 1.0,
          textStyle: TerminalStyle(
            fontSize: _fontSize, 
            fontFamily: 'maple', 
          ),
          theme: _currentTheme,
          showToolbar: _ismobile, 
          alwaysShowCursor: true,
          readOnly: _shouldBeReadOnly, 
        ),
      ),
    );
  }
}