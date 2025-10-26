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

class _TerminalPageState extends State<TerminalPage> {
  late final Terminal terminal;
  SSHClient? _sshClient;
  SSHSession? _session;
  bool _isConnected = false;
  String _status = '连接中...';
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;

  final TextEditingController _imeController = TextEditingController();
  final FocusNode _imeFocusNode = FocusNode();

  final FocusNode _rawKeyboardFocusNode = FocusNode();

  String _prevImeText = '';

  @override
  void initState() {
    super.initState();

    // terminal：保持原有行为，不把 inputHandler 绑定到 widget 的内部 TextInput
    terminal = Terminal(
      maxLines: 10000,
    );

    terminal.onOutput = (data) {
      if (_session != null && _isConnected) {
        try {
          _session!.write(utf8.encode(data));
        } catch (e) {
          // 忽略
        }
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
        _status = '已连接';
      });

      _stdoutSubscription = _session!.stdout.listen((data) {
        if (mounted) {
          try {
            terminal.write(utf8.decode(data));
          } catch (e) {
            //ignore
          }
        }
      });

      _stderrSubscription = _session!.stderr.listen((data) {
        if (mounted) {
          try {
            terminal.write('错误: ${utf8.decode(data)}');
          } catch (e) {
            terminal.write('错误: <stderr 解码失败>');
          }
        }
      });

      _session!.done.then((_) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _status = '连接已关闭';
          });
          terminal.write('\r\n连接已断开\r\n');
        }
      });

      terminal.write('连接到 ${widget.connection.host} 成功\r\n');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
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
    while (suffixPrev > prefix && suffixCur > prefix &&
        prev.codeUnitAt(suffixPrev - 1) == cur.codeUnitAt(suffixCur - 1)) {
      suffixPrev--;
      suffixCur--;
    }

    final deleted = prev.substring(prefix, suffixPrev);
    final inserted = cur.substring(prefix, suffixCur);


    if (deleted.isNotEmpty) {
      for (int i = 0; i < deleted.runes.length; i++) {
        _sendText('\x08'); // backspace
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
      } catch (e) {
        // 忽略
      }
    } else {
      terminal.write(text);
    }
  }

  // 物理键盘处理
  //bool _handleRawKeyEvent(RawKeyEvent event) {
    //if (event is RawKeyDownEvent) {
      //final isCtrl = event.isControlPressed;
      //final key = event.logicalKey;

      //if (key == LogicalKeyboardKey.enter) {
        //_sendText('\r\n');
        //return true;
      //} else if (key == LogicalKeyboardKey.backspace) {
      //  _sendText('\x08');
      //  return true;
      //} else if (key == LogicalKeyboardKey.tab) {
      //  _sendText('\t');
      //  return true;
      //} else if (isCtrl && key == LogicalKeyboardKey.keyC) {
      //  _sendText('\x03');
      //  return true;
      //} else if (isCtrl && key == LogicalKeyboardKey.keyD) {
      //  _sendText('\x04');
      //  return true;
      //} else {
      //}
    //}
    //return false;
  //}

  // 处理剪贴板粘贴（把整个文本发送）
  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        _sendText(text);
      }
    } catch (e) {
      // 忽略
    }
  }

void _clearTerminal() {
  terminal.write('\x1B[2J\x1B[1;1H');
  terminal.buffer.clear();      // 清空 scrollback buffer

  if (_session != null && _isConnected) {
    try {
      _sendText('\x15');
      _sendText('\x0C');
      _sendText('\x1B[2J\x1B[H');
      _sendText('clear\r');
    } catch (e) {
      // 忽略
    }
  } else {
    // 未连接时，仅本地清屏
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
    super.dispose();
  }

  void _onTerminalTap() {
    if (!_imeFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_imeFocusNode);
      _prevImeText = '';
      _imeController.value = const TextEditingValue(text: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
appBar: AppBar(
  backgroundColor: _isConnected ? Colors.green : Colors.red,
  foregroundColor: Colors.white,
  title: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${widget.connection.host}:${widget.connection.port}',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Row(
        children: [
          Icon(
            _isConnected ? Icons.circle : Icons.circle_outlined,
            color: Colors.white,
            size: 10,
          ),
          const SizedBox(width: 6),
          Text(
            _status,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(width: 10),
          if (!_isConnected)
            TextButton(
              onPressed: _connectToHost,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('重新连接'),
            ),
        ],
      ),
    ],
  ),
  actions: [
    PopupMenuButton(
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'enter', child: Text('发送 Enter')),
        const PopupMenuItem(value: 'tab', child: Text('发送 Tab')),
        const PopupMenuItem(value: 'backspace', child: Text('发送 Backspace')),
        const PopupMenuItem(value: 'ctrlc', child: Text('发送 Ctrl+C')),
        const PopupMenuItem(value: 'ctrld', child: Text('发送 Ctrl+D')),
        const PopupMenuItem(value: 'clear', child: Text('清屏')),
        const PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
      ],
      onSelected: (value) {
        switch (value) {
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
          case 'clear':
            _clearTerminal();
            break;
          case 'disconnect':
            Navigator.of(context).pop();
            break;
        }
      },
    ),
  ],
),

      body: Column(
        children: [
          // 终端主区：使用 Stack 放置 TerminalView（显示），以及透明的 EditableText（接受 IME）
          // 完全禁用了onKey，只使用EditableText来接受文字输入
          Expanded(
            // ignore: deprecated_member_use
            child: RawKeyboardListener(
              focusNode: _rawKeyboardFocusNode,
              //onKey: (event) {
                //_handleRawKeyEvent(event);
              //},
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTerminalTap,
                onLongPress: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('确认是否粘贴剪贴板内容？'),
                      duration: const Duration(seconds: 4),
                      behavior: SnackBarBehavior.floating,
                      action: SnackBarAction(
                        label: '粘贴',
                        onPressed: () async {
                          await _pasteFromClipboard();
                        },
                      ),
                    ),
                  );
                },


                onSecondaryTapDown: (details) async {
                  // 右键（桌面） -> 粘贴
                  await _pasteFromClipboard();
                },
                child: Stack(
                  children: [
                    TerminalView(
                      terminal,
                      backgroundOpacity: 1.0,
                      textStyle: const TerminalStyle(
                        fontSize: 14,
                        fontFamily: 'Monospace',
                      ),
                      autoResize: true,
                      readOnly: false,
                      hardwareKeyboardOnly:
                          true, 
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0.0, 
                        child: IgnorePointer(
                          ignoring: false,
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
