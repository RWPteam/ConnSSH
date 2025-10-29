import 'dart:async';
import 'dart:convert';
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

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal terminal;
  SSHClient? _sshClient;
  SSHSession? _session;
  bool _isConnected = false;
  bool _isConnecting = true;
  String _status = '连接中...';
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  final TextEditingController _imeController = TextEditingController();
  final FocusNode _imeFocusNode = FocusNode();
  final FocusNode _rawKeyboardFocusNode = FocusNode();

  String _prevImeText = '';

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;

  @override
  void initState() {
    super.initState();

    terminal = Terminal(
      maxLines: 10000,
    );

    terminal.onOutput = (data) {
      if (_session != null && _isConnected) {
        try {
          _session!.write(utf8.encode(data));
        } catch (_) {}
      }
    };

    _imeController.addListener(_onImeChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(_rawKeyboardFocusNode);
        }
      });

      _connectToHost();
    });
  }

  Future<void> _connectToHost() async {
    try {
      setState(() {
        _isConnecting = true;
        _status = '连接中...';
      });

      final sshService = SshService();
      _sshClient = await sshService.connect(widget.connection, widget.credential);

      _session = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _status = '已连接';
      });

      _stdoutSubscription = _session!.stdout.listen((data) {
        if (mounted) {
          try {
            terminal.write(utf8.decode(data));
          } catch (_) {}
        }
      });

      _stderrSubscription = _session!.stderr.listen((data) {
        if (mounted) {
          try {
            terminal.write('错误: ${utf8.decode(data)}');
          } catch (_) {
            terminal.write('错误: <stderr 解码失败>');
          }
        }
      });

      _session!.done.then((_) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _status = '连接已断开';
          });
          terminal.write('\r\n连接已断开\r\n');
        }
      });

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

  void _onImeChanged() {
    final cur = _imeController.text;
    final prev = _prevImeText;
    if (cur == prev) return;

    int prefix = 0;
    final minLen = cur.length < prev.length ? cur.length : prev.length;
    while (prefix < minLen && cur.codeUnitAt(prefix) == prev.codeUnitAt(prefix)) {
      prefix++;
    }

    int suffixPrev = prev.length;
    int suffixCur = cur.length;
    while (suffixPrev > prefix && suffixCur > prefix && prev.codeUnitAt(suffixPrev - 1) == cur.codeUnitAt(suffixCur - 1)) {
      suffixPrev--;
      suffixCur--;
    }

    final deleted = prev.substring(prefix, suffixPrev);
    final inserted = cur.substring(prefix, suffixCur);

    if (deleted.isNotEmpty) {
      for (int i = 0; i < deleted.runes.length; i++) {
        _sendText('\x08');
      }
    }

    if (inserted.isNotEmpty) {
      _sendText(inserted);
      terminal.write(inserted);
    }

    _prevImeText = cur;
  }

  void _sendText(String text) {
    if (_session != null && _isConnected) {
      try {
        _session!.write(utf8.encode(text));
      } catch (_) {}
    } else {
      terminal.write(text);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text != null && text.isNotEmpty) _sendText(text);
    } catch (_) {}
  }

  void _clearTerminal() {
    terminal.write('\x1B[2J\x1B[1;1H');
    terminal.buffer.clear();
    if (_session != null && _isConnected) {
      try {
        _sendText('\x15');
        _sendText('\x0C');
        _sendText('\x1B[2J\x1B[H');
        _sendText('clear\r');
      } catch (_) {}
    }
  }

  void _sendCtrlC() => _sendText('\x03');
  void _sendCtrlD() => _sendText('\x04');

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _session?.close();
    _sshClient?.close();
    _imeController.removeListener(_onImeChanged);
    _imeController.dispose();
    _imeFocusNode.dispose();
    _rawKeyboardFocusNode.dispose();
    _hideSliderTimer?.cancel();
    _hideFontSlider();
    super.dispose();
  }

  void _onTerminalTap() {
    if (!_imeFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_imeFocusNode);
      _prevImeText = '';
      _imeController.value = const TextEditingValue(text: '');
    }
    _hideFontSlider();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Colors.green.shade800;
    return Colors.red;
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      const PopupMenuItem<String>(value: 'reconnect', child: Text('重新连接')),
      const PopupMenuItem<String>(
        value: 'commands',
        child: Row(
          children: [
            Text('发送命令'),
            SizedBox(width: 8),
            Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
      const PopupMenuItem<String>(value: 'clear', child: Text('清屏')),
      const PopupMenuItem<String>(value: 'fontsize', child: Text('字体大小')),
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
      items: [
        const PopupMenuItem<String>(value: 'enter', child: Text('发送 Enter')),
        const PopupMenuItem<String>(value: 'tab', child: Text('发送 Tab')),
        const PopupMenuItem<String>(value: 'backspace', child: Text('发送 Backspace')),
        const PopupMenuItem<String>(value: 'ctrlc', child: Text('发送 Ctrl+C')),
        const PopupMenuItem<String>(value: 'ctrld', child: Text('发送 Ctrl+D')),
      ],
    ).then((value) {
      if (value != null) {
        _handleCommand(value);
      }
    });
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _sendText('\r');
        break;
      case 'tab':
        _sendText('\t');
        break;
      case 'backspace':
        _sendText('\x08');
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
    _hideSliderTimer?.cancel();

    _fontSliderOverlay ??= OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _hideFontSlider,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: GestureDetector(
                    onTap: () {}, 
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey[900]!.withOpacity(0.95),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('字体大小',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
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
                              max: 40,
                              divisions: 32,
                              onChanged: (v) {
                                setStateOverlay(() {
                                  _fontSize = v;
                                });
                                setState(() {});
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
    _hideSliderTimer?.cancel();
    _fontSliderOverlay?.remove();
    _fontSliderOverlay = null;
  }

  void _resetHideSliderTimer() {
    _hideSliderTimer?.cancel();
    _hideSliderTimer = Timer(const Duration(seconds: 3), _hideFontSlider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _getAppBarColor(),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.connection.host}:${widget.connection.port}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(_isConnected ? Icons.circle : Icons.circle_outlined,
                  color: _isConnecting ? Colors.grey : Colors.white, size: 10,
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
            child: RawKeyboardListener(
              focusNode: _rawKeyboardFocusNode,
              onKey: (event) {
                if (event.isControlPressed && event is RawKeyDownEvent) {
                  if (event.logicalKey.keyLabel == '=') {
                    setState(() => _fontSize = (_fontSize + 1).clamp(8, 40));
                  } else if (event.logicalKey.keyLabel == '-') {
                    setState(() => _fontSize = (_fontSize - 1).clamp(8, 40));
                  }
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
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
                child: Stack(
                  children: [
                    TerminalView(
                      terminal,
                      backgroundOpacity: 1.0,
                      textStyle: TerminalStyle(fontSize: _fontSize, fontFamily: 'Monospace'),
                      autoResize: true,
                      readOnly: false,
                      hardwareKeyboardOnly: true,
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0.0,
                        child: EditableText(
                          controller: _imeController,
                          focusNode: _imeFocusNode,
                          style: const TextStyle(color: Colors.transparent, fontSize: 14),
                          cursorColor: Colors.transparent,
                          backgroundCursorColor: Colors.transparent,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          autofocus: false,
                          onSubmitted: (v) {
                            _sendText('\r\n');
                            _imeController.value = const TextEditingValue(text: '');
                            _prevImeText = '';
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}