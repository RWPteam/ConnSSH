import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:dartssh2/dartssh2.dart';
import 'models/connection_model.dart';
import 'services/rsa_key_service.dart';
import 'services/ecdsa_key_service.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'components/quick_connect_dialog.dart';

class KeygenPage extends StatefulWidget {
  const KeygenPage({super.key});

  @override
  State<KeygenPage> createState() => _KeygenPageState();
}

class _KeygenPageState extends State<KeygenPage> {
  final StorageService _storageService = StorageService();
  final SshService _sshService = SshService();

  int _keySize = 2048;
  String _keyFormat = 'pkcs8';
  String _keyAlgorithm = 'rsa';
  String _ecdsaCurve = 'p256';

  String? _privateKey;
  String? _publicKey;

  List<ConnectionInfo> _savedConnections = [];
  bool _isUploading = false;
  String _uploadStatus = '';
  SSHClient? _sshClient;
  dynamic _sftpClient;

  bool _isGenerating = false;
  final TextEditingController _passwordController = TextEditingController();

  final List<int> _rsaKeySizeOptions = [512, 1024, 2048, 4096];
  final List<String> _ecdsaCurveOptions = [
    'p192',
    'p224',
    'p256',
    'p384',
    'p521'
  ];

  final List<String> _formatOptions = ['pkcs1', 'pkcs8'];

  final List<String> _algorithmOptions = ['RSA', 'ECDSA'];

  @override
  void initState() {
    super.initState();
    _loadSavedConnections();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _sshClient?.close();
    super.dispose();
  }

  List<dynamic> get _currentKeyOptions {
    if (_keyAlgorithm == 'rsa') {
      return _rsaKeySizeOptions;
    } else {
      return _ecdsaCurveOptions;
    }
  }

  String _getKeySizeLabel(dynamic option) {
    if (_keyAlgorithm == 'rsa') {
      return '$option 位';
    } else {
      return option.toUpperCase();
    }
  }

  Future<void> _loadSavedConnections() async {
    try {
      final connections = await _storageService.getConnections();
      setState(() {
        _savedConnections = connections;
      });
    } catch (e) {
      _showError('加载已保存连接失败: $e');
    }
  }

  Future<void> _generateKeyPair() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _privateKey = null;
      _publicKey = null;
    });

    try {
      String privateKey;
      String publicKey;

      if (_keyAlgorithm == 'rsa') {
        final keyPair = RSAKeyService.generateKeyPair(_keySize);
        final privateKeyObj = keyPair['private'] as RSAPrivateKey;
        final publicKeyObj = keyPair['public'] as RSAPublicKey;

        if (_keyFormat == 'pkcs8') {
          privateKey = RSAKeyService.encodePrivateKeyToPemPKCS8(privateKeyObj);
        } else {
          privateKey = RSAKeyService.encodePrivateKeyToPemPKCS1(privateKeyObj);
        }

        publicKey = RSAKeyService.encodePublicKeyToPem(publicKeyObj);
      } else {
        final keyPair = ECDSAKeyService.generateKeyPair(_ecdsaCurve);
        final privateKeyObj = keyPair['private'] as ECPrivateKey;
        final publicKeyObj = keyPair['public'] as ECPublicKey;

        privateKey = ECDSAKeyService.encodePrivateKeyToPemPKCS8(
          privateKeyObj,
          _ecdsaCurve,
        );

        publicKey = ECDSAKeyService.encodePublicKeyToPem(
          publicKeyObj,
          _ecdsaCurve,
        );

        ECDSAKeyService.encodePublicKeyToOpenSSH(
          publicKeyObj,
          _ecdsaCurve,
        );
      }

      if (_passwordController.text.isNotEmpty) {
        if (_keyAlgorithm == 'rsa') {
          privateKey = RSAKeyService.encryptPrivateKeyWithPassword(
            privateKey,
            _passwordController.text,
          );
        } else {
          privateKey = ECDSAKeyService.encryptPrivateKeyWithPassword(
            privateKey,
            _passwordController.text,
          );
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _privateKey = privateKey;
        _publicKey = publicKey;
        _isGenerating = false;
      });

      final algoName = _keyAlgorithm.toUpperCase();
      _showSuccess('$algoName密钥对生成成功');
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });
      _showError('密钥生成失败: $e');
    }
  }

  Future<void> _saveToLocal() async {
    if (_privateKey == null || _publicKey == null) {
      _showError('暂无生成的密钥对');
      return;
    }

    try {
      String baseName;
      if (_keyAlgorithm == 'rsa') {
        baseName = 'id_${_keyAlgorithm}_${_keySize}_${_keyFormat}';
      } else {
        baseName = 'id_${_keyAlgorithm}_${_ecdsaCurve}_${_keyFormat}';
      }

      final privateKeyFile = await getSaveLocation(
        suggestedName: baseName,
      );

      if (privateKeyFile != null) {
        final privatePath = privateKeyFile.path;
        final privateFile = File(privatePath);
        await privateFile.writeAsString(_privateKey!);

        final publicPath = privatePath + '.pub';
        final publicFile = File(publicPath);
        await publicFile.writeAsString(_publicKey!);

        _showSuccess('密钥已保存到:\n$privatePath\n$publicPath');
      }
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  Future<void> _showUploadDialog() async {
    if (_privateKey == null || _publicKey == null) {
      _showError('请先生成密钥对');
      return;
    }

    if (_savedConnections.isEmpty) {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('没有保存的服务器连接，请先连接'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('快速连接'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _showQuickConnectDialog();
        return;
      }
      return;
    }

    final Map<String, ConnectionInfo> uniqueConnections = {};
    for (var connection in _savedConnections) {
      final String key =
          '${connection.host}:${connection.port}:${connection.credentialId}';
      if (!uniqueConnections.containsKey(key)) {
        uniqueConnections[key] = connection;
      }
    }
    final deduplicatedConnections = uniqueConnections.values.toList();

    final selectedConnection = await showDialog<ConnectionInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择服务器'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: Colors.grey, width: 1.0),
                    color: Colors.transparent,
                  ),
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('快速连接'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showQuickConnectDialog();
                    },
                  ),
                ),
                ...deduplicatedConnections.map((connection) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: Colors.grey, width: 1.0),
                      color: Colors.transparent,
                    ),
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: ListTile(
                      leading: const Icon(Icons.computer),
                      title: Text(connection.name),
                      subtitle: Text('${connection.host}:${connection.port}'),
                      onTap: () => Navigator.of(context).pop(connection),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedConnection == null) return;

    final uploadPathController = TextEditingController(text: '/home');
    final pathResult = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择上传目录'),
        content: TextField(
          controller: uploadPathController,
          decoration: const InputDecoration(
            labelText: '上传路径',
            hintText: '请确保您对上传目录具有完全的访问权限',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(uploadPathController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (pathResult == null || pathResult.isEmpty) return;

    await _uploadToServer(selectedConnection, pathResult);
  }

  Future<void> _uploadToServer(ConnectionInfo connection, String path) async {
    setState(() {
      _isUploading = true;
      _uploadStatus = '连接服务器...';
    });

    try {
      final credentials = await _storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == connection.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      _sshClient = await _sshService.connect(connection, credential);
      _sftpClient = await _sshClient!.sftp();

      String expandedPath = path;
      if (path.startsWith('~')) {
        final session = await _sshClient!.execute('echo ~');
        final output = await session.stdout.join();
        expandedPath = path.replaceFirst('~', output.trim());
      }

      setState(() => _uploadStatus = '上传私钥...');

      String privateKeyPath;
      if (_keyAlgorithm == 'rsa') {
        privateKeyPath =
            '$expandedPath/id_${_keyAlgorithm}_${_keySize}_${_keyFormat}';
      } else {
        privateKeyPath =
            '$expandedPath/id_${_keyAlgorithm}_${_ecdsaCurve}_${_keyFormat}';
      }

      await _uploadFile(_privateKey!, privateKeyPath);

      setState(() => _uploadStatus = '上传公钥...');

      final publicKeyPath = '$privateKeyPath.pub';
      await _uploadFile(_publicKey!, publicKeyPath);

      setState(() => _uploadStatus = '设置权限...');
      final session = await _sshClient!.execute(
        'chmod 600 "$privateKeyPath" && chmod 644 "$publicKeyPath"',
      );
      await session.done;

      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });

      _showSuccess('密钥对已上传到服务器！\n私钥: $privateKeyPath\n公钥: $publicKeyPath');
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });
      _showError('上传失败: $e');
    } finally {
      _sshClient?.close();
      _sshClient = null;
    }
  }

  Future<void> _uploadFile(String content, String remotePath) async {
    final remoteFile = await _sftpClient.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    try {
      final bytes = utf8.encode(content);
      await remoteFile.writeBytes(bytes, offset: 0);
      await remoteFile.close();
    } catch (e) {
      await remoteFile.close();
      rethrow;
    }
  }

  Future<void> _showQuickConnectDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => const QuickConnectDialog(),
    );

    if (result == true) {
      await _loadSavedConnections();
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('已复制到剪贴板');
  }

  void _showError(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密钥生成'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '生成参数',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _keyAlgorithm,
                            decoration: InputDecoration(
                              labelText: '密钥算法',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _algorithmOptions.map((algorithm) {
                              return DropdownMenuItem(
                                value: algorithm.toLowerCase(),
                                child: Text(algorithm),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _keyAlgorithm = value;
                                  if (value == 'rsa') {
                                    _keySize = 2048;
                                  } else {
                                    _ecdsaCurve = 'p256';
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<dynamic>(
                            value:
                                _keyAlgorithm == 'rsa' ? _keySize : _ecdsaCurve,
                            decoration: InputDecoration(
                              labelText:
                                  _keyAlgorithm == 'rsa' ? '密钥长度' : '椭圆曲线',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _currentKeyOptions.map((option) {
                              return DropdownMenuItem(
                                value: option,
                                child: Text(_getKeySizeLabel(option)),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  if (_keyAlgorithm == 'rsa') {
                                    _keySize = value as int;
                                  } else {
                                    _ecdsaCurve = value as String;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _keyFormat,
                            decoration: InputDecoration(
                              labelText: '密钥格式',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              enabled: _keyAlgorithm == 'rsa',
                            ),
                            items: _formatOptions.map((format) {
                              return DropdownMenuItem(
                                value: format,
                                child: Text(format.toUpperCase()),
                              );
                            }).toList(),
                            onChanged: _keyAlgorithm == 'rsa'
                                ? (value) {
                                    if (value != null) {
                                      setState(() => _keyFormat = value);
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: '私钥密码（可选）',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        hintText: '为空则不设置密码保护',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      obscureText: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGenerating ? null : _generateKeyPair,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    icon: _isGenerating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : null,
                    label: Text(
                      _isGenerating ? '生成中...' : '生成',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUploading || _privateKey == null
                        ? null
                        : _showUploadDialog,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    icon: _isUploading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                            ),
                          )
                        : null,
                    label: const Text(
                      '上传',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _privateKey == null ? null : _saveToLocal,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                    ),
                    label: const Text(
                      '保存',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
            if (_uploadStatus.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _uploadStatus,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: _privateKey == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 64,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '请先生成密钥对',
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildKeyCard(
                            title: '私钥',
                            keyContent: _privateKey!,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildKeyCard(
                            title: '公钥',
                            keyContent: _publicKey!,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard({
    required String title,
    required String keyContent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyToClipboard(keyContent),
                  tooltip: '复制到剪贴板',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  keyContent,
                  style: const TextStyle(
                    fontFamily: 'maple',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
