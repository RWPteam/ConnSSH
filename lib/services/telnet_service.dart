import 'dart:async';
import 'dart:convert';
import 'package:ctelnet/ctelnet.dart';
import 'package:fast_gbk/fast_gbk.dart';
import '../models/telnet_connection_model.dart';

class TelnetService {
  CTelnetClient? _client;
  StreamSubscription<Message>? _subscription;
  String _terminalType = 'xterm';
  String _lineSeparator = '\r\n';
  // 编码相关
  Encoding _encoding = utf8;
  List<int> _buffer = [];

  // Telnet 选项常量（根据实际的 Symbols 类调整）
  static const int TELNET_OPT_ECHO = 1; // Echo
  static const int TELNET_OPT_NAWS = 31; // Window size
  static const int TELNET_OPT_TERMINAL_TYPE = 24; // Terminal type
  static const int TELNET_OPT_CHARSET = 42; // Charset

  // 连接状态回调
  final void Function()? onConnected;
  final void Function()? onDisconnected;
  final void Function(String error)? onError;
  final void Function(String data)? onDataReceived;

  TelnetService({
    this.onConnected,
    this.onDisconnected,
    this.onError,
    this.onDataReceived,
  });

  // 连接到Telnet服务器
  Future<void> connect(TelnetConnectionInfo connection) async {
    try {
      _terminalType = connection.terminalType.toString().split('.').last;

      _encoding = _getEncoding(connection.encoding);
      _client = CTelnetClient(
        host: connection.host,
        port: connection.port,
        timeout: const Duration(seconds: 10),
        onConnect: () {
          onConnected?.call();

          if (connection.username != null && connection.username!.isNotEmpty) {
            // 发送用户名
            Timer(const Duration(milliseconds: 500), () {
              send('${connection.username!}$_lineSeparator');

              // 如果有密码，延迟发送
              if (connection.password != null &&
                  connection.password!.isNotEmpty) {
                Timer(const Duration(milliseconds: 300), () {
                  send('${connection.password!}$_lineSeparator');
                });
              }
            });
          }
        },
        onDisconnect: () {
          onDisconnected?.call();
          _buffer.clear();
        },
        onError: (error) {
          onError?.call(error.toString());
        },
      );

      // 连接并监听数据流
      final stream = await _client!.connect();
      if (stream == null) {
        throw Exception('Failed to connect');
      }

      _subscription = stream.listen(_handleMessage);
    } catch (e) {
      throw Exception('连接失败: $e');
    }
  }

  // 根据枚举获取编码
  Encoding _getEncoding(TelnetEncoding telnetEncoding) {
    switch (telnetEncoding) {
      case TelnetEncoding.gbk:
      case TelnetEncoding.gb2312:
        return gbk;
      case TelnetEncoding.utf8:
        return utf8;
      case TelnetEncoding.ascii:
        return ascii;
      case TelnetEncoding.iso8859_1:
        return latin1;
      case TelnetEncoding.big5:
        return latin1;
    }
  }

  // 处理接收到的消息
  void _handleMessage(Message message) {
    if (message.text.isNotEmpty) {
      _processTextData(message.text);
    }

    // 处理其他Telnet选项
    _handleTelnetOptions(message);
  }

  // 处理文本数据
  void _processTextData(String text) {
    final bytes = text.runes.map((rune) {
      if (rune <= 0xFF) {
        return rune;
      } else {
        return 0x3F; // '?'
      }
    }).toList();

    _buffer.addAll(bytes);

    String? decoded;

    try {
      decoded = _encoding.decode(_buffer);
      _buffer.clear();
    } catch (e) {
      decoded = _tryDetectAndDecode(_buffer);
    }

    if (decoded != null && decoded.isNotEmpty) {
      onDataReceived?.call(decoded);
    }
  }

  // 尝试检测并解码
  String? _tryDetectAndDecode(List<int> buffer) {
    // 尝试UTF-8
    try {
      final decoded = utf8.decode(buffer);
      _buffer.clear();
      _encoding = utf8; // 更新编码
      return decoded;
    } catch (e) {
      // UTF-8 失败
    }

    try {
      final decoded = gbk.decode(buffer);
      _buffer.clear();
      _encoding = gbk; // 更新编码
      return decoded;
    } catch (e) {
      // GBK 失败
    }

    // 如果缓冲区过长，清空并返回ASCII部分
    if (_buffer.length > 1024) {
      final result = String.fromCharCodes(_buffer.where((b) => b < 128));
      _buffer.clear();
      return result.isNotEmpty ? result : null;
    }

    return null; // 继续等待更多数据
  }

  // 处理Telnet选项协商
  void _handleTelnetOptions(Message message) {
    if (_containsTerminalTypeRequest(message.text)) {
      _sendTerminalType(_terminalType);
    }
  }

  // 检查是否包含终端类型请求
  bool _containsTerminalTypeRequest(String text) {
    // 简单的启发式检查
    return text.contains('TERMINAL-TYPE') ||
        text.contains('terminal type') ||
        text.contains('Terminal type');
  }

  // 发送终端类型子协商
  void _sendTerminalType(String type) {
    if (_client != null) {
      // 发送 IAC SB TERMINAL_TYPE IS <type> IAC SE
      final bytes = [
        Symbols.iac,
        Symbols.sb,
        TELNET_OPT_TERMINAL_TYPE,
        0x00, // IS
        ...type.codeUnits,
        Symbols.iac,
        Symbols.se,
      ];
      _client!.sendBytes(bytes);
    }
  }

  // 发送数据（使用当前编码）
  void send(String data) {
    if (_client != null) {
      final bytes = _encodeString(data);
      _client!.sendBytes(bytes);
    }
  }

  // 编码字符串
  List<int> _encodeString(String data) {
    try {
      return _encoding.encode(data);
    } catch (e) {
      // 如果编码失败，尝试UTF-8
      try {
        return utf8.encode(data);
      } catch (e) {
        // 最后尝试使用Latin-1
        return latin1.encode(data);
      }
    }
  }

  // 发送字节数据
  void sendBytes(List<int> bytes) {
    if (_client != null) {
      _client!.sendBytes(bytes);
    }
  }

  // 发送Telnet IAC命令
  void sendIacCommand(int command) {
    if (_client != null) {
      _client!.sendBytes([Symbols.iac, command]);
    }
  }

  // 发送特殊命令
  void sendSpecialCommand(int command) {
    sendIacCommand(command);
  }

  // 发送换行（根据配置）
  void sendNewLine(TelnetLineSeparator lineSeparator) {
    switch (lineSeparator) {
      case TelnetLineSeparator.cr:
        send('\r');
        break;
      case TelnetLineSeparator.lf:
        send('\n');
        break;
      case TelnetLineSeparator.crlf:
        send('\r\n');
        break;
    }
  }

  // 设置编码
  void setEncoding(TelnetEncoding telnetEncoding) {
    _encoding = _getEncoding(telnetEncoding);
    _buffer.clear(); // 清空缓冲区
  }

  // 获取当前编码
  Encoding get currentEncoding => _encoding;

  // 断开连接
  void disconnect() {
    _subscription?.cancel();
    _client?.disconnect();
    _client = null;
    _buffer.clear();
  }

  // 检查是否连接
  bool isConnected() {
    return _client != null;
  }
}
