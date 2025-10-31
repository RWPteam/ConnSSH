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

  // 关键点：只为 KeyboardListener 使用一个独立的 FocusNode（用于物理键盘事件）
  final FocusNode _keyboardFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode();
  TextInputConnection? _textInputConnection;
  TextEditingValue _currentEditingValue = TextEditingValue.empty;

  // 字体
  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;
  
  // 写缓冲
  final StringBuffer _writeBuffer = StringBuffer();
  Timer? _flushTimer;
  final Duration _flushInterval = const Duration(milliseconds: 20);

  DateTime? _lastSendAt;
  String? _lastSentChunk;

  // 滑块是否显示
  bool _isSliderVisible = false;

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
      // 初始把焦点给 keyboard listener（方便物理键盘立刻可用）
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) FocusScope.of(context).requestFocus(_keyboardFocusNode);
      });
      _connectToHost();
    });

    // 监听焦点变化，控制透明输入框显示
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus && !_isSliderVisible) {
        _attachTextInput();
      }
    });
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
        });
        terminal.write('\r\n连接已断开\r\n');
        _detachTextInput();
      });

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = '已连接';
        });
      }

      terminal.write('\x1B[2J\x1B[1;1H');
      terminal.buffer.clear();
      terminal.write('连接到 ${widget.connection.host} 成功\r\n');
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

  void _bufferWrite(String text) {
    if (text.isEmpty) return;

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

  //
  // TextInputClient
  //
  @override
  TextEditingValue get currentTextEditingValue => _currentEditingValue;

  @override
  void updateEditingValue(TextEditingValue value) {
    final prev = _currentEditingValue.text;
    final cur = value.text;
    _currentEditingValue = value;

    if (cur == prev) return;

    int prefix = 0;
    final minLen = cur.length < prev.length ? cur.length : prev.length;
    while (prefix < minLen && cur.codeUnitAt(prefix) == prev.codeUnitAt(prefix)) {
      prefix++;
    }

    int suffixPrev = prev.length;
    int suffixCur = cur.length;
    while (suffixPrev > prefix &&
        suffixCur > prefix &&
        prev.codeUnitAt(suffixPrev - 1) == cur.codeUnitAt(suffixCur - 1)) {
      suffixPrev--;
      suffixCur--;
    }

    final deleted = prev.substring(prefix, suffixPrev);
    final inserted = cur.substring(prefix, suffixCur);

    if (deleted.isNotEmpty) {
      for (final _ in deleted.runes) {
        _bufferWrite('\x08');
      }
    }

    if (inserted.isNotEmpty) {
      _bufferWrite(inserted);
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline ||
        action == TextInputAction.done ||
        action == TextInputAction.go ||
        action == TextInputAction.send ||
        action == TextInputAction.search ||
        action == TextInputAction.unspecified) {
      // 直接发送回车，不重置编辑值
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

    // Android sometimes won't pop the soft keyboard unless手动调用 textInput.show
    // 调用两次也安全（是冗余的保证），并且在非 Android 平台也不会有副作用
    if (defaultTargetPlatform == TargetPlatform.android) {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  void _detachTextInput() {
    try { _textInputConnection?.close(); } catch (_) {}
    _textInputConnection = null;
    _currentEditingValue = const TextEditingValue(text: '');
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text != null && text.isNotEmpty) _bufferWrite(text);
    } catch (_) {}
  }

  void _clearTerminal() {
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
    _flushTimer?.cancel();
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    super.dispose();
  }

  void _onTerminalTap() {
    // 请求焦点到输入节点以激活软键盘
    if (!_isSliderVisible) {
      FocusScope.of(context).requestFocus(_inputFocusNode);
      
      // 强制显示软键盘
      if (defaultTargetPlatform == TargetPlatform.android) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    }

    _hideFontSlider();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Colors.green.shade800;
    return Colors.red;
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return const [
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
        _connectToHost();
        break;
      case 'commands':
        _showCommandsSubMenu();
        break;
      case 'clear':
        _clearTerminal();
        break;
      case 'disconnect':
        Navigator.of(context).pop();
        break;
    }
    // 选择菜单项后，如果当前有输入焦点，移除焦点以关闭输入法
    if (_inputFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    }
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
      // 选择命令后，如果当前有输入焦点，移除焦点以关闭输入法
      if (_inputFocusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_keyboardFocusNode);
      }
    });
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _bufferWrite('\r');
        break;
      case 'tab':
        _bufferWrite('\t');
        break;
      case 'backspace':
        _bufferWrite('\x08');
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
    // 如果滑块已经显示，则不重复显示
    if (_isSliderVisible) return;
    
    _isSliderVisible = true;
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
                // 使用 Center 来垂直居中，并降低透明度
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // 阻止点击滑块区域关闭
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(16),
                        // 降低透明度：从 0.95 降到 0.7
                        color: Colors.grey[900]!.withOpacity(0.7),
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.8, // 限制宽度
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
                                max: 40,
                                divisions: 32,
                                onChanged: (v) {
                                  setStateOverlay(() {
                                    _fontSize = v;
                                  });
                                  if (mounted) setState(() {});
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
    
    if (_inputFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_keyboardFocusNode);
    }
  }
  void _hideFontSlider() {
    _isSliderVisible = false;
    _hideSliderTimer?.cancel();
    try { _fontSliderOverlay?.remove(); } catch (_) {}
    _fontSliderOverlay = null;
    // 关闭字体滑块后，如果之前有输入焦点，重新请求焦点到输入框
    if (_inputFocusNode.hasFocus == false && mounted) {
      FocusScope.of(context).requestFocus(_inputFocusNode);
    }
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
              '${widget.connection.host}:${widget.connection.port}',
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
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // TerminalView 作为背景
                KeyboardListener(
                  focusNode: _keyboardFocusNode,
                  onKeyEvent: (KeyEvent event) {
                    if (event is KeyDownEvent || event is KeyRepeatEvent) {
                      if (HardwareKeyboard.instance.isControlPressed) {
                        final label = event.logicalKey.keyLabel;
                        if (label == '=') {
                          setState(() => _fontSize = (_fontSize + 1).clamp(8, 40));
                          return;
                        } else if (label == '-') {
                          setState(() => _fontSize = (_fontSize - 1).clamp(8, 40));
                          return;
                        }
                        return;
                      }

                      if (event.logicalKey == LogicalKeyboardKey.enter) {
                        _bufferWrite('\r');
                        return;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.tab) {
                        _bufferWrite('\t');
                        return;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.backspace) {
                        _bufferWrite('\x08');
                        return;
                      }

                      final ch = event.character;
                      if (ch != null && ch.isNotEmpty) {
                        _bufferWrite(ch);
                        return;
                      }
                    }

                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                      _hideFontSlider();
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTerminalTap,
                    onLongPress: () {
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.clearSnackBars();
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('确认是否粘贴剪贴板内容？'),
                          action: SnackBarAction(label: '粘贴', onPressed: () => _pasteFromClipboard()),
                        ),
                      );
                    },
                    onSecondaryTapDown: (_) => _pasteFromClipboard(),
                    child: TerminalView(
                      terminal,
                      backgroundOpacity: 1.0,
                      textStyle: TerminalStyle(fontSize: _fontSize, fontFamily: 'Monospace'),
                      autoResize: true,
                      readOnly: false, // 允许交互
                      autofocus: false,
                    ),
                  ),
                ),
                // 完全透明的覆盖层，用于接收输入焦点
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: _isSliderVisible, // 当滑块显示时，忽略输入框的点击事件
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: TextEditingController.fromValue(_currentEditingValue),
                      onChanged: (text) {
                        final newValue = TextEditingValue(
                          text: text,
                          selection: TextSelection.fromPosition(
                            TextPosition(offset: text.length),
                          ),
                        );
                        updateEditingValue(newValue);
                      },
                      onSubmitted: (text) {
                        // 在多行文本框中，回车不提交，而是换行
                        _bufferWrite('\n');
                      },
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      maxLines: null, // 支持多行
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 0.1,
                      ),
                      cursorColor: Colors.transparent,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      enableInteractiveSelection: false,
                      showCursor: false,
                      contextMenuBuilder: (context, editableTextState) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



