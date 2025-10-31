import 'package:flutter/material.dart';
import 'manage_credentials_page.dart';
import 'package:uuid/uuid.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'terminal_page.dart';
import 'sftp_page.dart';

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
  final _storageService = StorageService();
  final _sshService = SshService();

  List<Credential> _credentials = [];
  Credential? _selectedCredential;
  ConnectionType _selectedType = ConnectionType.ssh;
  bool _rememberConnection = false;
  bool _isConnecting = false;
  bool _isEditing = false;
  bool _isNameChanged = false;

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
    } else {
      _nameController.text = '新连接';
      _isNameChanged = false;
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
    if (!_isEditing && (_hostController.text.isNotEmpty || _portController.text.isNotEmpty)) {
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
    showDialog(context: context, builder: (context) => CredentialDialog(
      onSaved: () {
        _loadCredentials().then((_) {
          if(_credentials.isNotEmpty) {
            setState(() {
              _selectedCredential =_credentials.last;
            });
          }
        });
      },
    ));
  }

  Future<void> _connectToServer() async {
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
        name: _nameController.text,
        host: _hostController.text,
        port: int.parse(_portController.text),
        credentialId: _selectedCredential!.id,
        type: _selectedType,
        remember: _rememberConnection,
      );

      await _sshService.connect(connection, _selectedCredential!);
      await _storageService.addRecentConnection(connection);

      if (_rememberConnection || _isEditing) {
        await _storageService.saveConnection(connection);
      }

      if (mounted) {
        Navigator.of(context).pop();
        if (_selectedType == ConnectionType.sftp) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SftpPage(
                connection: connection,
                credential: _selectedCredential!,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TerminalPage(
                connection: connection,
                credential: _selectedCredential!,
              ),
            ),
          );
        }
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

  // 新增：仅保存连接而不连接
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
              _connectToServer();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_getDialogTitle()),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '连接名称',
                  hintText: '请输入连接名称',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh_outlined),
                    onPressed: () {
                        _reserToDefaultName();
                      },
                    ),
                ),
                onChanged: (value) {
                  if(!_isEditing) {
                    setState(() {
                      _isNameChanged = true;
                    });
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入连接名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '主机地址',
                  hintText: '例如：192.168.1.1',
                ),
                onChanged: !_isEditing ? (value) => _generateConnectionName() : null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入主机地址';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口号',
                ),
                keyboardType: TextInputType.number,
                onChanged: !_isEditing ? (value) => _generateConnectionName() : null,
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
              
              if (!widget.isNewConnection && !_isEditing)
                CheckboxListTile(
                  title: const Text('记住该连接'),
                  value: _rememberConnection,
                  onChanged: (value) {
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
          onPressed: _isConnecting ? null : () {
            if (widget.isNewConnection) {
              _saveConnectionOnly();
            } else if (_isEditing) {
              _updateConnection();
            } else {
              _connectToServer(); 
            }
          },
          child: _isConnecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_getActionButtonText()),
        ),
      ],
    );
  }
}