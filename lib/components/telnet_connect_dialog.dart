import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/telnet_connection_model.dart';
import '../services/telnet_service.dart';
import '../services/telnet_storage_service.dart';
import '../pages/telnet_terminal.dart';

class TelnetConnectDialog extends StatefulWidget {
  final TelnetConnectionInfo? connection;
  final bool isNewConnection;

  const TelnetConnectDialog({
    super.key,
    this.connection,
    this.isNewConnection = false,
  });

  @override
  State<TelnetConnectDialog> createState() => _TelnetConnectDialogState();
}

class _TelnetConnectDialogState extends State<TelnetConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '23');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _telnetStorageService = TelnetStorageService();

  TelnetTerminalType _selectedTerminalType = TelnetTerminalType.xterm;
  TelnetLineSeparator _selectedLineSeparator = TelnetLineSeparator.crlf;
  bool _rememberConnection = true;
  bool _isConnecting = false;
  bool _isEditing = false;
  bool _showPassword = false;
  TelnetEncoding _selectedEncoding = TelnetEncoding.utf8;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.connection != null;

    if (_isEditing) {
      _nameController.text = widget.connection!.name;
      _hostController.text = widget.connection!.host;
      _portController.text = widget.connection!.port.toString();
      _usernameController.text = widget.connection!.username ?? '';
      _passwordController.text = widget.connection!.password ?? '';
      _rememberConnection = widget.connection!.remember;
      _selectedTerminalType = widget.connection!.terminalType;
      _selectedLineSeparator = widget.connection!.lineSeparator;
      _selectedEncoding = widget.connection!.encoding;
    } else {
      _nameController.text = 'Telnet连接';
      _selectedEncoding = TelnetEncoding.gbk;
    }
  }

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      final connection = TelnetConnectionInfo(
        id: widget.connection?.id ?? const Uuid().v4(),
        name: _nameController.text,
        host: _hostController.text,
        port: int.parse(_portController.text),
        username: _usernameController.text.isNotEmpty
            ? _usernameController.text
            : null,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        remember: _rememberConnection,
        terminalType: _selectedTerminalType,
        lineSeparator: _selectedLineSeparator,
        encoding: _selectedEncoding,
      );

      await _telnetStorageService.saveConnection(connection);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Telnet连接已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _connectNow() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
    });

    final connection = TelnetConnectionInfo(
      id: const Uuid().v4(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.parse(_portController.text),
      username: _usernameController.text.isNotEmpty
          ? _usernameController.text
          : null,
      password: _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
      remember: _rememberConnection,
      terminalType: _selectedTerminalType,
      lineSeparator: _selectedLineSeparator,
      encoding: _selectedEncoding,
    );

    final testService = TelnetService();

    try {
      await testService.connect(connection);
      await Future.delayed(const Duration(milliseconds: 500));
      testService.disconnect();

      if (_rememberConnection) {
        await _telnetStorageService.saveConnection(connection);
      }

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TelnetTerminalPage(connection: connection),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text('无法连接到Telnet服务器: $e'),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  // 统一的文本框样式
  InputDecoration _textFieldDecoration(
    String labelText, {
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 1.0,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.red, width: 1.0),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // 统一的下拉菜单样式
  InputDecoration _dropdownDecoration(String labelText) {
    return InputDecoration(
      labelText: labelText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 1.0,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '编辑Telnet连接' : '新建Telnet连接',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isConnecting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 7),
                        TextFormField(
                          controller: _nameController,
                          decoration: _textFieldDecoration(
                            '连接名称',
                            hintText: '请输入连接名称',
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? '请输入连接名称'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _hostController,
                          decoration: _textFieldDecoration(
                            '主机地址',
                            hintText: '例如：192.168.1.1',
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? '请输入主机地址'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _portController,
                          decoration: _textFieldDecoration('端口号'),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请输入端口号';
                            final port = int.tryParse(value);
                            if (port == null || port <= 0 || port > 65535)
                              return '请输入有效的端口号';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          decoration: _textFieldDecoration(
                            '用户名 (可选)',
                            hintText: '如果需要认证请输入用户名',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: _textFieldDecoration(
                            '密码 (可选)',
                            hintText: '如果需要认证请输入密码',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                            ),
                          ),
                          obscureText: !_showPassword,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<TelnetTerminalType>(
                          value: _selectedTerminalType,
                          decoration: _dropdownDecoration('终端类型'),
                          items: TelnetTerminalType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => _selectedTerminalType = value!),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<TelnetLineSeparator>(
                          initialValue: _selectedLineSeparator,
                          decoration: _dropdownDecoration('行分隔符'),
                          items: TelnetLineSeparator.values.map((separator) {
                            return DropdownMenuItem(
                              value: separator,
                              child: Text(separator.displayName),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => _selectedLineSeparator = value!),
                        ),
                        const SizedBox(height: 16),
                        // 添加编码选择下拉菜单
                        DropdownButtonFormField<TelnetEncoding>(
                          value: _selectedEncoding,
                          decoration: _dropdownDecoration('字符编码'),
                          items: TelnetEncoding.values.map((encoding) {
                            return DropdownMenuItem(
                              value: encoding,
                              child: Text(encoding.displayName),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => _selectedEncoding = value!),
                        ),
                        const SizedBox(height: 16),
                        // 将"保存此连接"改为SwitchListTile样式
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('保存此连接'),
                          subtitle: const Text('将此连接保存到连接列表'),
                          value: _rememberConnection,
                          onChanged: (value) {
                            setState(() {
                              _rememberConnection = value;
                            });
                          },
                          secondary: const Icon(Icons.bookmark),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isConnecting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isConnecting
                          ? null
                          : _isEditing
                          ? _saveConnection
                          : _connectNow,
                      child: _isConnecting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEditing ? '保存' : '连接'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
