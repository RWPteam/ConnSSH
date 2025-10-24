import 'package:flutter/material.dart';
import 'package:t_samuioto_ssh/manage_credentials_page.dart';
import 'package:uuid/uuid.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'terminal_page.dart';


class QuickConnectDialog extends StatefulWidget {
  final ConnectionInfo? connection; 

  const QuickConnectDialog({super.key, this.connection});

  @override
  State<QuickConnectDialog> createState() => _QuickConnectDialogState();
}

class _QuickConnectDialogState extends State<QuickConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _storageService = StorageService();
  final _sshService = SshService();

  List<Credential> _credentials = [];
  Credential? _selectedCredential;
  ConnectionType _selectedType = ConnectionType.ssh;
  bool _rememberConnection = false;
  bool _isConnecting = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.connection != null;
    
    if (_isEditing) {
      _hostController.text = widget.connection!.host;
      _portController.text = widget.connection!.port.toString();
      _selectedType = widget.connection!.type;
      _rememberConnection = widget.connection!.remember;
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
    }
  }

  Future<void> _connect() async {
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
        id: widget.connection?.id ?? const Uuid().v4(),
        name: '${_hostController.text}:${_portController.text}',
        host: _hostController.text,
        port: int.parse(_portController.text),
        credentialId: _selectedCredential!.id,
        type: _selectedType,
        remember: _rememberConnection,
      );

      await _sshService.connect(connection, _selectedCredential!);

      if (_rememberConnection || _isEditing) {
        await _storageService.saveConnection(connection);
      }

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TerminalPage(
              connection: connection,
              credential: _selectedCredential!,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showConnectionError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  void _showConnectionError(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接失败'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _connect();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _addNewCredential() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManageCredentialsPage(),
      ),
    ).then((_) => _loadCredentials());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? '编辑连接' : '快速连接'), 
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主机地址
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '主机地址',
                  hintText: '例如：192.168.1.1',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入主机地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // 端口号
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口号',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入端口号';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port <= 0 || port > 65535) {
                    return '请输入有效的端口号';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // 认证凭证选择
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Credential>(
                      value: _selectedCredential,
                      decoration: const InputDecoration(
                        labelText: '认证凭证',
                      ),
                      items: [
                        ..._credentials.map((credential) {
                          return DropdownMenuItem(
                            value: credential,
                            child: Text(credential.name),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCredential = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return '请选择认证凭证';
                        }
                        return null;
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: _addNewCredential,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // 连接类型 - 修复默认值问题
              DropdownButtonFormField<ConnectionType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: '连接类型',
                ),
                items: ConnectionType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              
              CheckboxListTile(
                title: const Text('记住该连接'),
                value: _isEditing ? true : _rememberConnection, 
                onChanged: _isEditing 
                    ? null 
                    : (value) {
                        setState(() {
                          _rememberConnection = value!;
                        });
                      },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isConnecting ? null : _connect,
          child: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? '更新' : '连接'),
        ),
      ],
    );
  }
}