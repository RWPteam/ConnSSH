import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gbk_codec/gbk_codec.dart';

class SocketDebugPage extends StatefulWidget {
  const SocketDebugPage({super.key});

  @override
  State<SocketDebugPage> createState() => _SocketDebugPageState();
}

enum SocketMode {
  hex,
  text,
}

class _SocketDebugPageState extends State<SocketDebugPage> {
  // Socket连接相关
  Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _errorMessage = '';

  // 输入控制
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _sendController = TextEditingController();
  final TextEditingController _receiveController = TextEditingController();

  // 模式设置
  SocketMode _currentMode = SocketMode.text;
  bool _autoReconnect = false;
  bool _autoScroll = true;
  int _receiveTimeout = 2000;
  String _charset = 'utf-8';

  // 数据统计
  int _totalSent = 0;
  int _totalReceived = 0;
  Timer? _statTimer;
  Timer? _reconnectTimer;

  // 接收数据缓冲
  final List<String> _receiveBuffer = [];

  final ScrollController _receiveScrollController = ScrollController();

  // 用于控制异步操作
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadLastSettings();
  }

  @override
  void dispose() {
    _isDisposed = true;

    // 先取消所有定时器
    _statTimer?.cancel();
    _statTimer = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // 关闭socket但不调用setState
    _closeSocketSilently();

    // 销毁控制器
    _ipController.dispose();
    _portController.dispose();
    _sendController.dispose();
    _receiveController.dispose();
    _receiveScrollController.dispose();

    super.dispose();
  }

  // 静默关闭socket，不调用setState
  void _closeSocketSilently() {
    try {
      _socket?.destroy();
    } catch (e) {
      // 忽略关闭时的错误
    }
    _socket = null;
  }

  Future<void> _loadLastSettings() async {
    _ipController.text = '127.0.0.1';
    _portController.text = '8080';
  }

  Future<void> _connect() async {
    if (_isConnecting || _isConnected) return;

    final String ip = _ipController.text.trim();
    final String portStr = _portController.text.trim();

    if (ip.isEmpty) {
      _showError('请输入IP地址');
      return;
    }

    if (portStr.isEmpty) {
      _showError('请输入端口号');
      return;
    }

    final int? port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      _showError('端口号无效 (1-65535)');
      return;
    }

    if (!mounted || _isDisposed) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = '';
    });

    try {
      // 尝试解析主机名
      final List<InternetAddress> addresses = await InternetAddress.lookup(ip);
      if (addresses.isEmpty) {
        throw SocketException('无法解析主机名: $ip');
      }

      final InternetAddress address = addresses.first;

      _socket = await Socket.connect(address, port,
          timeout: Duration(milliseconds: _receiveTimeout));

      // 设置socket选项
      _socket?.setOption(SocketOption.tcpNoDelay, true);

      // 监听数据
      _socket?.listen(
        (data) => _handleReceivedData(data),
        onError: (error) => _handleSocketError(error),
        onDone: () => _handleDisconnected(),
        cancelOnError: true,
      );

      if (!mounted || _isDisposed) {
        _closeSocketSilently();
        return;
      }

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _totalSent = 0;
        _totalReceived = 0;
      });

      // 启动统计定时器
      _statTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && !_isDisposed && _isConnected) {
          setState(() {});
        } else {
          timer.cancel();
        }
      });
    } catch (e) {
      if (!mounted || _isDisposed) return;

      _logToBuffer('${_getTimestamp()} 连接失败: $e');
      setState(() {
        _isConnecting = false;
        _errorMessage = '连接失败: ${e.toString()}';
      });

      try {
        _socket?.destroy();
      } catch (e) {}
      _socket = null;
    }
  }

  void _handleReceivedData(List<int> data) {
    if (!mounted || _isDisposed || data.isEmpty) return;

    try {
      String decodedData;

      if (_currentMode == SocketMode.hex) {
        decodedData = _bytesToHex(data);
      } else {
        try {
          if (_charset.toLowerCase() == 'utf-8') {
            decodedData = utf8.decode(data, allowMalformed: true);
          } else {
            decodedData = gbk.decode(data);
          }
        } catch (e) {
          decodedData = '[解码失败，原始HEX]: ${_bytesToHex(data)}';
        }
      }

      _totalReceived += data.length;

      _logToBuffer('${_getTimestamp()} 接收 (${data.length}字节): $decodedData');
    } catch (e) {
      _logToBuffer('${_getTimestamp()} 处理接收数据失败: $e');
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  List<int> _hexToBytes(String hexString) {
    final hexPattern = RegExp(r'[0-9a-fA-F]+');
    final hex = hexString.replaceAll(RegExp(r'\s+'), '');

    if (!hexPattern.hasMatch(hex) || hex.length % 2 != 0) {
      throw FormatException('无效的十六进制格式');
    }

    final List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      final byteStr = hex.substring(i, i + 2);
      final byte = int.parse(byteStr, radix: 16);
      bytes.add(byte);
    }
    return bytes;
  }

  void _handleSocketError(dynamic error) {
    if (!mounted || _isDisposed) return;

    _logToBuffer('${_getTimestamp()} Socket错误: $error');

    setState(() {
      _errorMessage = '连接错误: $error';
    });

    _disconnect();
  }

  void _handleDisconnected() {
    if (!mounted || _isDisposed) return;

    _logToBuffer('${_getTimestamp()} 连接断开');

    setState(() {
      _isConnected = false;
    });

    // 清理资源
    _statTimer?.cancel();
    _statTimer = null;

    // 自动重连逻辑
    if (_autoReconnect) {
      _logToBuffer('${_getTimestamp()} 2秒后尝试重连...');

      // 2秒后重连
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        if (!_isDisposed && mounted && !_isConnected && !_isConnecting) {
          _logToBuffer('${_getTimestamp()} 开始重连...');
          _connect();
        }
      });
    }
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _statTimer?.cancel();
    _statTimer = null;

    try {
      _socket?.close();
      _socket?.destroy();
    } catch (e) {
      print('断开连接时出错: $e');
    }

    _socket = null;

    if (mounted && !_isDisposed) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
      });
    }
  }

  void _sendData() {
    if (!_isConnected || _socket == null) {
      _showError('未连接到服务器');
      return;
    }

    final String data = _sendController.text.trim();
    if (data.isEmpty) {
      _showError('请输入要发送的数据');
      return;
    }

    try {
      List<int> bytesToSend;

      if (_currentMode == SocketMode.hex) {
        bytesToSend = _hexToBytes(data);
        if (bytesToSend.isEmpty) {
          throw FormatException('无效的十六进制数据');
        }
      } else {
        if (_charset.toLowerCase() == 'utf-8') {
          bytesToSend = utf8.encode(data);
        } else {
          bytesToSend = gbk.encode(data);
        }
      }

      _socket!.add(bytesToSend);

      String displayData;
      if (_currentMode == SocketMode.hex) {
        displayData = '[HEX] ${_bytesToHex(bytesToSend)}';
      } else {
        displayData = data;
      }

      _logToBuffer(
          '${_getTimestamp()} 发送 (${bytesToSend.length}字节): $displayData');

      _totalSent += bytesToSend.length;

      if (mounted && !_isDisposed) {
        setState(() {
          _sendController.clear();
        });
      }
    } catch (e) {
      _logToBuffer('${_getTimestamp()} 发送失败: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = '发送失败: $e';
        });
      }
    }
  }

  void _logToBuffer(String message) {
    if (!mounted || _isDisposed) return;

    _receiveBuffer.add(message);

    if (_receiveBuffer.length > 1000) {
      _receiveBuffer.removeAt(0);
    }

    setState(() {
      _receiveController.text = _receiveBuffer.join('\n');
    });

    if (_autoScroll) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_receiveScrollController.hasClients && mounted && !_isDisposed) {
          _receiveScrollController.animateTo(
            _receiveScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _clearReceive() {
    if (!mounted || _isDisposed) return;

    setState(() {
      _receiveBuffer.clear();
      _receiveController.clear();
    });
  }

  String _getTimestamp() {
    final now = DateTime.now();
    return '[${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}]';
  }

  void _showError(String message) {
    if (!mounted || _isDisposed) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  Widget _buildModeSelectionCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '工作模式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (!_isConnected) {
                        setState(() {
                          _currentMode = SocketMode.hex;
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _currentMode == SocketMode.hex
                          ? colorScheme.primaryContainer
                          : null,
                      side: BorderSide(
                        color: _currentMode == SocketMode.hex
                            ? colorScheme.primary
                            : colorScheme.outline,
                        width: _currentMode == SocketMode.hex ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.code,
                          color: _currentMode == SocketMode.hex
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'HEX模式',
                          style: TextStyle(
                            color: _currentMode == SocketMode.hex
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: _currentMode == SocketMode.hex
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (!_isConnected) {
                        setState(() {
                          _currentMode = SocketMode.text;
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _currentMode == SocketMode.text
                          ? colorScheme.primaryContainer
                          : null,
                      side: BorderSide(
                        color: _currentMode == SocketMode.text
                            ? colorScheme.primary
                            : colorScheme.outline,
                        width: _currentMode == SocketMode.text ? 2 : 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.text_fields,
                          color: _currentMode == SocketMode.text
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '文本模式',
                          style: TextStyle(
                            color: _currentMode == SocketMode.text
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: _currentMode == SocketMode.text
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_currentMode == SocketMode.text) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('编码格式:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isConnected
                              ? colorScheme.outline.withOpacity(0.5)
                              : colorScheme.outline,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: _charset,
                        isExpanded: true,
                        underline: Container(),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        borderRadius: BorderRadius.circular(12),
                        onChanged: _isConnected
                            ? null
                            : (value) {
                                if (value != null && mounted && !_isDisposed) {
                                  setState(() {
                                    _charset = value;
                                  });
                                }
                              },
                        items: const [
                          DropdownMenuItem(
                            value: 'utf-8',
                            child: Text('UTF-8'),
                          ),
                          DropdownMenuItem(
                            value: 'gbk',
                            child: Text('GBK'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '连接设置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'IP地址',
                hintText: '例如: 127.0.0.1',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                prefixIcon: const Icon(Icons.computer),
              ),
              enabled: !_isConnecting && !_isConnected,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: '端口号',
                hintText: '例如: 8080',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                prefixIcon: const Icon(Icons.numbers),
              ),
              enabled: !_isConnecting && !_isConnected,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _autoReconnect,
                  onChanged: _isConnected
                      ? null
                      : (value) {
                          if (mounted && !_isDisposed) {
                            setState(() {
                              _autoReconnect = value ?? false;
                            });
                          }
                        },
                ),
                const Text('自动重连'),
                const Spacer(),
                Checkbox(
                  value: _autoScroll,
                  onChanged: (value) {
                    if (mounted && !_isDisposed) {
                      setState(() {
                        _autoScroll = value ?? true;
                      });
                    }
                  },
                ),
                const Text('自动滚动'),
              ],
            ),
            const SizedBox(height: 12),
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnected ? _disconnect : _connect,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: _isConnected
                            ? colorScheme.error
                            : colorScheme.primary,
                      ),
                      foregroundColor: _isConnected
                          ? colorScheme.error
                          : colorScheme.primary,
                    ),
                    icon: _isConnecting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  colorScheme.primary),
                            ),
                          )
                        : Icon(
                            _isConnected ? Icons.stop : Icons.play_arrow,
                          ),
                    label: Text(
                      _isConnecting
                          ? '连接中...'
                          : _isConnected
                              ? '断开连接'
                              : '开始连接',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '发送数据',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '已发送: ${_formatBytes(_totalSent)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.surfaceContainer,
              ),
              child: TextField(
                controller: _sendController,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: _currentMode == SocketMode.hex
                      ? '输入十六进制数据，例如: 48 65 6C 6C 6F (空格可选)'
                      : '输入要发送的文本',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
                enabled: _isConnected,
                style: const TextStyle(fontFamily: 'maple'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isConnected ? _sendData : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text(
                      '发送数据',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (mounted && !_isDisposed) {
                        setState(() {
                          _sendController.clear();
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary),
                    ),
                    icon: const Icon(Icons.clear),
                    label: const Text(
                      '清空',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivePanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '接收数据',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '已接收: ${_formatBytes(_totalReceived)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 120,
              constraints: const BoxConstraints(
                minWidth: double.infinity,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.surfaceContainer,
              ),
              child: Scrollbar(
                controller: _receiveScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _receiveScrollController,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width,
                      minHeight: 120,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _receiveController.text,
                        style: const TextStyle(
                          fontFamily: 'maple',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearReceive,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: colorScheme.primary,
                      side: BorderSide(color: colorScheme.primary),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清空接收区'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TCP Socket调试'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLandscape
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildModeSelectionCard(),
                          const SizedBox(height: 16),
                          _buildConnectionPanel(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: Column(
                              children: [
                                _buildSendPanel(),
                                const SizedBox(height: 16),
                                _buildReceivePanel(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeSelectionCard(),
                    const SizedBox(height: 16),
                    _buildConnectionPanel(),
                    const SizedBox(height: 16),
                    _buildSendPanel(),
                    const SizedBox(height: 16),
                    _buildReceivePanel(),
                  ],
                ),
              ),
      ),
    );
  }
}
