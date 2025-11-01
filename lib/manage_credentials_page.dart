// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'models/credential_model.dart';
import 'services/storage_service.dart';

class ManageCredentialsPage extends StatefulWidget {
  const ManageCredentialsPage({super.key});

  @override
  State<ManageCredentialsPage> createState() => _ManageCredentialsPageState();
}

class _ManageCredentialsPageState extends State<ManageCredentialsPage> {
  final _storageService = StorageService();
  List<Credential> _credentials = [];

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await _storageService.getCredentials();
    setState(() {
      _credentials = credentials;
    });
  }

  void _showAddCredentialDialog() {
    showDialog(
      context: context,
      builder: (context) => CredentialDialog(
        onSaved: _loadCredentials,
      ),
    );
  }

  void _editCredential(Credential credential) {
    showDialog(
      context: context,
      builder: (context) => CredentialDialog(
        credential: credential,
        onSaved: _loadCredentials,
      ),
    );
  }

  void _deleteCredential(Credential credential) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除凭证'),
        content: Text('确定要删除凭证 "${credential.name}" 吗？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              await _storageService.deleteCredential(credential.id);
              if (mounted) {
                _loadCredentials(); // 重新加载列表
              }
              Navigator.of(context).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理认证凭证'),
        actions: [
          IconButton(
            onPressed: _showAddCredentialDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _credentials.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.vpn_key_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无认证凭证', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 8),
                  Text(
                    '点击右上角 + 按钮添加新的认证凭证',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _credentials.length,
              itemBuilder: (context, index) {
                final credential = _credentials[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    title: Text(
                      credential.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('用户名: ${credential.username}'),
                        const SizedBox(height: 2),
                        Text(
                          '认证方式: ${_getAuthTypeText(credential.authType)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editCredential(credential),
                          icon: const Icon(Icons.edit),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          onPressed: () => _deleteCredential(credential),
                          icon: const Icon(Icons.delete),
                          tooltip: '删除',
                        ),
                      ],
                    ),
                    onTap: () => _editCredential(credential),
                  ),
                );
              },
            ),
    );
  }

  String _getAuthTypeText(AuthType authType) {
    switch (authType) {
      case AuthType.password:
        return '密码认证';
      case AuthType.privateKey:
        return '私钥认证';
      case AuthType.passphrase:
        return '密码短语认证';
    }
  }
}

class CredentialDialog extends StatefulWidget {
  final Credential? credential;
  final VoidCallback? onSaved;

  const CredentialDialog({
    super.key,
    this.credential,
    this.onSaved,
  });

  @override
  State<CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<CredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _passphraseController = TextEditingController();

  final _storageService = StorageService();
  AuthType _authType = AuthType.password;
  bool _isEditing = false;
  bool _obscurePassword = true;
  bool _obscurePassphrase = true;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.credential != null;
    
    if (_isEditing) {
      _nameController.text = widget.credential!.name;
      _usernameController.text = widget.credential!.username;
      _authType = widget.credential!.authType;
      _passwordController.text = widget.credential!.password ?? '';
      _privateKeyController.text = widget.credential!.privateKey ?? '';
      _passphraseController.text = widget.credential!.passphrase ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _pickPrivateKeyFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'key', 'ppk', 'txt'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);
        final keyContent = await file.readAsString();
        setState(() {
          _privateKeyController.text = keyContent;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已从文件加载私钥: ${result.files.single.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('读取文件失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearPrivateKey() {
    setState(() {
      _privateKeyController.clear();
    });
  }

  Future<void> _saveCredential() async {
    if (!_formKey.currentState!.validate()) return;

    final credential = Credential(
      id: widget.credential?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      username: _usernameController.text.trim(),
      authType: _authType,
      password: _authType == AuthType.password ? _passwordController.text : null,
      privateKey: _authType == AuthType.privateKey ? _privateKeyController.text : null,
      passphrase: _authType == AuthType.privateKey ? _passphraseController.text : null,
    );

    try {
      await _storageService.saveCredential(credential);
      
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved?.call();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? '凭证已更新' : '凭证已创建'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _validatePrivateKey(String? value) {
    if (_authType == AuthType.privateKey && (value == null || value.isEmpty)) {
      return '请输入私钥内容';
    }
    
    if (value != null && value.isNotEmpty) {
      // 简单的私钥格式验证
      if (!value.contains('-----BEGIN') && !value.contains('PRIVATE KEY')) {
        return '私钥格式可能不正确';
      }
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // 固定对话框宽度
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500, // 设置最大宽度
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '编辑凭证' : '添加凭证',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
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
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: '凭证名称',
                            hintText: '输入凭证的显示名称',

                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入凭证名称';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            hintText: '输入登录用户名',

                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入用户名';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      
                        DropdownButtonFormField<AuthType>(
                          value: _authType,
                          decoration: const InputDecoration(
                            labelText: '认证方式',

                          ),
                          items: const [
                            DropdownMenuItem(
                              value: AuthType.password,
                              child: Text('密码认证'),
                            ),
                            DropdownMenuItem(
                              value: AuthType.privateKey,
                              child: Text('私钥认证'),
                            ),
                          ],
                          onChanged: (AuthType? value) {
                            if (value != null) {
                              setState(() {
                                _authType = value;
                              });
                            }
                          },
                          validator: (value) {
                            if (value == null) {
                              return '请选择认证方式';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        if (_authType == AuthType.password)
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: '密码',
                              hintText: '输入登录密码',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            validator: (value) {
                              if (_authType == AuthType.password && 
                                  (value == null || value.isEmpty)) {
                                return '请输入密码';
                              }
                              return null;
                            },
                          )
                        else
                          Column(
                            children: [
                              TextFormField(
                                controller: _privateKeyController,
                                decoration: const InputDecoration(
                                  labelText: '私钥内容',
                                  hintText: '粘贴私钥内容或从文件读取',
      
                                  alignLabelWithHint: true,
                                ),
                                maxLines: 6,
                                minLines: 4,
                                textInputAction: TextInputAction.next,
                                validator: _validatePrivateKey,
                              ),
                              const SizedBox(height: 12),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickPrivateKeyFile,
                                      icon: const Icon(Icons.file_open, size: 18),
                                      label: const Text('从文件读取'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _clearPrivateKey,
                                      icon: const Icon(Icons.clear, size: 18),
                                      label: const Text('清空内容'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              TextFormField(
                                controller: _passphraseController,
                                decoration: InputDecoration(
                                  labelText: '私钥密码 (可选)',
                                  hintText: '如果私钥有密码保护，请在此输入',
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassphrase ? Icons.visibility : Icons.visibility_off,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassphrase = !_obscurePassphrase;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscurePassphrase,
                                textInputAction: TextInputAction.done,
                              ),
                            ],
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saveCredential,
                      child: const Text('保存'),
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