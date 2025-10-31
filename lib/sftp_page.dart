import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
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
  enum ViewMode { list, icon }
  ViewMode _viewMode = ViewMode.list;
class _SftpPageState extends State<SftpPage> {
  final SshService _sshService = SshService();
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

  @override
  void initState() {
    super.initState();
    _connectSftp();
  }

  Color _getIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark 
        ? Colors.white 
        : Colors.black;
  }

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
          if (Theme.of(context).brightness == Brightness.dark )
          {
            _appBarColor = Colors.green.shade800;
          } else {
            _appBarColor = Colors.green;
          }
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
    if (!mounted || !_isMultiSelectMode) return;

    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
        // 如果没有选中任何文件，自动退出多选模式
        if (_selectedFiles.isEmpty) {
          _isMultiSelectMode = false;
        }
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
    if (_isMultiSelectMode == true) {
      _toggleMultiSelectMode();
    } else {
      setState(() {
        _isMultiSelectMode = true;
        _selectedFiles.clear();
        for (var item in _fileList) {
          final filename = item.filename.toString();
          _selectedFiles.add(filename);
        }
      });
    }
  }

  void _clearSelectionAndExitMultiSelect() {
    if (!mounted) return;
    
    setState(() {
      _selectedFiles.clear();
      _isMultiSelectMode = false;
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
        
        // 删除操作后清空选择并退出多选模式
        _clearSelectionAndExitMultiSelect();
        
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('删除失败', e.toString());
    }
  }


  Future<String?> _getDownloadPath(String fileName) async {
    try {
      if (Platform.isAndroid) {
        // Android 专用处理
        return await _getAndroidDownloadPath(fileName);
      } else {
        // 其他平台使用原有逻辑
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '选择保存位置',
          fileName: fileName,
        );
        return result;
      }
    } catch (e) {
      debugPrint('获取下载路径失败: $e');
      return await _getFallbackDownloadPath(fileName);
    }
  }

  Future<String?> _getAndroidDownloadPath(String fileName) async {
    try {
      // 首先尝试使用 Downloads 目录
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        final file = File('${directory.path}/$fileName');
        return file.path;
      }
      
      // 如果 Downloads 目录不可用，尝试外部存储目录
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        // 在外部存储目录下创建 Connecter 文件夹
        final connecterDir = Directory('${externalDir.path}/Connecter');
        if (!await connecterDir.exists()) {
          await connecterDir.create(recursive: true);
        }
        final file = File('${connecterDir.path}/$fileName');
        return file.path;
      }
      
      // 最后尝试应用文档目录
      final documentsDir = await getApplicationDocumentsDirectory();
      final file = File('${documentsDir.path}/$fileName');
      return file.path;
      
    } catch (e) {
      debugPrint('Android 下载路径获取失败: $e');
      return null;
    }
  }

  Future<String?> _getFallbackDownloadPath(String fileName) async {
    try {
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final downloadDir = Directory('${directory.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return '${downloadDir.path}/$fileName';
        }
      } else if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        return '${directory.path}/$fileName';
      }
      
      // 最后的备用方案
      final directory = await getTemporaryDirectory();
      return '${directory.path}/$fileName';
    } catch (e) {
      debugPrint('备用下载路径获取失败: $e');
      return null;
    }
  }

  Future<void> _downloadSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    String? saveDir;
    String? firstFileName;

    if (_selectedFiles.isNotEmpty) {
      firstFileName = _selectedFiles.first;
      
      // 对于 Android，我们直接生成路径，不通过 FilePicker
      if (Platform.isAndroid) {
        saveDir = await _getAndroidDownloadDirectory();
      } else {
        final firstSavePath = await _getDownloadPath(firstFileName);
        if (firstSavePath != null && firstSavePath.isNotEmpty) {
          try {
            final file = File(firstSavePath);
            final parentDir = file.parent;
            if (!await parentDir.exists()) {
              await parentDir.create(recursive: true);
            }
            saveDir = parentDir.path;
          } catch (e) {
            debugPrint('创建保存目录失败: $e');
          }
        }
      }
    }

    saveDir ??= await _selectDownloadDirectory();

    if (saveDir == null || !mounted) {
      _showErrorDialog('下载失败', '无法获取可写目录');
      return;
    }

    // 确保目录存在
    try {
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('下载失败', '无法创建保存目录: $e');
      }
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
      final safeFilename = _getSafeFileName(filename);
      final localFilePath = '$saveDir/$safeFilename';

      setState(() {
        _currentOperation = '正在下载: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      await _downloadSingleFile(remotePath, localFilePath, filename, i, total);
      
      if (!_cancelOperation) {
        // 检查文件是否成功下载
        final localFile = File(localFilePath);
        if (await localFile.exists()) {
          successCount++;
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
      _clearSelectionAndExitMultiSelect();
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
  }

  Future<String?> _getAndroidDownloadDirectory() async {
    try {
      // 优先使用 Downloads 目录
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return downloadsDir.path;
      }
      
      // 备用方案：外部存储目录下的 Download 文件夹
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadDir = Directory('${externalDir.path}/Download');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir.path;
      }
      
      return null;
    } catch (e) {
      debugPrint('获取 Android 下载目录失败: $e');
      return null;
    }
  }

  Future<String?> _selectDownloadDirectory() async {
    try {
      if (Platform.isAndroid) {
        // Android 使用固定的下载目录
        return await _getAndroidDownloadDirectory();
      } else {
        // 其他平台使用目录选择器
        final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存目录',
        );
        return selectedDirectory;
      }
    } catch (e) {
      debugPrint('选择下载目录失败: $e');
      return null;
    }
  }

  Future<void> _downloadSingleFile(String remotePath, String localFilePath, String filename, int index, int total) async {
    IOSink? sink;
    dynamic remote;

    try {
      // 检查远程文件是否存在
      final stat = await _sftpClient.stat(remotePath);
      final int fileSize = (stat.size ?? 0).toInt();
      
      if (fileSize <= 0) {
        debugPrint('文件大小为0或无效: $filename');
        return;
      }

      remote = await _sftpClient.open(remotePath);
      _currentDownloadFile = remote;

      // 创建本地文件
      final localFile = File(localFilePath);
      sink = localFile.openWrite();

      num offset = 0;
      const int chunkSize = 32 * 1024;
      
      while (offset < fileSize && !_cancelOperation) {
        final bytesToRead = fileSize - offset > chunkSize ? chunkSize : fileSize - offset;
        final chunk = await remote.readBytes(offset: offset, length: bytesToRead);
        
        if (chunk.isEmpty) {
          debugPrint('读取到空数据块，文件可能已损坏: $filename');
          break;
        }
        
        sink.add(chunk);
        offset += chunk.length;

        if (mounted) {
          setState(() {
            _downloadProgress = fileSize > 0 ? (offset / fileSize) : 0.0;
          });
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      await remote.close();
      remote = null;
      _currentDownloadFile = null;

    } catch (e) {
      debugPrint('下载文件 $filename 失败: $e');
      
      // 清理资源
      try {
        await sink?.close();
      } catch (_) {}
      
      try {
        await remote?.close();
      } catch (_) {}
      
      _currentDownloadFile = null;

      // 删除可能已创建的不完整文件
      try {
        final incompleteFile = File(localFilePath);
        if (await incompleteFile.exists()) {
          await incompleteFile.delete();
        }
      } catch (deleteError) {
        debugPrint('删除不完整文件失败: $deleteError');
      }
      
      // 重新抛出异常以便上层处理
      rethrow;
    }
  }

  String _getSafeFileName(String filename) {
    // 替换可能引起问题的字符
    return filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
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
              TextButton(
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
    int crossAxisCount;
    if (screenWidth >= 1600) {
      crossAxisCount = 10;
    } else if (screenWidth >= 1300) {
      crossAxisCount = 8;
    } else if (screenWidth >= 1000) {
      crossAxisCount = 7;
    } else if (screenWidth >= 800) {
      crossAxisCount = 6;
    } else if (screenWidth >= 600) {
      crossAxisCount = 5;
    } else if (screenWidth >= 400) {
      crossAxisCount = 4;
    } else {
      crossAxisCount = 3;
    }

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
            if (!_isMultiSelectMode) {
              _toggleMultiSelectMode();
            }
            _toggleFileSelection(filename);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue.withOpacity(0.12)
                  : null,
              borderRadius: BorderRadius.circular(5),
              border: isSelected
                  ? Border.all(color: Colors.blueAccent, width: 1.3)
                  : null,
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center, // 改为居中对齐
              crossAxisAlignment: CrossAxisAlignment.center, // 水平居中对齐
              children: [
                Icon(
                  isDirectory ? Icons.folder : Icons.insert_drive_file,
                  size: 50,
                  color: isDirectory ? Colors.blueAccent : Colors.grey,
                ),
                const SizedBox(height: 4), // 添加固定间距
                Text(
                  filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
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
        if (!_isMultiSelectMode) {
          _toggleMultiSelectMode();
        }
        _toggleFileSelection(filename);
      },
      tileColor: isSelected
          ? Colors.blue.withOpacity(0.3)
          : null,
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
      if (mode == null) return '---------';

      // 处理字符串格式，如 "de(400644)"
      if (mode is String) {
        final match = RegExp(r'\((\d+)\)').firstMatch(mode);
        if (match != null) {
          final octalString = match.group(1);
          if (octalString != null && octalString.length >= 3) {
            // 取最后3位或4位（如果有4位，第一位是特殊权限位）
            final lastDigits = octalString.length > 3 
                ? octalString.substring(octalString.length - 3)
                : octalString;
            
            return _octalToPermissionString(lastDigits);
          }
        }
        
        // 如果无法从括号中提取，尝试直接解析整个字符串
        if (mode.length >= 3) {
          final lastDigits = mode.length > 3 
              ? mode.substring(mode.length - 3)
              : mode;
          
          // 检查是否是纯数字
          if (RegExp(r'^\d+$').hasMatch(lastDigits)) {
            return _octalToPermissionString(lastDigits);
          }
        }
        
        return '---------';
      }

      // 处理整数格式（原有逻辑）
      if (mode is int) {
        return _intToPermissionString(mode);
      }

      // 如果 mode 不是整数也不是字符串，尝试其他方式解析
      final modeStr = mode.toString();
      
      // 尝试从字符串中提取数字权限
      final digitMatch = RegExp(r'(\d{3,4})').firstMatch(modeStr);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        final lastThree = digits.length > 3 
            ? digits.substring(digits.length - 3)
            : digits;
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
      
      final read = (digit & 4) != 0;
      final write = (digit & 2) != 0;
      final execute = (digit & 1) != 0;
      
      permissions.write(read ? 'r' : '-');
      permissions.write(write ? 'w' : '-');
      permissions.write(execute ? 'x' : '-');
    }
    
    return permissions.toString();
  }

  String _intToPermissionString(int mode) {
    final permissions = StringBuffer();
    
    permissions.write((mode & 0x100) != 0 ? 'r' : '-'); // 读
    permissions.write((mode & 0x80) != 0 ? 'w' : '-');  // 写  
    permissions.write((mode & 0x40) != 0 ? 'x' : '-');  // 执行

    permissions.write((mode & 0x20) != 0 ? 'r' : '-'); // 读
    permissions.write((mode & 0x10) != 0 ? 'w' : '-'); // 写
    permissions.write((mode & 0x8) != 0 ? 'x' : '-');  // 执行
    
    permissions.write((mode & 0x4) != 0 ? 'r' : '-'); // 读
    permissions.write((mode & 0x2) != 0 ? 'w' : '-'); // 写
    permissions.write((mode & 0x1) != 0 ? 'x' : '-'); // 执行
    
    return permissions.toString();
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '未知';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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

  Future<void> _copySelected() async {
    if (_selectedFiles.length != 1) return;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制')),
      );
      _clearSelectionAndExitMultiSelect();
    } catch (e) {
      _showErrorDialog('复制失败', e.toString());
    }
  }

  Future<void> _cutSelected() async {
    if (_selectedFiles.length != 1) return;

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已剪切: $name')),
      );
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

  //bool _hasExecutePermission(dynamic stat) {
    //try {
      //final permissions = _getPermissions(stat);
      // 检查其他用户的执行权限（最后一位的x权限）
      //return permissions.length >= 9 && permissions[8] == 'x';
    //} catch (e) {
      //debugPrint('检查执行权限失败: $e');
      //return true; // 如果检查失败，默认允许
    //}
  //}

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

  Future<void> _pasteFile() async {
    if (_clipboardFilePath == null) return;

    final fileName = _clipboardFilePath!.split('/').last;
    final newPath = _joinPath(_currentPath, fileName);

    try {
      setState(() => _isLoading = true);

      if (_clipboardIsCut) {
        // 剪切操作
        await _sftpClient.rename(_clipboardFilePath!, newPath);
        
        // 检查剪切是否成功：源文件应该不存在，目标文件应该存在
        bool sourceExists = true;
        bool targetExists = false;
        
        try {
          await _sftpClient.stat(_clipboardFilePath!);
        } catch (e) {
          sourceExists = false; // 源文件不存在，说明剪切成功
        }
        
        try {
          await _sftpClient.stat(newPath);
          targetExists = true; // 目标文件存在，说明剪切成功
        } catch (e) {
          targetExists = false;
        }
        
        if (!sourceExists && targetExists) {
          // 剪切成功
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('移动成功: $fileName')),
            );
          }
          
          if (mounted) {
            setState(() {
              _selectedFiles.clear();
              _clipboardFilePath = null;
              _clipboardIsCut = false;
            });
          }
          
          if (mounted) {
            await _loadDirectory(_currentPath);
          }
        } else {
          // 剪切失败
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
          try {
            await _sftpClient.stat(newPath);
            targetExists = true;
          } catch (e) {
            targetExists = false;
          }
          
          if (targetExists) {
            // 复制成功
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('复制成功: $fileName')),
              );
            }
            
            if (mounted) {
              setState(() {
                _selectedFiles.clear();
                _clipboardFilePath = null;
              });
            }
            
            if (mounted) {
              await _loadDirectory(_currentPath);
            }
          } else {
            // 复制失败 - 目标文件不存在
            throw Exception('复制操作失败：目标文件不存在');
          }
        } else {
          // 命令执行失败
          final stderr = await session.stderr.join();
          throw Exception('复制命令执行失败，退出码: $exitCode\n错误: $stderr');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('粘贴失败', e.toString());
      }
      
      // 操作失败后清空剪贴板
      if (mounted) {
        setState(() {
          _clipboardFilePath = null;
          _clipboardIsCut = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                            _isMultiSelectMode ? Icons.check_box_outline_blank : Icons.check_box,
                          ),
                          onPressed: _selectAllFiles,
                          tooltip: _isMultiSelectMode ? '取消选择' : '全选',
                          color: iconColor,
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: singleSelection ? _copySelected : null,
                          tooltip: '复制',
                          color: singleSelection ? iconColor : disabledIconColor,
                        ),

                        const SizedBox(width: 3),

                        IconButton(
                          icon: const Icon(Icons.paste),
                          onPressed: _clipboardFilePath != null ? _pasteFile : null,
                          tooltip: '粘贴',
                          color: _clipboardFilePath != null ? iconColor : disabledIconColor,
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          icon: const Icon(Icons.cut),
                          tooltip: '剪切',
                          onPressed: singleSelection ? _cutSelected : null,
                          color: singleSelection ? iconColor : disabledIconColor,
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
                          label: Text('属性', style: TextStyle(color: singleSelection ? iconColor : disabledIconColor)),
                          onPressed: singleSelection ? _showFileDetails : null,
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.info),
                          onPressed: singleSelection ? _showFileDetails : null,
                          tooltip: '属性',
                          color: singleSelection ? iconColor : disabledIconColor,
                        ),
                      
                      const SizedBox(width: 3),
                      if (isWideScreen)
                        TextButton.icon(
                          icon: Icon(Icons.view_module, color: disabledIconColor),
                          label: Text('切换视图', style: TextStyle(color: disabledIconColor)),
                          onPressed: () {
                            setState(() {
                              _viewMode = _viewMode == ViewMode.list ? ViewMode.icon : ViewMode.list;
                            });
                          },
                        )
                        else IconButton(
                          icon: Icon(Icons.view_module, color: disabledIconColor),
                          tooltip: '切换视图',
                          onPressed: () {
                            setState(() {
                              _viewMode = _viewMode == ViewMode.list ? ViewMode.icon : ViewMode.list;
                            });
                          },
                        )
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
                    ? const Center(child: Text('目录为空'))
                    : _viewMode == ViewMode.list
                        ? _buildListView()
                        : _buildGridView(),
          ),
        ],
      ),
    );
  }
}