// quick_connect_dialog.dart
import 'dart:async';

import 'package:flutter/material.dart';
import '../pages/manage_credentials.dart';
import 'package:uuid/uuid.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/storage_service.dart';
import '../pages/terminal.dart';
import '../pages/sftpview.dart';
import 'telnet_connect_dialog.dart';

class QuickConnectDialog extends StatefulWidget {
  final ConnectionInfo? connection;
  final bool isNewConnection;

  const QuickConnectDialog({
    super.key,
    this.connection,
    this.isNewConnection = false,
  });

  @override
  State<QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<QuickConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _sftpPathController = TextEditingController();
  final _storageService = StorageService();

  List<Credential> _credentials = [];
  Credential? _selectedCredential;
  ConnectionType _selectedType = ConnectionType.ssh;
  bool _rememberConnection = false;
  bool _isConnecting = false;
  bool _isEditing = false;
  bool _isNameChanged = false;
  bool _needTwoFa = false; // 新增：是否需要2FA

  @override
  void initState() {
    super.initState();
    _isEditing = widget.connection != null;

    if (_isEditing) {
      _nameController.text = widget.connection!.name;
      _hostController.text = widget.connection!.host;
      _portController.text = widget.connection!.port.toString();
      _selectedType = widget.connection!.type;
      _rememberConnection = widget.connection!.remember;
      _sftpPathController.text = widget.connection!.sftpPath ?? '/';
      _needTwoFa = widget.connection!.needTwoFa; // 读取2FA设置
    } else {
      _nameController.text = '新连接';
      _sftpPathController.text = '/';
      _isNameChanged = false;
      _needTwoFa = false; // 默认不启用2FA
    }

    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await _storageService.getCredentials();
    setState(() {
      _credentials = credentials;
    });

    if (_isEditing && _credentials.isNotEmpty) {
      final connectionCredentialId = widget.connection!.credentialId;
      final credential = _credentials.firstWhere(
        (c) => c.id == connectionCredentialId,
        orElse: () => _credentials.first,
      );
      setState(() {
        _selectedCredential = credential;
      });
    } else if (_credentials.isNotEmpty) {
      setState(() {
        _selectedCredential = _credentials.first;
      });
    }
  }

  void _generateConnectionName() {
    if (_isNameChanged) return;

    if (_hostController.text.isNotEmpty || _portController.text.isNotEmpty) {
      final host = _hostController.text;
      final port = _portController.text;
      if (host.isNotEmpty) {
        setState(() {
          _nameController.text = '$host:$port';
        });
      }
    }
  }

  void _reserToDefaultName() {
    setState(() {
      _isNameChanged = false;
    });
    _generateConnectionName();
  }

  void _addNewCredential() {
    showDialog(
        context: context,
        builder: (context) => CredentialDialog(
              onSaved: () {
                _loadCredentials().then((_) {
                  if (_credentials.isNotEmpty) {
                    setState(() {
                      _selectedCredential = _credentials.last;
                    });
                  }
                });
              },
            ));
  }

  void _connectToServer(ConnectionInfo connection) async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          backgroundColor: Colors.transparent,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('正在测试连接...'),
            ],
          ),
        );
      },
    );

    try {
      final storageService = StorageService();

      final credentials = await storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      unawaited(storageService.addRecentConnection(connection));
      if (connection.remember) {
        await storageService.saveConnection(connection);
      }
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop();
      }

      if (mounted) {
        if (connection.type == ConnectionType.sftp) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SftpPage(
                connection: connection,
                credential: credential,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TerminalPage(
                connection: connection,
                credential: credential,
              ),
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(e.message ?? '连接超时'),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('连接失败'),
            content: Text(e.toString()),
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

  Future<void> _updateConnection() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCredential == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择认证凭证')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final connection = ConnectionInfo(
        id: widget.connection!.id,
        name: _nameController.text,
        host: _hostController.text,
        port: int.parse(_portController.text),
        credentialId: _selectedCredential!.id,
        type: _selectedType,
        remember: true,
        needTwoFa: _needTwoFa, // 保存2FA设置
        sftpPath: _selectedType == ConnectionType.sftp
            ? _sftpPathController.text
            : null,
      );

      await _storageService.saveConnection(connection);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接信息已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败: $e')),
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

  Future<void> _saveConnectionOnly() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCredential == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择认证凭证')),
      );
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final connection = ConnectionInfo(
        id: const Uuid().v4(),
        name: _nameController.text,
        host: _hostController.text,
        port: int.parse(_portController.text),
        credentialId: _selectedCredential!.id,
        type: _selectedType,
        remember: true,
        needTwoFa: _needTwoFa, // 保存2FA设置
        sftpPath: _selectedType == ConnectionType.sftp
            ? _sftpPathController.text
            : null,
      );

      await _storageService.saveConnection(connection);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
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

  String _getDialogTitle() {
    if (widget.isNewConnection) return '新建连接';
    if (_isEditing) return '编辑连接';
    return '快速连接';
  }

  String _getActionButtonText() {
    if (widget.isNewConnection) return '保存';
    if (_isEditing) return '更新';
    return '连接';
  }

  void _showTelnetDialog() {
    Navigator.of(context).pop(); // 关闭当前对话框
    showDialog(
      context: context,
      builder: (context) => const TelnetConnectDialog(),
    );
  }

  // 统一的文本框样式
  InputDecoration _textFieldDecoration(String labelText,
      {String? hintText, Widget? suffixIcon}) {
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
        borderSide:
            BorderSide(color: Theme.of(context).primaryColor, width: 1.0),
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
        borderSide:
            BorderSide(color: Theme.of(context).primaryColor, width: 1.0),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
        ),
        child: Padding(
          padding: const EdgeInsets.only(
              left: 16, right: 16, bottom: 16, top: 16), // 移除顶部内边距
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _getDialogTitle(),
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
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh_outlined),
                              onPressed: _reserToDefaultName,
                            ),
                          ),
                          onChanged: (value) =>
                              setState(() => _isNameChanged = true),
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
                          onChanged: !_isEditing
                              ? (value) => _generateConnectionName()
                              : null,
                          validator: (value) => (value == null || value.isEmpty)
                              ? '请输入主机地址'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _portController,
                          decoration: _textFieldDecoration('端口号'),
                          keyboardType: TextInputType.number,
                          onChanged: !_isEditing
                              ? (value) => _generateConnectionName()
                              : null,
                          validator: (value) {
                            if (value == null || value.isEmpty) return '请输入端口号';
                            final port = int.tryParse(value);
                            if (port == null || port <= 0 || port > 65535)
                              return '请输入有效的端口号';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // 问题2：修复凭证选择行，让+号按钮垂直居中
                        SizedBox(
                          height: 60, // 设置固定高度确保垂直居中
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<Credential>(
                                  value: _selectedCredential,
                                  decoration: _dropdownDecoration('认证凭证'),
                                  items: _credentials.map((credential) {
                                    return DropdownMenuItem(
                                      value: credential,
                                      child: Text(credential.name),
                                    );
                                  }).toList(),
                                  onChanged: (value) => setState(
                                      () => _selectedCredential = value),
                                  validator: (value) =>
                                      value == null ? '请选择认证凭证' : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 48, // 与下拉菜单高度匹配
                                width: 48, // 确保圆形按钮
                                child: IconButton(
                                  onPressed: _addNewCredential,
                                  icon: const Icon(Icons.add),
                                  tooltip: '添加新凭证',
                                  padding: const EdgeInsets.all(12), // 增加内边距
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(context)
                                        .primaryColor
                                        .withOpacity(0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(
                                          color: Colors.grey, width: 1),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<ConnectionType>(
                          value: _selectedType,
                          decoration: _dropdownDecoration('连接类型'),
                          items: ConnectionType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.displayName),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => _selectedType = value!),
                        ),
                        if (_selectedType == ConnectionType.sftp) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _sftpPathController,
                            decoration: _textFieldDecoration(
                              'SFTP默认访问目录',
                              hintText: '例如：/home/username',
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? '请输入SFTP默认路径'
                                    : null,
                          ),
                          const SizedBox(height: 8),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '此目录将覆盖全局SFTP默认路径设置',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        // 修改：将2FA选项移到SFTP路径下方
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('启用2FA认证'),
                          subtitle: const Text('如需双因素认证请启用此选项'),
                          value: _needTwoFa,
                          onChanged: (value) {
                            setState(() {
                              _needTwoFa = value;
                            });
                          },
                          secondary: const Icon(Icons.security),
                        ),
                        const SizedBox(height: 8),
                        // 修改：将"记住该连接"改为SwitchListTile样式
                        if (!widget.isNewConnection && !_isEditing)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('记住该连接'),
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
                        onPressed: _isConnecting ? null : _showTelnetDialog,
                        child: const Text('Telnet')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isConnecting
                          ? null
                          : () {
                              if (widget.isNewConnection) {
                                _saveConnectionOnly();
                              } else if (_isEditing) {
                                _updateConnection();
                              } else {
                                final connection = ConnectionInfo(
                                  id: const Uuid().v4(),
                                  name: _nameController.text,
                                  host: _hostController.text,
                                  port: int.parse(_portController.text),
                                  credentialId: _selectedCredential!.id,
                                  type: _selectedType,
                                  remember: _rememberConnection,
                                  needTwoFa: _needTwoFa, // 保存2FA设置
                                  sftpPath: _selectedType == ConnectionType.sftp
                                      ? _sftpPathController.text
                                      : null,
                                );
                                _connectToServer(connection);
                              }
                            },
                      child: _isConnecting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_getActionButtonText()),
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
