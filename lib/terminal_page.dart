// terminal_page.dart
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

  // EditableText controller 用于 IME/软键盘
  final TextEditingController _imeController = TextEditingController();
  final FocusNode _imeFocusNode = FocusNode();

  // 为了避免 TerminalView attach 系统 TextInput，使用 hardwareKeyboardOnly: true
  // 同时我们仍然支持硬件键盘（RawKeyboardListener）
  final FocusNode _rawKeyboardFocusNode = FocusNode();

  // 保存上一次编辑器文本以便计算差异
  String _prevImeText = '';

  @override
  void initState() {
    super.initState();

    // terminal：保持原有行为，不把 inputHandler 绑定到 widget 的内部 TextInput
    terminal = Terminal(
      maxLines: 10000,
    );

    // 当 terminal 产生 onOutput（例如从虚拟键盘或其它）我们也发给远端
    terminal.onOutput = (data) {
      if (_session != null && _isConnected) {
        try {
          _session!.write(utf8.encode(data));
        } catch (e) {
          // 忽略写入错误
        }
      }
    };

    // IME 编辑器文本变化监听（负责把输入/删除映射到 terminal + session）
    _imeController.addListener(_onImeChanged);

    // 在页面构建后再连接并聚焦（避免 TerminalView 在未 attach 时引发问题）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 小延迟以确保 TerminalView 完整构建，减少与 xterm 内部 attach 的竞态
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          // 我们把焦点放在 _rawKeyboardFocusNode 上以接收硬件键盘事件（RawKeyboard）
          FocusScope.of(context).requestFocus(_rawKeyboardFocusNode);
          // IME focus 不主动抢占，用户点击终端区域后会把焦点给 IME（见 GestureDetector）
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
          } catch (e) {}
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

  // IME 文本变化 -> 计算 diff 并发送
  void _onImeChanged() {
    final cur = _imeController.text;
    final prev = _prevImeText;

    // 快速路径
    if (cur == prev) return;

    // 找到最长相同前缀
    int prefix = 0;
    final minLen = cur.length < prev.length ? cur.length : prev.length;
    while (prefix < minLen && cur.codeUnitAt(prefix) == prev.codeUnitAt(prefix)) {
      prefix++;
    }

    // 找到最长相同后缀（注意处理重叠）
    int suffixPrev = prev.length;
    int suffixCur = cur.length;
    while (suffixPrev > prefix && suffixCur > prefix &&
        prev.codeUnitAt(suffixPrev - 1) == cur.codeUnitAt(suffixCur - 1)) {
      suffixPrev--;
      suffixCur--;
    }

    // 删除段（从 prev 中移除）
    final deleted = prev.substring(prefix, suffixPrev);
    // 插入段（在 cur 中新增）
    final inserted = cur.substring(prefix, suffixCur);

    // 处理删除：发送退格（或多次退格）
    if (deleted.isNotEmpty) {
      // 为了兼容各种远端 shell，我们发送对应数量的退格字符
      for (int i = 0; i < deleted.runes.length; i++) {
        _sendText('\x08'); // backspace
      }
      // 同时本地终端不需要额外回显删除（因为后续会回显插入或远端输出）
    }

    // 处理插入：直接发送 inserted 文本
    if (inserted.isNotEmpty) {
      _sendText(inserted);
      terminal.write(inserted); // 本地回显，以便用户看到
    }

    _prevImeText = cur;
  }

  // 发送文本到 session（并保护）
  void _sendText(String text) {
    if (_session != null && _isConnected) {
      try {
        _session!.write(utf8.encode(text));
      } catch (e) {
        // 忽略写入错误
      }
    } else {
      // 没有连上时在本地回显，方便调试
      terminal.write(text);
    }
  }

  // 物理键盘处理（RawKeyboard）: 支持 Enter/Backspace/Tab/Ctrl+X 等
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
        // 对于普通按键，尝试直接使用 event.character（桌面平台）
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

  // 用户点击终端区域：让 IME 输入框获得焦点，从而弹出软键盘（此 EditableText 是透明的）
  void _onTerminalTap() {
    // 把 focus 给 IME 编辑输入器，以便触发软键盘
    if (!_imeFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_imeFocusNode);
      // 把上一次文本清空，避免残留
      _prevImeText = '';
      _imeController.value = const TextEditingValue(text: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
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
            _sendText('\r\n');
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
                    // 真实的 TerminalView（来自 xterm 包），我们设置 hardwareKeyboardOnly: true
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
                          true, // 重要：阻止 xterm 自己 attach TextInput
                    ),

                    // 一个透明的 EditableText，用于接收 IME（放在 Stack 之上）
                    // 我们把它放在左上角，尺寸很小但可聚焦；点击终端时会给它焦点以弹出软键盘。
                    // 它不会显示文本（style 颜色透明），只是作为 IME 桥接器。
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0.0, // 完全透明
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
                              // Enter 提交 -> 发送回车
                              _sendText('\r\n');
                              // 清空编辑器（避免残留）
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
