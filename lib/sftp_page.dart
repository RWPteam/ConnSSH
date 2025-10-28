// sftp_page.dart
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
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
  Color _appBarColor = Colors.transparent;

  final Set<String> _selectedFiles = {};
  bool _isMultiSelectMode = false;

  double _uploadProgress = 0.0;
  double _downloadProgress = 0.0;
  String _currentOperation = '';
  bool _cancelOperation = false;

  dynamic _currentUploader;
  dynamic _currentDownloadFile;

  @override
  void initState() {
    super.initState();
    _connectSftp();
  }

  // 获取图标颜色 - 根据主题模式切换
  Color _getIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? Colors.white 
        : Colors.black;
  }

  // 获取禁用状态图标颜色
  Color _getDisabledIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? Colors.grey 
        : Colors.grey[600]!;
  }

  Future<void> _connectSftp() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _status = '连接中...';
        _appBarColor = Colors.grey;
      });

      _sshClient = await _sshService.connect(widget.connection, widget.credential);
      _sftpClient = await _sshClient!.sftp();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _status = '已连接';
          _appBarColor = Colors.green;
        });
      }

      await _loadDirectory(_currentPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isLoading = false;
          _status = '连接失败: $e';
          _appBarColor = Colors.red;
        });
        _showErrorDialog('SFTP连接失败', e.toString());
      }
    }
  }

  Future<void> _loadDirectory(String dirPath) async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        if (!_isMultiSelectMode) {
          _selectedFiles.clear();
        }
      });

      String normalizedPath = _normalizePath(dirPath);

      final list = await _sftpClient.listdir(normalizedPath);

      final filteredList = list.where((item) {
        final filename = item.filename.toString();
        return filename != '.' && filename != '..';
      }).toList();

      filteredList.sort((a, b) {
        try {
          final aIsDir = a.attr?.isDirectory ?? false;
          final bIsDir = b.attr?.isDirectory ?? false;

          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;

          final aFilename = a.filename?.toString() ?? '';
          final bFilename = b.filename?.toString() ?? '';
          return aFilename.compareTo(bFilename);
        } catch (e) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _fileList = filteredList;
          _currentPath = normalizedPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _showErrorDialog('读取目录失败', '路径: $dirPath\n错误: $e');
    }
  }

  String _normalizePath(String rawPath) {
    String normalized = rawPath;

    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    normalized = normalized.replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');

    if (normalized != '/' && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  String _joinPath(String part1, String part2) {
    if (part1.endsWith('/')) {
      part1 = part1.substring(0, part1.length - 1);
    }
    if (part2.startsWith('/')) {
      part2 = part2.substring(1);
    }
    return '$part1/$part2';
  }

  void _toggleFileSelection(String filename) {
    if (!mounted) return;

    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
      } else {
        _selectedFiles.add(filename);
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode) {
        _selectedFiles.clear();
      }
    });
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || !mounted) return;

      _showProgressDialog('上传文件', showCancel: true);
      _cancelOperation = false;

      int successCount = 0;
      int totalCount = result.files.length;

      for (int i = 0; i < totalCount; i++) {
        if (_cancelOperation) break;

        final item = result.files[i];
        if (item.path == null) continue;

        final localFile = File(item.path!);
        final remotePath = _joinPath(_currentPath, item.name);

        if (!await localFile.exists()) continue;

        final fileSize = await localFile.length();
        int uploadedBytes = 0;

        setState(() {
          _currentOperation = '正在上传: ${item.name} (${i + 1} / $totalCount)';
          _uploadProgress = 0.0;
        });

        final remote = await _sftpClient.open(
          remotePath,
          mode: SftpFileOpenMode.create |
              SftpFileOpenMode.write |
              SftpFileOpenMode.truncate,
        );
        _currentUploader = remote;

        int offset = 0;
        await for (final chunk in localFile.openRead()) {
          if (_cancelOperation) break;
          await remote.writeBytes(chunk, offset: offset);
          offset += chunk.length;
          uploadedBytes = offset;

          if (mounted) {
            setState(() {
              _uploadProgress = fileSize > 0 ? uploadedBytes / fileSize : 0.0;
            });
          }
        }

        try {
          await remote.close();
        } catch (e) {
          // ignore
        }
        _currentUploader = null;

        if (!_cancelOperation) successCount++;
      }

      if (mounted) Navigator.of(context).pop();
      if (!_cancelOperation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传完成: $successCount / $totalCount 个文件')),
        );
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        _showErrorDialog('上传失败', e.toString());
      }
    } finally {
      _currentUploader = null;
      _uploadProgress = 0;
      _currentOperation = '';
    }
  }
    
  Future<void> _downloadSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    String? saveDir;
    String? firstFileName;

    if (_selectedFiles.isNotEmpty) {
      firstFileName = _selectedFiles.first;
      final firstSavePath = await _getDownloadPath(firstFileName);
      if (firstSavePath == null) return;
      saveDir = File(firstSavePath).parent.path;
    }

    if (saveDir == null || !mounted) {
      _showErrorDialog('下载失败', '无法获取可写目录');
      return;
    }

    _showProgressDialog('下载文件', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int total = _selectedFiles.length;

    for (int i = 0; i < total; i++) {
      if (_cancelOperation) break;

      final filename = _selectedFiles.elementAt(i);
      final remotePath = _joinPath(_currentPath, filename);
      final localFile = File('$saveDir/$filename');

      setState(() {
        _currentOperation = '正在下载: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      IOSink? sink;
      dynamic remote;

      try {
        final stat = await _sftpClient.stat(remotePath);
        final int fileSize = (stat.size ?? 0).toInt();
        num downloadedBytes = 0;

        remote = await _sftpClient.open(remotePath);
        _currentDownloadFile = remote;

        sink = localFile.openWrite();

        num offset = 0;
        const int chunkSize = 32 * 1024;
        
        while (offset < fileSize && !_cancelOperation) {
          final bytesToRead = fileSize - offset > chunkSize ? chunkSize : fileSize - offset;
          final chunk = await remote.readBytes(offset: offset, length: bytesToRead);
          
          if (chunk.isEmpty) break;
          
          sink.add(chunk);
          offset += chunk.length;
          downloadedBytes = offset;

          if (mounted) {
            setState(() {
              _downloadProgress = fileSize > 0 ? (downloadedBytes / fileSize) : 0.0;
            });
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        await remote.close();
        remote = null;
        _currentDownloadFile = null;

        if (!_cancelOperation) successCount++;

      } catch (e) {
        debugPrint('下载失败: $e');
        
        try {
          await sink?.close();
        } catch (_) {}
        
        try {
          await remote?.close();
        } catch (_) {}
        
        _currentDownloadFile = null;

        await Future.delayed(const Duration(milliseconds: 100));
        
        if (await localFile.exists()) {
          try {
            await localFile.delete();
          } catch (deleteError) {
            debugPrint('删除不完整文件失败: $deleteError');
          }
        }
      }
    }

    if (mounted) {
      try {
        Navigator.of(context).pop();
      } catch (_) {}
    }

    if (!_cancelOperation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成: $successCount / $total 个文件')),
      );
      setState(() {
        _selectedFiles.clear();
      });
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
  }

  Future<void> _cancelCurrentOperation() async {
    _cancelOperation = true;

    try {
      await _currentUploader?.close();
    } catch (e) {
      debugPrint('关闭 uploader 出错: $e');
    }
    try {
      await _currentDownloadFile?.close();
    } catch (e) {
      debugPrint('关闭 download file 出错: $e');
    } finally {
      _currentUploader = null;
      _currentDownloadFile = null;
    }

    if (mounted) {
      setState(() {
        _uploadProgress = 0.0;
        _downloadProgress = 0.0;
        _currentOperation = '';
      });
      await Future.delayed(const Duration(milliseconds: 150));
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作已取消')),
        );
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除选中的 ${_selectedFiles.length} 个文件/文件夹吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteSelectedFilesAction();
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

  Future<void> _deleteSelectedFilesAction() async {
    try {
      int successCount = 0;

      for (final filename in _selectedFiles) {
        final itemPath = _joinPath(_currentPath, filename);

        try {
          final stat = await _sftpClient.stat(itemPath);
          if (stat.isDirectory) {
            await _sftpClient.rmdir(itemPath);
          } else {
            await _sftpClient.remove(itemPath);
          }
          successCount++;
        } catch (e) {
          debugPrint('删除 $filename 失败: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除完成: $successCount/${_selectedFiles.length}')),
        );
        setState(() {
          _selectedFiles.clear();
        });
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('删除失败', e.toString());
    }
  }

  Future<void> _showFileDetails() async {
    if (_selectedFiles.length != 1) return;

    final filename = _selectedFiles.first;
    final filePath = _joinPath(_currentPath, filename);

    try {
      final stat = await _sftpClient.stat(filePath);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('文件详情 - $filename'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailItem('文件名', filename),
                  _buildDetailItem('路径', filePath),
                  _buildDetailItem('类型', _getFileType(stat)),
                  _buildDetailItem('大小', _formatFileSize(stat.size ?? 0)),
                  _buildDetailItem('权限', _getPermissions(stat)),
                  _buildDetailItem('修改时间', _formatDate(stat.modifyTime)),
                  _buildDetailItem('访问时间', _formatDate(stat.accessTime)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('获取文件详情失败', e.toString());
    }
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '未知' : value),
          ),
        ],
      ),
    );
  }

  String _getFileType(dynamic stat) {
    if (stat.isDirectory) return '目录';
    if (stat.isSymbolicLink) return '符号链接';
    if (stat.isSocket) return '套接字';
    if (stat.isBlockDevice) return '块设备';
    if (stat.isCharacterDevice) return '字符设备';

    try {
      final type = stat.type;
      if (type != null) {
        final typeName = type.toString().toLowerCase();
        if (typeName.contains('directory')) return '目录';
        if (typeName.contains('symlink') || typeName.contains('link')) return '符号链接';
        if (typeName.contains('socket')) return '套接字';
        if (typeName.contains('block')) return '块设备';
        if (typeName.contains('character')) return '字符设备';
        if (typeName.contains('fifo') || typeName.contains('pipe')) return 'FIFO';
        if (typeName.contains('regular') || typeName.contains('file')) return '普通文件';
      }
    } catch (e) {
      // ignore
    }

    return '普通文件';
  }

  String _getPermissions(dynamic stat) {
    try {
      final mode = stat.mode;
      if (mode == null) return '未知';

      if (mode is int) {
        final permissions = StringBuffer();
        permissions.write((mode & 0x100) != 0 ? 'r' : '-');
        permissions.write((mode & 0x80) != 0 ? 'w' : '-');
        permissions.write((mode & 0x40) != 0 ? 'x' : '-');
        permissions.write((mode & 0x20) != 0 ? 'r' : '-');
        permissions.write((mode & 0x10) != 0 ? 'w' : '-');
        permissions.write((mode & 0x8) != 0 ? 'x' : '-');
        permissions.write((mode & 0x4) != 0 ? 'r' : '-');
        permissions.write((mode & 0x2) != 0 ? 'w' : '-');
        permissions.write((mode & 0x1) != 0 ? 'x' : '-');
        return permissions.toString();
      }

      return '未知';
    } catch (e) {
      return '未知';
    }
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '未知';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _copyPath() async {
    String pathToCopy;

    if (_selectedFiles.isEmpty) {
      pathToCopy = _currentPath;
    } else if (_selectedFiles.length == 1) {
      pathToCopy = _joinPath(_currentPath, _selectedFiles.first);
    } else {
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制路径: $pathToCopy')),
      );
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
      final newDirPath = _joinPath(_currentPath, dirName);
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

  void _showProgressDialog(String title, {required bool showCancel}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StreamBuilder<int>(
          stream: Stream.periodic(const Duration(milliseconds: 200), (i) => i),
          builder: (context, snapshot) {
            final progress = _uploadProgress > 0 ? _uploadProgress : _downloadProgress;
            final displayedText = _currentOperation.isEmpty ? '处理中...' : _currentOperation;

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayedText),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(1)}%'),
                ],
              ),
              actions: showCancel
                  ? [
                      TextButton(
                        onPressed: () {
                          _cancelCurrentOperation();
                        },
                        child: const Text('取消'),
                      ),
                    ]
                  : null,
            );
          },
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
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

  void _goToParentDirectory() {
    if (_currentPath != '/') {
      String parentPath = _normalizePath(_currentPath);
      if (parentPath.endsWith('/') && parentPath != '/') {
        parentPath = parentPath.substring(0, parentPath.length - 1);
      }
      final lastSlashIndex = parentPath.lastIndexOf('/');
      if (lastSlashIndex > 0) {
        parentPath = parentPath.substring(0, lastSlashIndex);
      } else {
        parentPath = '/';
      }
      parentPath = _normalizePath(parentPath);

      _loadDirectory(parentPath);
    }
  }

  void _exitApp() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _cancelCurrentOperation();
    try {
      _sftpClient?.close();
    } catch (_) {}
    try {
      _sshClient?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<String?> _getDownloadPath(String fileName) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '选择保存位置',
      fileName: fileName,
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedFiles.isNotEmpty;
    final singleSelection = _selectedFiles.length == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    final iconColor = _getIconColor(context);
    final disabledIconColor = _getDisabledIconColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SFTP-${widget.connection.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.circle : Icons.circle_outlined,
                  color: Colors.white,
                  size: 10,
                ),
                const SizedBox(width: 6),
                Text(_status, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ],
        ),
        backgroundColor: _appBarColor,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _loadDirectory(_currentPath);
                  break;
                case 'reconnect':
                  _connectSftp();
                  break;
                case 'exit':
                  _exitApp();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 8),
                    Text('刷新'),
                  ],
                ),
              ),
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
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'exit',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, size: 20),
                    SizedBox(width: 8),
                    Text('退出'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16,vertical: 4),
            color: Colors.transparent,
            child: Row(
              children: [
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            color: Colors.transparent,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                      if (_currentPath != '/')
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: _goToParentDirectory,
                          tooltip: '上级目录',
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          icon: const Icon(Icons.upload),
                          onPressed: _uploadFile,
                          tooltip: '上传文件',
                          color: iconColor,
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: hasSelection ? _downloadSelectedFiles : null,
                          tooltip: '下载文件',
                          color: hasSelection ? iconColor : disabledIconColor,
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: hasSelection ? _deleteSelectedFiles : null,
                          tooltip: '删除文件',
                          color: hasSelection ? iconColor : disabledIconColor,
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          icon: const Icon(Icons.create_new_folder),
                          onPressed: _createDirectory,
                          tooltip: '新建文件夹',
                          color: iconColor,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            _isMultiSelectMode ? Icons.check_box : Icons.check_box_outline_blank,
                          ),
                          onPressed: _toggleMultiSelectMode,
                          tooltip: _isMultiSelectMode ? '退出多选' : '多选模式',
                          color: iconColor,
                        ),
                      ],
                    ),
                  ),
                ),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.info, color: singleSelection ? iconColor : disabledIconColor),
                          label: Text('文件详情', style: TextStyle(color: singleSelection ? iconColor : disabledIconColor)),
                          onPressed: singleSelection ? _showFileDetails : null,
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.info),
                          onPressed: singleSelection ? _showFileDetails : null,
                          tooltip: '文件详情',
                          color: singleSelection ? iconColor : disabledIconColor,
                        ),
                      
                      const SizedBox(width: 3),
                      
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.copy, color: (!hasSelection || singleSelection) ? iconColor : disabledIconColor),
                          label: Text('复制路径', style: TextStyle(color: (!hasSelection || singleSelection) ? iconColor : disabledIconColor)),
                          onPressed: (!hasSelection || singleSelection) ? _copyPath : null,
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: (!hasSelection || singleSelection) ? _copyPath : null,
                          tooltip: '复制路径',
                          color: (!hasSelection || singleSelection) ? iconColor : disabledIconColor,
                        ),
                      
                      const SizedBox(width: 3),
                      
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.view_module, color: disabledIconColor),
                          label: Text('切换视图', style: TextStyle(color: disabledIconColor)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('切换视图功能开发中')),
                            );
                          },
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.view_module),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('切换视图功能开发中')),
                            );
                          },
                          tooltip: '切换视图',
                          color: disabledIconColor,
                        ),
                    ],
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
                          final isDirectory = item.attr?.isDirectory == true;
                          final filename = item.filename.toString();
                          final size = item.attr?.size ?? 0;
                          final isSelected = _selectedFiles.contains(filename);

                          return ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isMultiSelectMode)
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (value) {
                                      _toggleFileSelection(filename);
                                    },
                                  ),
                                Icon(
                                  isDirectory ? Icons.folder : Icons.insert_drive_file,
                                  color: isDirectory ? Colors.blueAccent : Colors.grey,
                                ),
                              ],
                            ),
                            title: Text(filename),
                            subtitle: Text(
                              isDirectory ? '文件夹' : _formatFileSize(size),
                            ),
                            onTap: () {
                              if (isDirectory) {
                                String newPath = _joinPath(_currentPath, filename);
                                _loadDirectory(newPath);
                              } else if (_isMultiSelectMode) {
                                _toggleFileSelection(filename);
                              } else {
                                setState(() {
                                  _selectedFiles.clear();
                                  _selectedFiles.add(filename);
                                });
                              }
                            },
                            onLongPress: () {
                              if (!_isMultiSelectMode) {
                                _toggleMultiSelectMode();
                              }
                              _toggleFileSelection(filename);
                            },
                            tileColor: isSelected && !_isMultiSelectMode 
                                ? Colors.blue.withOpacity(0.3)
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}