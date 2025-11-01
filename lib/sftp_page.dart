// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/setting_service.dart';
import 'models/app_settings_model.dart';
import 'services/ssh_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

enum ViewMode { list, icon }

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
  final SettingsService _settingsService = SettingsService();
  
  SSHClient? _sshClient;
  dynamic _sftpClient;
  String? _clipboardFilePath;
  bool _clipboardIsDirectory = false;
  bool _clipboardIsCut = false;
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
  AppSettings _appSettings = AppSettings.defaults;
  ViewMode _viewMode = ViewMode.list;
  DateTime? _lastBackPressedTime;
  bool _isProgressDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _preConnection();
  }

  Color _getIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? Colors.white : Colors.black;
  }

  Color _getDisabledIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? Colors.grey : Colors.grey[600]!;
  }

  Future<void> _preConnection() async {
    try {
      final settings = await _settingsService.getSettings();
      setState(() {
        _appSettings = settings;
        _currentPath = widget.connection.sftpPath ?? settings.defaultSftpPath ?? '/';
      });
    } catch (e) {
      debugPrint('加载设置失败: $e');
      setState(() => _currentPath = '/');
    }
    await _connectSftp();
  }  
  
  Future<void> _connectSftp() async {
    try {
      if (!mounted) return;
      setState(() {
        //清除已经保存的文件选择状态，以防重连后产生冲突
        _isMultiSelectMode = false;
        _selectedFiles.clear();
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
          _appBarColor = Theme.of(context).brightness == Brightness.dark 
              ? Colors.green.shade800 : Colors.green;
        });
      }

      try {
        await _loadDirectory(_currentPath);
      } catch (e) {
        debugPrint('初始路径 $_currentPath 不可用，回退到根目录: $e');
        await _loadDirectory('/');
      }
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

  // 检查连接状态的辅助方法
  Future<bool> _checkConnection() async {
    if (!_isConnected || _sshClient == null || _sftpClient == null) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _status = '连接已断开';
          _appBarColor = Colors.red;
        });
        _showErrorDialog('连接错误', '请重新连接服务器');
      }
      return false;
    }
    
    // 尝试执行一个简单的命令来验证连接是否仍然有效
    try {
      await _sshClient!.execute('pwd').timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('连接检查失败: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _status = '连接已断开';
          _appBarColor = Colors.red;
        });
        _showErrorDialog('连接已断开', '服务器连接已断开，请重新连接');
      }
      return false;
    }
  }

  Future<void> _loadDirectory(String dirPath) async {
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        if (!_isMultiSelectMode) _selectedFiles.clear();
      });

      String normalizedPath = _normalizePath(dirPath);
      final list = await _sftpClient.listdir(normalizedPath);

      final filteredList = list.where((item) {
        final filename = item.filename.toString();
        return filename != '.' && filename != '..';
      }).toList();

      filteredList.sort((a, b) {
        final aIsDir = a.attr?.isDirectory ?? false;
        final bIsDir = b.attr?.isDirectory ?? false;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aFilename = a.filename?.toString() ?? '';
        final bFilename = b.filename?.toString() ?? '';
        return aFilename.compareTo(bFilename);
      });

      if (mounted) {
        setState(() {
          _fileList = filteredList;
          _currentPath = normalizedPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      // 如果操作失败，检查连接状态
      if (!await _checkConnection()) return;
      
      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog('读取目录失败', '路径: $dirPath\n错误: $e');
    }
  }

  String _normalizePath(String rawPath) {
    String normalized = rawPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized != '/' && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _joinPath(String part1, String part2) {
    if (part1.endsWith('/')) part1 = part1.substring(0, part1.length - 1);
    if (part2.startsWith('/')) part2 = part2.substring(1);
    return '$part1/$part2';
  }

  void _toggleFileSelection(String filename) {
    if (!mounted || !_isMultiSelectMode) return;

    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
        if (_selectedFiles.isEmpty) _isMultiSelectMode = false;
      } else {
        _selectedFiles.add(filename);
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
    });
  }

  void _selectAllFiles() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
      if (_isMultiSelectMode) {
        for (var item in _fileList) {
          _selectedFiles.add(item.filename.toString());
        }
      }
    });
  }

  void _clearSelectionAndExitMultiSelect() {
    if (!mounted) return;
    setState(() {
      _selectedFiles.clear();
      _isMultiSelectMode = false;
    });
  }

  Future<void> _uploadFile() async {
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || !mounted) return;

      _showProgressDialog('上传文件', showCancel: true);
      _cancelOperation = false;

      int successCount = 0;
      int totalCount = result.files.length;
      int skippedCount = 0;

      for (int i = 0; i < totalCount; i++) {
        // 在每个文件上传前检查连接状态
        if (!await _checkConnection()) break;
        if (_cancelOperation) break;
        
        final item = result.files[i];
        if (item.path == null) continue;

        final localFile = File(item.path!);
        final remotePath = _joinPath(_currentPath, item.name);
        if (!await localFile.exists()) continue;

        bool fileExists = false;
        try {
          await _sftpClient.stat(remotePath);
          fileExists = true;
        } catch (e) {
          fileExists = false;
        }

        if (fileExists) {
          if (mounted) {
            Navigator.of(context).pop();
            final shouldOverwrite = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('文件已存在'),
                content: Text('文件 "${item.name}" 已存在，是否覆盖？'),
                actions: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('跳过'),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('覆盖', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            _showProgressDialog('上传文件', showCancel: true);
            if (shouldOverwrite == false) {
              skippedCount++;
              continue;
            }
          }
        }

        final fileSize = await localFile.length();
        setState(() {
          _currentOperation = '正在上传: ${item.name} (${i + 1} / $totalCount)';
          _uploadProgress = 0.0;
        });

        final remote = await _sftpClient.open(
          remotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );
        _currentUploader = remote;

        int offset = 0;
        await for (final chunk in localFile.openRead()) {
          // 在每次写入前检查连接状态
          if (!await _checkConnection()) break;
          if (_cancelOperation) break;
          
          await remote.writeBytes(chunk, offset: offset);
          offset += chunk.length;
          if (mounted) {
            setState(() {
              _uploadProgress = fileSize > 0 ? offset / fileSize : 0.0;
            });
          }
        }

        try {
          await remote.close();
        } catch (e) {}
        _currentUploader = null;
        if (!_cancelOperation) successCount++;
      }

      if (mounted) Navigator.of(context).pop();
      if (!_cancelOperation && mounted) {
        String message = '上传完成: $successCount / $totalCount 个文件';
        if (skippedCount > 0) message += ' (跳过 $skippedCount 个文件)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        try { Navigator.of(context).pop(); } catch (_) {}
        _showErrorDialog('上传失败', e.toString());
      }
    } finally {
      _currentUploader = null;
      _uploadProgress = 0;
      _currentOperation = '';
    }
  }  

  Future<void> _deleteSelectedFilesAction() async {
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    try {
      int successCount = 0;
      for (final filename in _selectedFiles) {
        // 在删除每个文件前检查连接状态
        if (!await _checkConnection()) break;
        
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
        _clearSelectionAndExitMultiSelect();
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('删除失败', e.toString());
    }
  }

  Future<void> _downloadSelectedFiles() async {
    if (_selectedFiles.isEmpty) {
      debugPrint('没有选中任何文件，跳过下载');
      return;
    }

    // 在操作前检查连接状态
    if (!await _checkConnection()) return;

    List<String> directories = [];
    for (String filename in _selectedFiles) {
      try {
        final fileItem = _fileList.firstWhere((item) => item.filename.toString() == filename);
        if (fileItem.attr?.isDirectory == true) directories.add(filename);
      } catch (e) {
        debugPrint('找不到文件: $filename');
      }
    }

    if (directories.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('错误: 不能下载目录: ${directories.join(', ')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    String? saveDir = _appSettings.defaultDownloadPath?.isNotEmpty == true 
        ? _appSettings.defaultDownloadPath 
        : await _getDownloadDirectory();

    if (saveDir == null && Platform.isAndroid) {
      saveDir = await _getAndroidDownloadDirectory();
    }

    try {
      final dir = Directory(saveDir!);
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      if (mounted) {
        if (saveDir == null || saveDir.isEmpty) {
          debugPrint('没有可用的下载目录，下载操作已取消');
        } else {
          _showErrorDialog('下载失败', '无法创建保存目录: $e');
        }
      }
      return;
    }

    _showProgressDialog('下载文件', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int total = _selectedFiles.length;

    for (int i = 0; i < total; i++) {
      // 在下载每个文件前检查连接状态
      if (!await _checkConnection()) break;
      if (_cancelOperation) break;
      
      final filename = _selectedFiles.elementAt(i);
      final remotePath = _joinPath(_currentPath, filename);
      final safeFilename = _getSafeFileName(filename);
      final localFilePath = '$saveDir/$safeFilename';

      setState(() {
        _currentOperation = '正在下载: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      await _downloadSingleFile(remotePath, localFilePath, filename, i, total);
      if (!_cancelOperation && await File(localFilePath).exists()) successCount++;
    }

    if (mounted) {
      try { Navigator.of(context).pop(); } catch (_) {}
      if (!_cancelOperation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载完成: $successCount / $total 个文件')),
        );
        _clearSelectionAndExitMultiSelect();
      }
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
  }

  Future<String?> _getDownloadDirectory() async {
    if (Platform.isWindows) {
      final firstSelectedFile = _selectedFiles.first;
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存 ${_selectedFiles.length > 1 ? '多个文件' : firstSelectedFile}',
        fileName: _selectedFiles.length == 1 ? firstSelectedFile : null,
      );
      return result?.substring(0, result.lastIndexOf(Platform.pathSeparator));
    } else {
      return await FilePicker.platform.getDirectoryPath(dialogTitle: '选择默认下载目录');
    }
  }

  Future<String?> _getAndroidDownloadDirectory() async {
    return _appSettings.defaultDownloadPath?.isNotEmpty == true 
        ? _appSettings.defaultDownloadPath
        : await SettingsService.getPlatformDefaultDownloadPath();
  }

  Future<void> _downloadSingleFile(String remotePath, String localFilePath, String filename, int index, int total) async {
    IOSink? sink;
    dynamic remote;

    try {
      final stat = await _sftpClient.stat(remotePath);
      final int fileSize = (stat.size ?? 0).toInt();
      if (fileSize <= 0) {
        debugPrint('文件大小为0或无效: $filename');
        return;
      }

      remote = await _sftpClient.open(remotePath);
      _currentDownloadFile = remote;
      final localFile = File(localFilePath);
      sink = localFile.openWrite();

      num offset = 0;
      const int chunkSize = 32 * 1024;
      
      while (offset < fileSize && !_cancelOperation) {
        // 在每次读取前检查连接状态
        if (!await _checkConnection()) break;
        
        final bytesToRead = fileSize - offset > chunkSize ? chunkSize : fileSize - offset;
        final chunk = await remote.readBytes(offset: offset, length: bytesToRead);
        if (chunk.isEmpty) {
          debugPrint('读取到空数据块，文件可能已损坏: $filename');
          break;
        }
        sink.add(chunk);
        offset += chunk.length;
        if (mounted) {
          setState(() => _downloadProgress = fileSize > 0 ? (offset / fileSize) : 0.0);
        }
      }

      await sink.flush();
      await sink.close();
      await remote.close();
      _currentDownloadFile = null;
    } catch (e) {
      debugPrint('下载文件 $filename 失败: $e');
      try { await sink?.close(); } catch (_) {}
      try { await remote?.close(); } catch (_) {}
      _currentDownloadFile = null;
      try {
        final incompleteFile = File(localFilePath);
        if (await incompleteFile.exists()) await incompleteFile.delete();
      } catch (deleteError) {
        debugPrint('删除不完整文件失败: $deleteError');
      }
      rethrow;
    }
  }

  String _getSafeFileName(String filename) {
    return filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<void> _cancelCurrentOperation() async {
    _cancelOperation = true;
    try { await _currentUploader?.close(); } catch (e) { debugPrint('关闭 uploader 出错: $e'); }
    try { await _currentDownloadFile?.close(); } catch (e) { debugPrint('关闭 download file 出错: $e'); }
    _currentUploader = null;
    _currentDownloadFile = null;

    if (mounted) {
      setState(() {
        _uploadProgress = 0.0;
        _downloadProgress = 0.0;
        _currentOperation = '';
      });
      
      // 安全关闭对话框
      if (_isProgressDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作已取消')));
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;
    
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除选中的 ${_selectedFiles.length} 个文件/文件夹吗？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteSelectedFilesAction();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileDetails() async {
    if (_selectedFiles.length != 1) return;
    
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    final filename = _selectedFiles.first;
    final filePath = _joinPath(_currentPath, filename);

    try {
      final stat = await _sftpClient.stat(filePath);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('属性 - $filename'),
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
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('获取属性失败', e.toString());
    }
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _fileList.length,
      itemBuilder: _buildFileItem,
    );
  }

  Widget _buildGridView() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = _getCrossAxisCount(screenWidth);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.95,
      ),
      itemCount: _fileList.length,
      itemBuilder: (context, index) {
        final item = _fileList[index];
        final isDirectory = item.attr?.isDirectory == true;
        final filename = item.filename.toString();
        final isSelected = _selectedFiles.contains(filename);

        return GestureDetector(
          onTap: () {
            if (_isMultiSelectMode) {
              _toggleFileSelection(filename);
            } else if (isDirectory) {
              _loadDirectory(_joinPath(_currentPath, filename));
            }
          },
          onLongPress: () {
            if (!_isMultiSelectMode) _toggleMultiSelectMode();
            _toggleFileSelection(filename);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.12) : null,
              borderRadius: BorderRadius.circular(5),
              border: isSelected ? Border.all(color: Colors.blueAccent, width: 1.3) : null,
            ),
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        child: Icon(
                          isDirectory ? Icons.folder : Icons.insert_drive_file,
                          size: 50,
                          color: isDirectory ? Colors.blueAccent : Colors.grey,
                        ),
                      ),
                    ),
                    Container(
                      height: constraints.maxHeight * 0.3, 
                      alignment: Alignment.topCenter,
                      child: Text(
                        filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth >= 1600) return 10;
    if (screenWidth >= 1300) return 8;
    if (screenWidth >= 1000) return 7;
    if (screenWidth >= 800) return 6;
    if (screenWidth >= 600) return 5;
    if (screenWidth >= 400) return 4;
    return 3;
  }
    
  Widget _buildFileItem(BuildContext context, int index) {
    final item = _fileList[index];
    final isDirectory = item.attr?.isDirectory == true;
    final filename = item.filename.toString();
    final size = item.attr?.size ?? 0;
    final isSelected = _selectedFiles.contains(filename);

    return ListTile(
      leading: Icon(
        isDirectory ? Icons.folder : Icons.insert_drive_file,
        color: isDirectory ? Colors.blueAccent : Colors.grey,
      ),
      title: Text(filename),
      subtitle: Text(isDirectory ? '文件夹' : _formatFileSize(size)),
      onTap: () {
        if (_isMultiSelectMode) {
          _toggleFileSelection(filename);
        } else if (isDirectory) {
          _loadDirectory(_joinPath(_currentPath, filename));
        }
      },
      onLongPress: () {
        if (!_isMultiSelectMode) _toggleMultiSelectMode();
        _toggleFileSelection(filename);
      },
      tileColor: isSelected ? Colors.blue.withOpacity(0.3) : null,
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value.isEmpty ? '未知' : value)),
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
      final type = stat.type?.toString().toLowerCase() ?? '';
      if (type.contains('directory')) return '目录';
      if (type.contains('symlink') || type.contains('link')) return '符号链接';
      if (type.contains('socket')) return '套接字';
      if (type.contains('block')) return '块设备';
      if (type.contains('character')) return '字符设备';
      if (type.contains('fifo') || type.contains('pipe')) return 'FIFO';
      if (type.contains('regular') || type.contains('file')) return '普通文件';
    } catch (e) {}
    return '普通文件';
  }

  String _getPermissions(dynamic stat) {
    try {
      final mode = stat.mode;
      if (mode == null) return '---------';
      if (mode is String) {
        final match = RegExp(r'\((\d+)\)').firstMatch(mode);
        if (match != null) {
          final octalString = match.group(1);
          if (octalString != null && octalString.length >= 3) {
            final lastDigits = octalString.length > 3 
                ? octalString.substring(octalString.length - 3) : octalString;
            return _octalToPermissionString(lastDigits);
          }
        }
        if (mode.length >= 3) {
          final lastDigits = mode.length > 3 ? mode.substring(mode.length - 3) : mode;
          if (RegExp(r'^\d+$').hasMatch(lastDigits)) return _octalToPermissionString(lastDigits);
        }
        return '---------';
      }
      if (mode is int) return _intToPermissionString(mode);
      
      final modeStr = mode.toString();
      final digitMatch = RegExp(r'(\d{3,4})').firstMatch(modeStr);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        final lastThree = digits.length > 3 ? digits.substring(digits.length - 3) : digits;
        return _octalToPermissionString(lastThree);
      }
      if (modeStr.length >= 9 && RegExp(r'^[rwsxt-]{9,}$').hasMatch(modeStr)) {
        return modeStr.length > 9 ? modeStr.substring(modeStr.length - 9) : modeStr;
      }
      return '---------';
    } catch (e) {
      debugPrint('获取权限失败: $e');
      return '---------';
    }
  }

  String _octalToPermissionString(String octalString) {
    if (octalString.length != 3) return '---------';
    final permissions = StringBuffer();
    for (int i = 0; i < 3; i++) {
      final digit = int.tryParse(octalString[i]);
      if (digit == null) return '---------';
      permissions.write((digit & 4) != 0 ? 'r' : '-');
      permissions.write((digit & 2) != 0 ? 'w' : '-');
      permissions.write((digit & 1) != 0 ? 'x' : '-');
    }
    return permissions.toString();
  }

  String _intToPermissionString(int mode) {
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

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '未知';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _createDirectory() async {
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
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
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
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
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    try {
      final newDirPath = _joinPath(_currentPath, dirName);
      await _sftpClient.mkdir(newDirPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件夹创建成功')));
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('创建文件夹失败', e.toString());
    }
  }

  Future<void> _copySelected() async {
    if (_selectedFiles.length != 1) return;
    
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    final name = _selectedFiles.first;
    final remotePath = _joinPath(_currentPath, name);

    try {
      final stat = await _sftpClient.stat(remotePath);
      if (!_hasReadPermission(stat)) {
        _showErrorDialog('复制失败', '没有读取 $name 的权限');
        return;
      }
      setState(() {
        _clipboardFilePath = remotePath;
        _clipboardIsDirectory = stat.isDirectory;
        _clipboardIsCut = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
      _clearSelectionAndExitMultiSelect();
    } catch (e) {
      _showErrorDialog('复制失败', e.toString());
    }
  }

  Future<void> _cutSelected() async {
    if (_selectedFiles.length != 1) return;
    
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    final name = _selectedFiles.first;
    final remotePath = _joinPath(_currentPath, name);

    try {
      final stat = await _sftpClient.stat(remotePath);
      if (!_hasWritePermission(stat)) {
        _showErrorDialog('剪切失败', '没有修改 $name 的权限');
        return;
      }
      setState(() {
        _clipboardFilePath = remotePath;
        _clipboardIsDirectory = stat.isDirectory;
        _clipboardIsCut = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已剪切: $name')));
    } catch (e) {
      _showErrorDialog('剪切失败', e.toString());
    }
  }

  bool _hasReadPermission(dynamic stat) {
    try {
      final permissions = _getPermissions(stat);
      return permissions.length >= 9 && permissions[6] == 'r';
    } catch (e) {
      debugPrint('检查读取权限失败: $e');
      return true;
    }
  }

  bool _hasWritePermission(dynamic stat) {
    try {
      final permissions = _getPermissions(stat);
      return permissions.length >= 9 && permissions[7] == 'w';
    } catch (e) {
      debugPrint('检查写入权限失败: $e');
      return true;
    }
  }

  Future<void> _showProgressDialog(String title, {required bool showCancel}) async {
    if (_isProgressDialogOpen) return;
    
    _isProgressDialogOpen = true;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
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
                  ? [OutlinedButton(onPressed: _cancelCurrentOperation, child: const Text('取消'))]
                  : null,
            );
          },
        );
      },
    ).then((_) {
      _isProgressDialogOpen = false;
    });
  }

  Future<void> _pasteFile() async {
    if (_clipboardFilePath == null) return;
    
    // 在操作前检查连接状态
    if (!await _checkConnection()) return;
    
    final fileName = _clipboardFilePath!.split('/').last;
    final newPath = _joinPath(_currentPath, fileName);

    try {
      setState(() => _isLoading = true);
      if (_clipboardIsCut) {
        await _sftpClient.rename(_clipboardFilePath!, newPath);
        bool sourceExists = true, targetExists = false;
        try { await _sftpClient.stat(_clipboardFilePath!); } catch (e) { sourceExists = false; }
        try { await _sftpClient.stat(newPath); targetExists = true; } catch (e) { targetExists = false; }
        
        if (!sourceExists && targetExists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动成功: $fileName')));
          }
          if (mounted) {
            setState(() {
              _selectedFiles.clear();
              _clipboardFilePath = null;
              _clipboardIsCut = false;
            });
            await _loadDirectory(_currentPath);
          }
        } else {
          throw Exception('剪切操作失败：权限不足或目标已存在');
        }
      } else {
        final cmd = _clipboardIsDirectory
            ? 'cp -r "${_clipboardFilePath!}" "$newPath"'
            : 'cp "${_clipboardFilePath!}" "$newPath"';
        final session = await _sshClient!.execute(cmd);
        await session.done;
        final exitCode = session.exitCode;

        if (exitCode == 0) {
          bool targetExists = false;
          try { await _sftpClient.stat(newPath); targetExists = true; } catch (e) { targetExists = false; }
          if (targetExists) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('复制成功: $fileName')));
              setState(() {
                _selectedFiles.clear();
                _clipboardFilePath = null;
              });
              await _loadDirectory(_currentPath);
            }
          } else {
            throw Exception('复制操作失败：目标文件不存在');
          }
        } else {
          final stderr = await session.stderr.join();
          throw Exception('复制命令执行失败，退出码: $exitCode\n错误: $stderr');
        }
      }
    } catch (e) {
      if (mounted) _showErrorDialog('粘贴失败', e.toString());
      if (mounted) {
        setState(() {
          _clipboardFilePath = null;
          _clipboardIsCut = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('确定'))],
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
      parentPath = lastSlashIndex > 0 ? parentPath.substring(0, lastSlashIndex) : '/';
      _loadDirectory(_normalizePath(parentPath));
    }
  }

  void _exitApp() => Navigator.of(context).pop();

  Future<bool> _onWillPop() async {
    if (_currentPath != '/') {
      _goToParentDirectory();
      return false;
    }
    
    final now = DateTime.now();
    final bool shouldExit = _lastBackPressedTime == null ||
        now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

    if (shouldExit) {
      _lastBackPressedTime = now;
      
    Fluttertoast.showToast(
        msg: "再按一次退出",
        toastLength: Toast.LENGTH_SHORT, 
        gravity: ToastGravity.BOTTOM, 
        timeInSecForIosWeb: 1, 
        backgroundColor: Colors.grey[700], 
        textColor: Colors.white,
        fontSize: 16.0 
    );
      
      Future.delayed(const Duration(seconds: 2), () {});
      
      return false;
    }
    
    return true;
  }

  @override
  void dispose() {
    _cancelCurrentOperation();
    try { _sftpClient?.close(); } catch (_) {}
    try { _sshClient?.close(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedFiles.isNotEmpty;
    final singleSelection = _selectedFiles.length == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    final iconColor = _getIconColor(context);
    final disabledIconColor = _getDisabledIconColor(context);

    // 使用 WillPopScope 来拦截返回按钮
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
                  Icon(_isConnected ? Icons.circle : Icons.circle_outlined, color: Colors.white, size: 10),
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
                  case 'refresh': _loadDirectory(_currentPath); break;
                  case 'reconnect': _connectSftp(); break;
                  case 'exit': _exitApp(); break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(children: [Icon(Icons.refresh, size: 20), SizedBox(width: 8), Text('刷新')]),
                ),
                const PopupMenuItem(
                  value: 'reconnect',
                  child: Row(children: [Icon(Icons.replay, size: 20), SizedBox(width: 8), Text('重新连接')]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'exit',
                  child: Row(children: [Icon(Icons.exit_to_app, size: 20), SizedBox(width: 8), Text('退出')]),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _currentPath,
                    style: const TextStyle(fontFamily: 'Monospace', fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        if (_currentPath != '/')
                          IconButton(
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: _goToParentDirectory,
                            tooltip: '上级目录',
                          ) else IconButton(
                            icon: const Icon(Icons.circle_outlined),
                            onPressed: null,
                            tooltip: '/',
                          ),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.upload, '上传文件', _uploadFile, iconColor),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.download, '下载文件', 
                            hasSelection ? _downloadSelectedFiles : null, 
                            hasSelection ? iconColor : disabledIconColor),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.delete, '删除文件', 
                            hasSelection ? _deleteSelectedFiles : null, 
                            hasSelection ? iconColor : disabledIconColor),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.create_new_folder, '新建文件夹', _createDirectory, iconColor),
                        const SizedBox(width: 8),
                        _buildIconButton(
                            _isMultiSelectMode ? Icons.check_box_outline_blank : Icons.check_box,
                            _isMultiSelectMode ? '取消选择' : '全选', _selectAllFiles, iconColor),
                        _buildIconButton(Icons.copy, '复制', 
                            singleSelection ? _copySelected : null, 
                            singleSelection ? iconColor : disabledIconColor),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.cut, '剪切', 
                            singleSelection ? _cutSelected : null, 
                            singleSelection ? iconColor : disabledIconColor),
                        const SizedBox(width: 3),
                        _buildIconButton(Icons.paste, '粘贴', 
                            _clipboardFilePath != null ? _pasteFile : null, 
                            _clipboardFilePath != null ? iconColor : disabledIconColor),

                      ]),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.info, color: singleSelection ? iconColor : disabledIconColor),
                          label: Text('属性', style: TextStyle(color: singleSelection ? iconColor : disabledIconColor)),
                          onPressed: singleSelection ? _showFileDetails : null,
                        )
                      else
                        _buildIconButton(Icons.info, '属性', 
                            singleSelection ? _showFileDetails : null, 
                            singleSelection ? iconColor : disabledIconColor),
                      const SizedBox(width: 3),
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.view_module, color: disabledIconColor),
                          label: Text('切换视图', style: TextStyle(color: disabledIconColor)),
                          onPressed: () => setState(() => _viewMode = _viewMode == ViewMode.list ? ViewMode.icon : ViewMode.list),
                        )
                      else
                        _buildIconButton(Icons.view_module, '切换视图', 
                            () => setState(() => _viewMode = _viewMode == ViewMode.list ? ViewMode.icon : ViewMode.list), 
                            disabledIconColor),
                    ]),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: Text('正在加载'))
                  : _fileList.isEmpty
                      ? const Center(child: Text('目录为空'))
                      : _viewMode == ViewMode.list ? _buildListView() : _buildGridView(),
            ),
          ],
        ),
      ),
    );

  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback? onPressed, Color color) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
    );
  }
}