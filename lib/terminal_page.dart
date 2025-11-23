// TerminalPage.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _TerminalPageState extends State<TerminalPage> implements TextInputClient {
  late final Terminal terminal;
  SSHClient? _sshClient;
  SSHSession? _session;

  bool _isConnected = false;
  bool _isConnecting = true;
  String _status = '连接中...';

  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode();
  TextInputConnection? _textInputConnection;
  TextEditingValue _currentEditingValue = TextEditingValue.empty;

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;
  
  final StringBuffer _writeBuffer = StringBuffer();
  Timer? _flushTimer;
  final Duration _flushInterval = const Duration(milliseconds: 20);

  DateTime? _lastSendAt;
  String? _lastSentChunk;

  bool _isSliderVisible = false;
  bool _menuIsOpen = false;
  bool _ismobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.ohos || defaultTargetPlatform == TargetPlatform.iOS ? true : false;

  bool _isThemeSelectorVisible = false;
  OverlayEntry? _themeSelectorOverlay;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme; 

  bool _connectionEstablished = false;
  bool _focusRequested = false;

  bool get _shouldBeReadOnly {
    return !_isConnected || _menuIsOpen || _isSliderVisible || _isThemeSelectorVisible;
  }
  
  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);

    terminal.onOutput = (data) {
      _bufferWrite(data);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screenWidth = MediaQuery.of(context).size.width;
      final isWideScreen = screenWidth >= 800;
      if (_fontSize == 14.0 && !isWideScreen) {
        _fontSize = 10.0;
      } else if (_fontSize == 10.0 && isWideScreen) {
        _fontSize = 14.0;
      }
      
      _connectToHost();
    });

    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && !_isSliderVisible) {
        _attachTextInput();
      } else if (!_inputFocusNode.hasFocus) {
        _detachTextInput();
      }
    });
  }

  Future<void> _connectToHost() async {
    if (_connectionEstablished) return;
    
    try {
      if (mounted) {
        setState(() {
          _menuIsOpen = false;
          _isSliderVisible = false;
          _isThemeSelectorVisible = false;
          _isConnecting = true;
          _status = '连接中...';
        });
      }
      _manageFocus();
      final sshService = SshService();
      _sshClient = await sshService.connect(widget.connection, widget.credential);

      _session = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      _stdoutSubscription = _session!.stdout.listen((data) {
        if (!mounted) return;
        try {
          terminal.write(utf8.decode(data));
        } catch (_) {}
      });

      _stderrSubscription = _session!.stderr.listen((data) {
        if (!mounted) return;
        try {
          terminal.write('错误: ${utf8.decode(data)}');
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
          _connectionEstablished = false;
        });
        terminal.write('\r\n连接已断开\r\n');
        _detachTextInput();
      });

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = '已连接';
          _connectionEstablished = true;
        });
        _manageFocus();
      }

      terminal.write('\x1B[2J\x1B[1;1H');
      terminal.buffer.clear();
      terminal.write('连接到 ${widget.connection.host} 成功\r\n');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接失败';
          _connectionEstablished = false;
        });
        terminal.write('连接失败: $e\r\n');
      }
    }
  }

  // 优化的焦点请求方法
  void _requestFocusWithDelay() {
    if (_focusRequested || _shouldBeReadOnly) return;
    
    _focusRequested = true;
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || _shouldBeReadOnly) {
        _focusRequested = false;
        return;
      }
      
      // 首先请求键盘焦点
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
      
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || _shouldBeReadOnly) {
          _focusRequested = false;
          return;
        }
        
        // 然后请求输入焦点
        FocusScope.of(context).requestFocus(_inputFocusNode);
        _attachTextInput();
        
        // 最后确保文本输入连接已附加
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!mounted || _shouldBeReadOnly) {
            _focusRequested = false;
            return;
          }
          _attachTextInput();
        });
      });
    });
  }

  void _bufferWrite(String text) {
    if (text.isEmpty || _shouldBeReadOnly) return;

    if (text.length == 1) {
      final now = DateTime.now();
      if ((text == '\r' || text == '\n') &&
          _lastSentChunk == '\r' &&
          _lastSendAt != null &&
          now.difference(_lastSendAt!) < const Duration(milliseconds: 250)) {
        return;
      }
      _lastSentChunk = text;
      _lastSendAt = now;
    } else {
      _lastSentChunk = null;
      _lastSendAt = null;
    }

    _writeBuffer.write(text);
    _flushTimer ??= Timer(_flushInterval, _flushToSession);
  }

  void _flushToSession() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_writeBuffer.isEmpty) return;
    final payload = _writeBuffer.toString();
    _writeBuffer.clear();
    if (_session != null && _isConnected) {
      try {
        _session!.write(utf8.encode(payload));
      } catch (_) {}
    } else {
      terminal.write(payload);
    }
  }

  @override
  TextEditingValue get currentTextEditingValue => _currentEditingValue;

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingValue = value;
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline ||
        action == TextInputAction.done ||
        action == TextInputAction.go ||
        action == TextInputAction.send ||
        action == TextInputAction.search ||
        action == TextInputAction.unspecified) {
      _bufferWrite('\r');
      debugPrint('performAction: action = $action');
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void connectionClosed() {
    _textInputConnection = null;
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    try { oldControl?.hide(); } catch (_) {}
    try { newControl?.show(); } catch (_) {}
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    try {
      final mime = content.mimeType;
      final data = content.data;
      if (mime.toLowerCase().startsWith('text') && data != null) {
        final s = utf8.decode(data);
        if (s.isNotEmpty) _bufferWrite(s);
      }
    } catch (_) {}
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void showToolbar() {}

  void _attachTextInput() {
    if (_textInputConnection != null && _textInputConnection!.attached) return;

    const config = TextInputConfiguration(
      inputType: TextInputType.multiline,
      inputAction: TextInputAction.newline,
      autocorrect: true,
      enableSuggestions: true,
    );

    _textInputConnection = TextInput.attach(this, config);
    _textInputConnection!.setEditingState(_currentEditingValue);
    _textInputConnection!.show();

    if (defaultTargetPlatform == TargetPlatform.android) {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  void _detachTextInput() {
    try { _textInputConnection?.close(); } catch (_) {}
    _textInputConnection = null;
    _currentEditingValue = const TextEditingValue(text: '');
  }

  void _clearTerminal() {
    _menuIsOpen = false;
    terminal.write('\x1B[2J\x1B[1;1H');
    terminal.buffer.clear();
    if (_session != null && _isConnected) {
      _bufferWrite('\x15');
      _bufferWrite('\x0C');
      _bufferWrite('\x1B[2J\x1B[H');
      _bufferWrite('clear\r');
    }
  }

  void _sendCtrlC() => _bufferWrite('\x03');
  void _sendCtrlD() => _bufferWrite('\x04');
  void _sendTab() => terminal.keyInput(TerminalKey.tab);

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _session?.close();
    _sshClient?.close();
    _detachTextInput();
    _keyboardFocusNode.dispose();
    _inputFocusNode.dispose();
    _hideSliderTimer?.cancel();
    _hideThemeSelectorTimer?.cancel(); 
    _flushTimer?.cancel();
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    try { _themeSelectorOverlay?.remove(); } catch (_) {}
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    super.dispose();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Colors.green.shade800;
    return Colors.red;
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      PopupMenuItem<String>(value: 'reconnect', child: Text('重新连接')),
      PopupMenuItem<String>(
        value: 'commands',
        child: Row(
          children: [
            Text('发送命令'),
            SizedBox(width: 8),
            Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
      PopupMenuItem<String>(value: 'clear', child: Text('清屏')),
      PopupMenuItem<String>(value: 'fontsize', child: Text('字体大小')),
      PopupMenuItem<String>(value: 'theme', child: Text('主题')),
      PopupMenuDivider(),
      PopupMenuItem<String>(value: 'disconnect', child: Text('断开连接并返回')),
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
    _manageFocus();
  }

  void _showThemeSelector() {
    if (_isThemeSelectorVisible) return;

    _isThemeSelectorVisible = true;
    _manageFocus();
    _hideThemeSelectorTimer?.cancel();

    _themeSelectorOverlay ??= OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hideThemeSelector,
                    onPanDown: (_) => _hideThemeSelector(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // 空操作，阻止事件冒泡
                      onPanDown: (_) {},
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.grey[900]!.withOpacity(0.7),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.7,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '选择主题',
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildThemeOption(
                                '默认',
                                TerminalThemes.defaultTheme,
                              ),
                              const SizedBox(height: 12),
                              _buildThemeOption(
                                '纯黑',
                                TerminalThemes.whiteOnBlack,
                              ),
                            ],
                          ),
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
                  style: TextStyle(
                    color:  Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
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
    setState(() {
      _currentTheme = newTheme;
    });
    _hideThemeSelector();
  }

  void _hideThemeSelector() {
    setState(() {
      _menuIsOpen = false;
      _isThemeSelectorVisible = false;
    });
    _manageFocus();
    _hideThemeSelectorTimer?.cancel();
    try { _themeSelectorOverlay?.remove(); } catch (_) {}
    _themeSelectorOverlay = null;
    
  }

  void _resetHideThemeSelectorTimer() {
    _hideThemeSelectorTimer?.cancel();
    _hideThemeSelectorTimer = Timer(const Duration(seconds: 5), _hideThemeSelector);
  }

  void _reconnect() {
    setState(() {
      _connectionEstablished = false;
      _focusRequested = false;
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
        PopupMenuItem<String>(value: 'backspace', child: Text('发送 Backspace')),
        PopupMenuItem<String>(value: 'ctrlc', child: Text('发送 Ctrl+C')),
        PopupMenuItem<String>(value: 'ctrld', child: Text('发送 Ctrl+D')),
      ],
    ).then((value) {
      if (value != null) _handleCommand(value);
      setState(() {
        _menuIsOpen = false;
      });
    });
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _bufferWrite('\r');
        _menuIsOpen = false;
        break;
      case 'tab':
        _sendTab();
        _menuIsOpen = false;
        break;
      case 'backspace':
        _bufferWrite('\x08');
        _menuIsOpen = false;
        break;
      case 'ctrlc':
        _sendCtrlC();
        _menuIsOpen = false;
        break;
      case 'ctrld':
        _sendCtrlD();
        _menuIsOpen = false;
        break;
    }
  }

  void _showFontSlider() {
    if (_isSliderVisible) return;
    _isSliderVisible = true;
    _manageFocus();
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
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.grey[900]!.withOpacity(0.7),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.8,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '字体大小',
                                    style: TextStyle(color: Colors.white, fontSize: 16),
                                  ),
                                  Text(
                                    '${_fontSize.toInt()}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: _fontSize,
                                min: 8,
                                max: 16,
                                divisions: 8,
                                onChanged: (v) {
                                  setStateOverlay(() {
                                    _fontSize = v;
                                  });
                                  if (mounted) setState(() {
                                    _fontSize = v;
                                  });
                                    _applyFontSize();
                                    _resetHideSliderTimer();
                                },
                              ),
                            ],
                          ),
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
    _manageFocus();
    _hideSliderTimer?.cancel();
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    _fontSliderOverlay = null;
    
  }

  void _resetHideSliderTimer() {
    _hideSliderTimer?.cancel();
    _hideSliderTimer = Timer(const Duration(seconds: 3), _hideFontSlider);
  }
//
  void _manageFocus() {
    if (_isThemeSelectorVisible || _isSliderVisible || _menuIsOpen) {
      _removeFocus();
    } else if (_isConnected && !_shouldBeReadOnly) {
      _requestFocusWithDelay();
    }
  }

  void _removeFocus() {
    _focusRequested = false;
    _detachTextInput();    // 移除所有焦点
    _keyboardFocusNode.unfocus();
    _inputFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _applyFontSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cols = terminal.viewWidth;
      final rows = terminal.viewHeight;

      if (cols <= 0 || rows <= 0) return;

      try {
        _session?.resizeTerminal(
          cols,
          rows,
          0,
          0,
        );
      } catch (e) {
        debugPrint('resizeTerminal error: $e');
      }
    });
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
              '${widget.connection.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle_outlined,
                  color: _isConnecting ? Colors.grey : Colors.white,
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
            onOpened: () {
              setState(() {
                _menuIsOpen = true;
              });
            },
            onCanceled: () {
              setState(() {
                _menuIsOpen = false;
              });
            },
          ),
        ],
      ),
    body: LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _applyFontSize();
        });
        
        return TerminalView(
          terminal,
          backgroundOpacity: 1.0,
          textStyle: TerminalStyle(fontSize: _fontSize, fontFamily: 'Monospace'),
          theme: _currentTheme,
          autoResize: true,
          readOnly: _shouldBeReadOnly,
          autofocus: false,
          showToolbar: _ismobile,
        );
      },
    ),
    );
  }
}