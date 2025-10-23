// terminal_page.dart
import 'dart:convert';
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
  String _status = '连接中...';

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000,);
    
    WidgetsBinding.instance.addPostFrameCallback((_){
      _connectToHost();
    });
  }

  void _setupTerminalInput() {
    // 设置输入处理器
    terminal.onOutput = (data) {
      // 发送用户输入到 SSH 会话
      _session?.write(utf8.encode(data));
    };
    
    // 设置键盘输入处理器
  }

  Future<void> _connectToHost() async {
    try {
      final sshService = SshService();
      _sshClient = await sshService.connect(widget.connection, widget.credential);
      
      // 创建交互式shell会话
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

      // 监听终端输出
      _session!.stdout.listen((data) {
        terminal.write(utf8.decode(data));
      });

      // 监听错误
      _session!.stderr.listen((data) {
        terminal.write('错误: ${utf8.decode(data)}');
      });
      
      // 监听会话关闭
      _session!.done.then((_) {
        if (mounted) {
          setState(() {
            _isConnected = false;
            _status = '连接已关闭';
          });
          terminal.write('\r\n连接已断开\r\n');
        }
      });
      _setupTerminalInput();
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

  void _clearTerminal() {
    // 使用 ANSI 转义序列清屏
    terminal.write('\x1B[2J\x1B[0;0H');
  }

  void _sendText(String text) {
    if (_session != null) {
      _session!.write(utf8.encode(text));
    }
  }

  void _sendEnter() {
    _sendText('\r');
  }

  void _sendBackspace() {
    _sendText('\x08');
  }

  void _sendCtrlC() {
    _sendText('\x03');
  }

  void _sendCtrlD() {
    _sendText('\x04');
  }

  void _sendTab() {
    _sendText('\t');
  }

  @override
  void dispose() {
    _session?.close();
    _sshClient?.close();
    super.dispose();
  }

  
@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('终端 - ${widget.connection.host}'),
        backgroundColor: _isConnected ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
        actions: [
          // 快捷键按钮
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'enter',
                child: Text('发送 Enter'),
              ),
              const PopupMenuItem(
                value: 'tab',
                child: Text('发送 Tab'),
              ),
              const PopupMenuItem(
                value: 'backspace',
                child: Text('发送 Backspace'),
              ),
              const PopupMenuItem(
                value: 'ctrlc',
                child: Text('发送 Ctrl+C'),
              ),
              const PopupMenuItem(
                value: 'ctrld',
                child: Text('发送 Ctrl+D'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('清屏'),
              ),
              const PopupMenuItem(
                value: 'disconnect',
                child: Text('断开连接'),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'enter':
                  _sendEnter();
                  break;
                case 'tab':
                  _sendTab();
                  break;
                case 'backspace':
                  _sendBackspace();
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
          // 状态栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[200],
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle_outlined,
                  color: _isConnected ? Colors.green : Colors.red,
                  size: 12,
                ),
                const SizedBox(width: 8),
                Text(_status),
                const Spacer(),
                if (!_isConnected)
                  TextButton(
                    onPressed: _connectToHost,
                    child: const Text('重新连接'),
                  ),
                Text('${widget.connection.host}:${widget.connection.port}'),
              ],
            ),
          ),
          // 终端
          Expanded(
            child: FutureBuilder(
              future: Future.delayed(const Duration(milliseconds: 500)),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
              
                return Focus(
                  autofocus: true,
                  child: TerminalView(
                    terminal,
                    backgroundOpacity: 1.0,
                    textStyle: const TerminalStyle(
                      fontSize: 14,
                      fontFamily: 'Monospace',
                    ),
                  ),
                );
              },
            ),
          ),
          // 虚拟键盘（可选，用于测试）
          if (!_isConnected) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _connectToHost,
                    child: const Text('重新连接'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
