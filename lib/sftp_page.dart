import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/ssh_service.dart';

class SftpPage extends StatefulWidget {
  final ConnectionInfo connection;
  final Credential credential;

  const SftpPage({
    super.key,
    required this.connection,
    required this.credential,
  });

  @override
  State<SftpPage> createState() => _SftpPageState();
}

class _SftpPageState extends State<SftpPage> {
  final SshService _sshService = SshService();
  SSHClient? _sshClient;
  dynamic _sftpClient;
  
  List<dynamic> _fileList = [];
  String _currentPath = '/';
  bool _isLoading = true;
  bool _isConnected = false;
  String _status = '连接中...';

  @override
  void initState() {
    super.initState();
    _connectSftp();
  }

  Future<void> _connectSftp() async {
    try {
      setState(() {
        _isLoading = true;
        _status = '连接中...';
      });

      _sshClient = await _sshService.connect(widget.connection, widget.credential);
      _sftpClient = await _sshClient!.sftp();
      
      setState(() {
        _isConnected = true;
        _status = '已连接';
      });

      await _loadDirectory(_currentPath);
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
        _status = '连接失败: $e';
      });
      _showErrorDialog('SFTP连接失败', e.toString());
    }
  }

  Future<void> _loadDirectory(String dirPath) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final list = await _sftpClient.listdir(dirPath);
      
      list.sort((a, b) {
        try {
          final aIsDir = a.attr.isDirectory;
          final bIsDir = b.attr.isDirectory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.filename.toString().compareTo(b.filename.toString());
        } catch (e) {
          return 0; 
        }
      });

      setState(() {
        _fileList = list;
        _currentPath = dirPath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorDialog('读取目录失败', e.toString());
    }
  }

  Future<void> _downloadFile(dynamic file) async {
    try {
      if (file.attr.isDirectory) {
        _loadDirectory(path.join(_currentPath, file.filename));
        return;
      }

      final String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: file.filename.toString(),
      );

      if (savePath != null && mounted) {
        _showProgressDialog('下载中...');
        
        final remotePath = path.join(_currentPath, file.filename.toString());
        final localFile = File(savePath);
        
        final remoteFile = await _sftpClient.open(remotePath);
        final content = await remoteFile.readBytes();
        await localFile.writeAsBytes(content);
        
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文件已下载: $savePath')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog('下载失败', e.toString());
      }
    }
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        _showProgressDialog('上传中...');

        for (var platformFile in result.files) {
          if (platformFile.path != null) {
            final localFile = File(platformFile.path!);
            final remotePath = path.join(_currentPath, platformFile.name);
            final data = await localFile.readAsBytes();
            
            final remoteFile = await _sftpClient.open(
              remotePath, 
              mode: SftpFileOpenMode.create | SftpFileOpenMode.write
            );
            await remoteFile.writeBytes(data);
          }
        }

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件上传成功')),
          );
          await _loadDirectory(_currentPath);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog('上传失败', e.toString());
      }
    }
  }

  Future<void> _createDirectory() async {
    final textController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            hintText: '输入新文件夹名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (textController.text.trim().isNotEmpty) {
                Navigator.of(context).pop();
                await _createDirectoryAction(textController.text.trim());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDirectoryAction(String dirName) async {
    try {
      final newDirPath = path.join(_currentPath, dirName);
      await _sftpClient.mkdir(newDirPath);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件夹创建成功')),
        );
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('创建文件夹失败', e.toString());
    }
  }

  Future<void> _deleteItem(dynamic item) async {
    final isDirectory = item.attr.isDirectory;
    final filename = item.filename.toString();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除${isDirectory ? '文件夹' : '文件'}'),
        content: Text('确定要删除 "$filename" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteItemAction(item);
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItemAction(dynamic item) async {
    try {
      final itemPath = path.join(_currentPath, item.filename.toString());
      
      if (item.attr.isDirectory) {
        await _sftpClient.rmdir(itemPath);
      } else {
        await _sftpClient.remove(itemPath);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('删除失败', e.toString());
    }
  }

  void _showProgressDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _goToParentDirectory() {
    if (_currentPath != '/') {
      final parentPath = path.dirname(_currentPath);
      _loadDirectory(parentPath);
    }
  }

  @override
  void dispose() {
    _sftpClient?.close();
    _sshClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SFTP - ${widget.connection.host}'),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle_outlined,
                  color: _isConnected ? Colors.green : Colors.red,
                  size: 10,
                ),
                const SizedBox(width: 6),
                Text(
                  _status,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDirectory(_currentPath),
            tooltip: '刷新',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'upload':
                  _uploadFile();
                  break;
                case 'create_dir':
                  _createDirectory();
                  break;
                case 'reconnect':
                  _connectSftp();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'upload',
                child: Row(
                  children: [
                    Icon(Icons.upload, size: 20),
                    SizedBox(width: 8),
                    Text('上传文件'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'create_dir',
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder, size: 20),
                    SizedBox(width: 8),
                    Text('新建文件夹'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reconnect',
                child: Row(
                  children: [
                    Icon(Icons.replay, size: 20),
                    SizedBox(width: 8),
                    Text('重新连接'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 路径导航
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.transparent,
            child: Row(
              children: [
                if (_currentPath != '/')
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _goToParentDirectory,
                    tooltip: '上级目录',
                  ),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(
                      fontFamily: 'Monospace',
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _fileList.isEmpty
                    ? const Center(
                        child: Text('目录为空'),
                      )
                    : ListView.builder(
                        itemCount: _fileList.length,
                        itemBuilder: (context, index) {
                          final item = _fileList[index];
                          final isDirectory = item.attr.isDirectory;
                          final filename = item.filename.toString();
                          final size = item.attr.size ?? 0;
                          
                          return ListTile(
                            leading: Icon(
                              isDirectory ? Icons.folder : Icons.insert_drive_file,
                              color: isDirectory ? Colors.blue : Colors.grey,
                            ),
                            title: Text(filename),
                            subtitle: Text(
                              isDirectory
                                  ? '文件夹'
                                  : '${_formatFileSize(size)} - ${_formatDate(DateTime.now())}',
                            ),
                            trailing: !isDirectory
                                ? IconButton(
                                    icon: const Icon(Icons.download),
                                    onPressed: () => _downloadFile(item),
                                    tooltip: '下载',
                                  )
                                : null,
                            onTap: () => _downloadFile(item),
                            onLongPress: () => _deleteItem(item),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadFile,
        tooltip: '上传文件',
        child: const Icon(Icons.upload),
      ),
    );
  }
}