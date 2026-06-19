// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:connssh/components/file_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/setting_service.dart';
import '../services/ssh_service.dart';
import '../services/notification_service.dart';
import 'package:path/path.dart' as path;
import '../components/twofa_dialog.dart';
import '../widgets/app_style.dart';
import '../widgets/app_toast.dart';

enum ViewMode { list, icon }

class ClipboardItem {
  final String path;
  final bool isDirectory;
  final String name;

  ClipboardItem({
    required this.path,
    required this.isDirectory,
    required this.name,
  });
}

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

class _SftpPageState extends State<SftpPage> with TickerProviderStateMixin {
  final SshService _sshService = SshService();
  final SettingsService _settingsService = SettingsService();
  final NotificationService _notificationService = NotificationService();

  SSHClient? _sshClient;
  dynamic _sftpClient;
  final List<ClipboardItem> _clipboardItems = [];
  bool _clipboardIsCut = false;
  List<dynamic> _fileList = [];
  String _currentPath = '/';
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = '连接中...';
  final Set<String> _selectedFiles = {};
  bool _isMultiSelectMode = false;
  double _uploadProgress = 0.0;
  double _downloadProgress = 0.0;
  String _currentOperation = '';
  bool _cancelOperation = false;
  dynamic _currentUploader;
  dynamic _currentDownloadFile;
  ViewMode _viewMode = ViewMode.list;
  DateTime? _lastBackPressedTime;
  bool _isProgressDialogOpen = false;
  bool _isSudoPromptOpen = false;
  bool _sftpMenuIsOpen = false;
  bool _needsTwoFactorAuth = false;
  Completer<String?>? _twoFactorCompleter;

  String? _rememberedSudoPassword;
  // ignore: unused_field
  bool _rememberSudoPassword = false;

  static const int _largeFileThreshold = 1024 * 1024;

  bool get _ismobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();

    // 初始化通知服务
    _notificationService.initialize();

    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _loadingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _loadingAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _preConnection();
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

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Theme.of(context).primaryColor;
    return Colors.red;
  }

  void _showToast(
    String message, {
    IconData icon = Icons.info_outline_rounded,
    Duration? duration,
  }) {
    if (!mounted) return;
    AppToast.show(
      context,
      message: message,
      icon: icon,
      duration: duration,
    );
  }

  Future<void> _preConnection() async {
    try {
      final settings = await _settingsService.getSettings();
      setState(() {
        _currentPath =
            widget.connection.sftpPath ?? settings.defaultSftpPath ?? '/';
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
        _isMultiSelectMode = false;
        _selectedFiles.clear();
        _isLoading = true;
        _isConnecting = true;
        _status = '连接中...';
      });

      _sshClient = await _sshService.connect(
        widget.connection,
        widget.credential,
        onTwoFactorAuth: (connectionName, host, prompt) async {
          return await _showTwoFactorAuthDialog(connectionName, host, prompt);
        },
      );

      _sftpClient = await _sshClient!.sftp();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = '已连接';
        });
        // 显示保持后台活动的通知
        _notificationService.updateConnectionNotification(
          connectionName: widget.connection.name,
          host: widget.connection.host,
          port: widget.connection.port,
          status: '已连接 (SFTP)',
        );
      }

      try {
        await _loadDirectory(_currentPath);
      } catch (e) {
        await _loadDirectory('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _isLoading = false;
          _status = '连接失败: $e';
        });
        // 取消通知
        await _notificationService.cancelConnectionNotification();
        _showErrorDialog('SFTP连接失败', e.toString());
      }
    }
  }

  Future<String?> _showTwoFactorAuthDialog(
    String connectionName,
    String host,
    String prompt,
  ) async {
    final completer = Completer<String?>();
    _twoFactorCompleter = completer;

    final code = await TwoFactorAuthDialog.show(
      context,
      connectionName: connectionName,
      host: host,
      prompt: prompt,
    );

    _twoFactorCompleter = null;
    if (mounted) {
      setState(() {
        _needsTwoFactorAuth = false;
      });
    }

    return code;
  }

  Future<bool> _checkConnection() async {
    if (!_isConnected || _sshClient == null || _sftpClient == null) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接已断开';
        });
        _showErrorDialog('连接已断开', '请重新连接服务器');
      }
      return false;
    }

    try {
      await _sshClient!.execute('pwd').timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '连接已断开';
        });
        _showErrorDialog('连接已断开', '请重新连接服务器');
      }
      return false;
    }
  }

  Widget _buildSingleRowToolbar(
    Color iconColor,
    Color disabledIconColor,
    bool hasSelection,
    bool singleSelection,
    bool isWideScreen,
  ) {
    bool showEditButton =
        _isMultiSelectMode &&
        _selectedFiles.length == 1 &&
        !_isSelectedItemDirectory();

    bool uploadEnabled =
        !_isMultiSelectMode ||
        (_isMultiSelectMode &&
            _selectedFiles.isEmpty &&
            !_isSelectedItemDirectory());

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (_currentPath != '/')
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _isConnected ? _goToParentDirectory : null,
                    tooltip: '返回上一级',
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.circle_outlined),
                    onPressed: null,
                    tooltip: '/',
                  ),
                const SizedBox(width: 3),
                if (showEditButton)
                  _buildIconButton(
                    Icons.edit,
                    '编辑',
                    _editSelectedFile,
                    iconColor,
                  )
                else
                  _buildIconButton(
                    Icons.upload,
                    '上传',
                    uploadEnabled ? _uploadFile : null,
                    uploadEnabled ? iconColor : disabledIconColor,
                  ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.download,
                  '下载',
                  hasSelection ? _downloadSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.delete,
                  '删除',
                  hasSelection ? _deleteSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.create_new_folder,
                  '新建',
                  _showCreateDialog,
                  iconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.drive_file_rename_outline,
                  '重命名',
                  singleSelection ? _renameFile : null,
                  singleSelection ? iconColor : disabledIconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  _isMultiSelectMode
                      ? Icons.check_box_outline_blank
                      : Icons.check_box,
                  _isMultiSelectMode ? '取消选择' : '全选',
                  _selectAllFiles,
                  iconColor,
                ),
                _buildIconButton(
                  Icons.copy,
                  '复制',
                  hasSelection ? _copySelected : null,
                  hasSelection ? iconColor : disabledIconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.cut,
                  '剪切',
                  hasSelection ? _cutSelected : null,
                  hasSelection ? iconColor : disabledIconColor,
                ),
                const SizedBox(width: 3),
                _buildIconButton(
                  Icons.paste,
                  '粘贴',
                  _clipboardItems.isNotEmpty ? _pasteFile : null,
                  _clipboardItems.isNotEmpty ? iconColor : disabledIconColor,
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
                  icon: Icon(
                    Icons.info,
                    color: singleSelection ? iconColor : disabledIconColor,
                  ),
                  label: Text(
                    '属性',
                    style: TextStyle(
                      color: singleSelection ? iconColor : disabledIconColor,
                    ),
                  ),
                  onPressed: singleSelection ? _showFileDetails : null,
                )
              else
                _buildIconButton(
                  Icons.info,
                  '属性',
                  singleSelection ? _showFileDetails : null,
                  singleSelection ? iconColor : disabledIconColor,
                ),
              const SizedBox(width: 3),
              if (isWideScreen)
                TextButton.icon(
                  icon: Icon(Icons.view_module, color: iconColor),
                  label: Text('切换视图', style: TextStyle(color: iconColor)),
                  onPressed: () => setState(
                    () => _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.icon
                        : ViewMode.list,
                  ),
                )
              else
                _buildIconButton(
                  Icons.view_module,
                  '切换视图',
                  () => setState(
                    () => _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.icon
                        : ViewMode.list,
                  ),
                  iconColor,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDoubleRowToolbar(
    Color iconColor,
    Color disabledIconColor,
    bool hasSelection,
    bool singleSelection,
  ) {
    double buttonWidth = (MediaQuery.of(context).size.width - 4) / 6;

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              SizedBox(
                width: buttonWidth,
                child: _currentPath != '/'
                    ? _buildIconButton(
                        Icons.arrow_back,
                        '返回上级',
                        _isConnected ? _goToParentDirectory : null,
                        iconColor,
                        iconSize: 20,
                      )
                    : _buildIconButton(
                        Icons.circle_outlined,
                        '/',
                        null,
                        disabledIconColor,
                        iconSize: 20,
                      ),
              ),
              SizedBox(
                width: buttonWidth,
                child:
                    _isMultiSelectMode &&
                        _selectedFiles.length == 1 &&
                        !_isSelectedItemDirectory()
                    ? _buildIconButton(
                        Icons.edit,
                        '编辑',
                        _editSelectedFile,
                        iconColor,
                        iconSize: 20,
                      )
                    : _buildIconButton(
                        Icons.upload,
                        '上传',
                        !_isMultiSelectMode ||
                                (_isMultiSelectMode &&
                                    _selectedFiles.isEmpty &&
                                    !_isSelectedItemDirectory())
                            ? _uploadFile
                            : null,
                        !_isMultiSelectMode ||
                                (_isMultiSelectMode &&
                                    _selectedFiles.isEmpty &&
                                    !_isSelectedItemDirectory())
                            ? iconColor
                            : disabledIconColor,
                        iconSize: 20,
                      ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.download,
                  '下载',
                  hasSelection ? _downloadSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.delete,
                  '删除',
                  hasSelection ? _deleteSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.create_new_folder,
                  '新建',
                  _showCreateDialog,
                  iconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  _isMultiSelectMode
                      ? Icons.check_box_outline_blank
                      : Icons.check_box,
                  _isMultiSelectMode ? '取消选择' : '全选',
                  _selectAllFiles,
                  iconColor,
                  iconSize: 20,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: Row(
            children: [
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.copy,
                  '复制',
                  hasSelection ? _copySelected : null,
                  hasSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.cut,
                  '剪切',
                  hasSelection ? _cutSelected : null,
                  hasSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.paste,
                  '粘贴',
                  _clipboardItems.isNotEmpty ? _pasteFile : null,
                  _clipboardItems.isNotEmpty ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.drive_file_rename_outline,
                  '重命名',
                  singleSelection ? _renameFile : null,
                  singleSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.info,
                  '属性',
                  singleSelection ? _showFileDetails : null,
                  singleSelection ? iconColor : disabledIconColor,
                  iconSize: 20,
                ),
              ),
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                  Icons.view_module,
                  '切换视图',
                  () => setState(
                    () => _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.icon
                        : ViewMode.list,
                  ),
                  iconColor,
                  iconSize: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isSelectedItemDirectory() {
    if (_selectedFiles.isEmpty) return false;

    final filename = _selectedFiles.first;
    try {
      final fileItem = _fileList.firstWhere(
        (item) => item.filename.toString() == filename,
      );
      return fileItem.attr?.isDirectory == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _showCreateDialog() async {
    if (!await _checkConnection()) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建'),
        content: const Text('请选择要创建的类型'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              _createFile();
            },
            child: const Text('文件'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _createDirectory();
            },
            child: const Text('文件夹'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSelectedFile() async {
    if (_selectedFiles.length != 1) return;

    if (!await _checkConnection()) return;

    final filename = _selectedFiles.first;

    if (_isSelectedItemDirectory()) {
      _showErrorDialog('编辑失败', '不能编辑文件夹');
      return;
    }

    final remotePath = _joinPath(_currentPath, filename);

    try {
      final stat = await _sftpClient.stat(remotePath);
      final int fileSize = (stat.size ?? 0).toInt();
      if (fileSize > _largeFileThreshold) {
        final bool? shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('文件较大'),
            content: Text(
              '文件 "$filename" 大小为 ${_formatFileSize(fileSize)}，'
              '超过1MB的大文件在编辑器中打开可能会产生卡顿。\n\n'
              '确定要继续吗？',
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          return;
        }
      }

      _showProgressDialog('下载文件', showCancel: false);

      final remote = await _sftpClient.open(remotePath);
      _currentDownloadFile = remote;

      final bytes = await remote.readBytes();
      final content = utf8.decode(bytes, allowMalformed: true);

      await remote.close();
      _currentDownloadFile = null;

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FileEditorPage(
              filename: filename,
              remotePath: remotePath,
              initialContent: content,
              saveCallback: _saveFile,
            ),
            settings: RouteSettings(arguments: _saveFile),
          ),
        );

        await _loadDirectory(_currentPath);
        _clearSelectionAndExitMultiSelect();
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('下载文件失败', e.toString());
      }
    }
  }

  Future<void> _loadDirectory(String dirPath) async {
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
      if (!await _checkConnection()) return;

      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog('读取目录失败', '$e');
    }
  }

  String _normalizePath(String rawPath) {
    String normalized = rawPath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/');
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

  Future<void> _renameFile() async {
    if (_selectedFiles.length != 1) {
      _showErrorDialog('重命名失败', '请重新选择');
      return;
    }

    if (!await _checkConnection()) return;

    final oldName = _selectedFiles.first;
    final oldPath = _joinPath(_currentPath, oldName);

    final textController = TextEditingController(text: oldName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '新文件名',
            hintText: '请输入新的文件名称',
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
              final newName = textController.text.trim();
              if (newName.isEmpty) {
                _showErrorDialog('重命名失败', '名称不能为空');
                return;
              }
              if (newName == oldName) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop();
              await _renameFileAction(oldPath, oldName, newName);
            },
            child: const Text('重命名'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFileAction(
    String oldPath,
    String oldName,
    String newName,
  ) async {
    final newPath = _joinPath(_currentPath, newName);

    try {
      try {
        await _sftpClient.stat(newPath);
        _showErrorDialog('重命名', '"$newName" 已存在');
        return;
      } catch (e) {}

      await _sftpClient.rename(oldPath, newPath);

      if (mounted) {
        _showToast('重命名成功: $oldName → $newName', icon: Icons.check_circle_outline_rounded);
        _clearSelectionAndExitMultiSelect();
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (_isPermissionDeniedError(e)) {
        await _trySudoRename(oldPath, newPath, oldName, newName);
      } else {
        _showErrorDialog('重命名失败', e.toString());
      }
    }
  }

  Future<void> _uploadFile() async {
    if (!await _checkConnection()) return;

    try {
      if (Platform.isAndroid) {
        FilePickerResult? result = await FilePicker.pickFiles(
          allowMultiple: true,
          type: FileType.any,
          dialogTitle: '选择要上传的文件',
        );

        if (result == null || result.files.isEmpty) return;

        _showProgressDialog('上传文件', showCancel: true);
        _cancelOperation = false;

        int successCount = 0;
        int totalCount = result.files.length;
        int skippedCount = 0;

        for (int i = 0; i < totalCount; i++) {
          if (!await _checkConnection()) break;
          if (_cancelOperation) break;

          final platformFile = result.files[i];
          final filePath = platformFile.path;

          if (filePath == null || filePath.isEmpty) {
            debugPrint('文件路径为空: ${platformFile.name}');
            continue;
          }

          try {
            await _uploadFileWithPath(
              platformFile.name,
              filePath,
              isMultiple: true,
              index: i + 1,
              total: totalCount,
            );
            successCount++;
          } catch (e) {
            debugPrint('上传文件 ${platformFile.name} 失败: $e');
          }
        }

        if (mounted) {
          if (!_cancelOperation) {
            String message = '上传完成: $successCount / $totalCount 个文件';
            if (skippedCount > 0) message += ' (跳过 $skippedCount 个文件)';

            _showToast(
              message,
              icon: Icons.check_circle_outline_rounded,
              duration: const Duration(seconds: 3),
            );

            await _loadDirectory(_currentPath);
          }
        }
      } else {
        const XTypeGroup typeGroup = XTypeGroup(
          label: 'files',
          extensions: <String>[],
        );
        final XFile? file = await openFile(
          acceptedTypeGroups: <XTypeGroup>[typeGroup],
        );

        if (file == null) return;

        await _uploadFileWithPath(file.name, file.path);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('上传失败', e.toString());
      }
    } finally {
      _currentUploader = null;
      _uploadProgress = 0;
      _currentOperation = '';
      _cancelOperation = false;
    }
  }

  Future<void> _uploadFileWithPath(
    String filename,
    String filePath, {
    bool isMultiple = false,
    int index = 1,
    int total = 1,
  }) async {
    _showProgressDialog('上传文件', showCancel: true);
    _cancelOperation = false;

    final localFile = File(filePath);
    if (!await localFile.exists()) {
      debugPrint('文件不存在: $filePath');
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      return;
    }

    final remotePath = _joinPath(_currentPath, filename);
    bool fileExists = false;
    try {
      await _sftpClient.stat(remotePath);
      fileExists = true;
    } catch (e) {
      fileExists = false;
    }

    if (fileExists) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}

        final shouldOverwrite = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('文件已存在'),
            content: Text('文件 "$filename" 已存在，是否覆盖？'),
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

        if (shouldOverwrite == false) {
          return;
        }
      }
      _showProgressDialog('上传文件', showCancel: true);
    }

    final fileSize = await localFile.length();
    setState(() {
      if (isMultiple) {
        _currentOperation = '正在上传: $filename ($index / $total)';
      } else {
        _currentOperation = '正在上传: $filename';
      }
      _uploadProgress = 0.0;
    });

    try {
      // 尝试正常上传
      await _uploadToSftp(localFile, remotePath, filename, fileSize);
    } catch (e) {
      // 权限不足时尝试使用root上传
      if (_isPermissionDeniedError(e)) {
        debugPrint('权限不足，尝试使用root上传: $e');
        await _trySudoUpload(localFile, remotePath, filename, fileSize);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _uploadToSftp(
    File localFile,
    String remotePath,
    String filename,
    int fileSize,
  ) async {
    final remote = await _sftpClient.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    _currentUploader = remote;

    int offset = 0;
    final stream = localFile.openRead();
    await for (final chunk in stream) {
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

    await remote.close();
    _currentUploader = null;

    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!_cancelOperation) {
        _showToast(
          '上传完成: $filename',
          icon: Icons.check_circle_outline_rounded,
          duration: const Duration(seconds: 3),
        );

        await _loadDirectory(_currentPath);
      }
    }
  }

  Future<void> _deleteSelectedFilesAction() async {
    if (!await _checkConnection()) return;

    try {
      int successCount = 0;
      int totalCount = _selectedFiles.length;

      _showProgressDialog('删除文件', showCancel: true);
      _cancelOperation = false;

      for (int i = 0; i < totalCount; i++) {
        if (!await _checkConnection()) break;
        if (_cancelOperation) break;

        final filename = _selectedFiles.elementAt(i);
        final itemPath = _joinPath(_currentPath, filename);

        setState(() {
          _currentOperation = '正在删除: $filename (${i + 1} / $totalCount)';
        });

        try {
          dynamic stat;
          try {
            stat = await _sftpClient.stat(itemPath);
          } catch (_) {
            stat = null;
          }

          if (stat != null && stat.isDirectory) {
            await _sftpClient.removeDir(itemPath);
          } else {
            await _sftpClient.remove(itemPath);
          }
          successCount++;
        } catch (e) {
          // 权限不足时尝试sudo删除
          if (_isPermissionDeniedError(e)) {
            debugPrint('权限不足，尝试sudo删除: $filename');
            bool isDir = false;
            try {
              final stat = await _sftpClient.stat(itemPath);
              isDir = stat.isDirectory;
            } catch (_) {
              isDir = false;
            }
            final success = await _trySudoDelete(itemPath, isDir);
            if (success) {
              successCount++;
            }
          } else {
            debugPrint('删除 $filename 失败: $e');
          }
        }
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!_cancelOperation && mounted) {
        _showToast(
          '删除成功: $successCount/${_selectedFiles.length}',
          icon: Icons.check_circle_outline_rounded,
        );
        _clearSelectionAndExitMultiSelect();
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('删除失败', e.toString());
      }
    } finally {
      _currentOperation = '';
    }
  }

  String _escapeShellArgument(String argument) {
    return argument.replaceAll("'", "'\\''");
  }

  Future<void> _downloadSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;
    if (!await _checkConnection()) return;

    List<String> filesToDownload = [];
    for (String filename in _selectedFiles) {
      try {
        final fileItem = _fileList.firstWhere(
          (item) => item.filename.toString() == filename,
        );
        if (fileItem.attr?.isDirectory != true) {
          filesToDownload.add(filename);
        } else {
          if (mounted) {
            _showToast(
              '暂不支持下载目录: $filename',
              duration: const Duration(seconds: 2),
            );
          }
        }
      } catch (e) {
        debugPrint('找不到文件: $filename');
      }
    }

    if (filesToDownload.isEmpty) {
      if (mounted) {
        _showToast('没有有效的文件可以下载');
      }
      return;
    }

    if (Platform.isAndroid) {
      await _downloadForAndroid(filesToDownload);
    } else {
      // Windows、Linux、macOS等桌面平台
      await _downloadForDesktop(filesToDownload);
    }
  }

  // 桌面平台的下载逻辑
  Future<void> _downloadForDesktop(List<String> filesToDownload) async {
    if (filesToDownload.isEmpty) return;

    String? saveDir;

    // 单个文件：使用saveFile让用户选择保存位置和文件名
    if (filesToDownload.length == 1) {
      final filename = filesToDownload.first;
      final safeFilename = _getSafeFileName(filename);

      try {
        final String? result = await FilePicker.saveFile(
          dialogTitle: '保存文件',
          fileName: safeFilename,
          allowedExtensions: _getFileExtensions(safeFilename),
          type: FileType.custom,
        );

        if (result == null) {
          if (mounted) {
            _showToast('已取消下载');
          }
          return;
        }

        saveDir = path.dirname(result);
        final saveFilePath = result;
        final filenameOnly = path.basename(saveFilePath);

        // 下载单个文件
        await _downloadSingleFileDesktop(
          _joinPath(_currentPath, filename),
          saveFilePath,
          filenameOnly,
          filesToDownload,
        );
      } catch (e) {
        if (mounted) {
          _showErrorDialog('下载失败', e.toString());
        }
      }
    } else {
      // 多个文件：让用户选择目录
      try {
        final String? selectedDir = await FilePicker.getDirectoryPath(
          dialogTitle: '选择保存目录',
        );

        if (selectedDir == null || selectedDir.isEmpty) {
          if (mounted) {
            _showToast('已取消下载');
          }
          return;
        }

        saveDir = selectedDir;

        // 下载多个文件
        await _downloadMultipleFilesDesktop(filesToDownload, saveDir);
      } catch (e) {
        if (mounted) {
          _showErrorDialog('下载失败', e.toString());
        }
      }
    }
  }

  // 下载单个文件（桌面平台）
  Future<void> _downloadSingleFileDesktop(
    String remotePath,
    String localFilePath,
    String filename,
    List<String> allFiles,
  ) async {
    _showProgressDialog('下载文件', showCancel: true);
    _cancelOperation = false;

    try {
      final stat = await _sftpClient.stat(remotePath);
      final int fileSize = (stat.size ?? 0).toInt();

      setState(() {
        _currentOperation = '正在下载: $filename';
        _downloadProgress = 0.0;
      });

      await _downloadSingleFile(remotePath, localFilePath, filename, fileSize);

      if (mounted && !_cancelOperation) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}

        _showToast('下载完成: $filename', icon: Icons.check_circle_outline_rounded);

        _clearSelectionAndExitMultiSelect();
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('下载失败', e.toString());
      }
    } finally {
      _downloadProgress = 0;
      _currentDownloadFile = null;
      _currentOperation = '';
      _cancelOperation = false;
    }
  }

  // 下载多个文件（桌面平台）
  Future<void> _downloadMultipleFilesDesktop(
    List<String> filesToDownload,
    String saveDir,
  ) async {
    _showProgressDialog('下载文件', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int total = filesToDownload.length;

    for (int i = 0; i < total; i++) {
      if (_cancelOperation) break;
      if (!await _checkConnection()) break;

      final filename = filesToDownload[i];
      final remotePath = _joinPath(_currentPath, filename);
      final safeFilename = _getSafeFileName(filename);
      final localFilePath = path.join(saveDir, safeFilename);

      setState(() {
        _currentOperation = '正在下载: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      try {
        final stat = await _sftpClient.stat(remotePath);
        final int fileSize = (stat.size ?? 0).toInt();

        if (fileSize <= 0) {
          await File(localFilePath).writeAsBytes([]);
          successCount++;
          continue;
        }

        final localFile = File(localFilePath);
        if (await localFile.exists()) {
          if (mounted) {
            final shouldOverwrite = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  title: const Text('文件已存在'),
                  content: Text('文件 "$safeFilename" 已存在，是否覆盖？'),
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('跳过'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('覆盖'),
                    ),
                  ],
                );
              },
            );

            if (shouldOverwrite == false) {
              continue;
            }
          }
        }

        await _downloadSingleFile(
          remotePath,
          localFilePath,
          filename,
          fileSize,
        );
        successCount++;
      } catch (e) {
        debugPrint('下载文件 $filename 失败: $e');
        try {
          final incompleteFile = File(localFilePath);
          if (await incompleteFile.exists()) {
            await incompleteFile.delete();
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!_cancelOperation) {
        if (successCount > 0) {
          _showDownloadCompleteDialog(saveDir, successCount, total);
        } else {
          _showToast('下载失败', icon: Icons.error_outline_rounded);
        }
        _clearSelectionAndExitMultiSelect();
      }
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
    _cancelOperation = false;
  }

  // 下载逻辑：使用平台标准目录保存下载文件
  Future<void> _downloadForAndroid(List<String> filesToDownload) async {
    final String saveDir =
        await SettingsService.getPlatformDefaultDownloadPath();

    try {
      final dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      debugPrint('使用标准下载目录: $saveDir');
    } catch (e) {
      debugPrint('创建目录失败: $e');
      if (mounted) {
        _showErrorDialog('目录创建失败', '无法创建目录: $saveDir\n错误: $e');
      }
      return;
    }

    _showProgressDialog('下载文件', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int total = filesToDownload.length;

    for (int i = 0; i < total; i++) {
      if (_cancelOperation) break;
      if (!await _checkConnection()) break;

      final filename = filesToDownload[i];
      final remotePath = _joinPath(_currentPath, filename);
      final safeFilename = _getSafeFileName(filename);
      final localFilePath = path.join(saveDir, safeFilename);

      setState(() {
        _currentOperation = '正在下载: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      try {
        final stat = await _sftpClient.stat(remotePath);
        final int fileSize = (stat.size ?? 0).toInt();

        if (fileSize <= 0) {
          await File(localFilePath).writeAsBytes([]);
          successCount++;
          continue;
        }

        final localFile = File(localFilePath);
        if (await localFile.exists()) {
          if (mounted) {
            final shouldOverwrite = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return AlertDialog(
                  title: const Text('文件已存在'),
                  content: Text('文件 "$safeFilename" 已存在，是否覆盖？'),
                  actions: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('跳过'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('覆盖'),
                    ),
                  ],
                );
              },
            );

            if (shouldOverwrite == false) {
              continue;
            }
          }
        }

        await _downloadSingleFile(
          remotePath,
          localFilePath,
          filename,
          fileSize,
        );
        successCount++;
      } catch (e) {
        debugPrint('下载文件 $filename 失败: $e');
        try {
          final incompleteFile = File(localFilePath);
          if (await incompleteFile.exists()) {
            await incompleteFile.delete();
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!_cancelOperation) {
        if (successCount > 0) {
          _showDownloadCompleteDialog(saveDir, successCount, total);
        } else {
          _showToast('下载失败', icon: Icons.error_outline_rounded);
        }
        _clearSelectionAndExitMultiSelect();
      }
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
    _cancelOperation = false;
  }

  // 下载文件到内存
  List<String> _getFileExtensions(String filename) {
    final extIndex = filename.lastIndexOf('.');
    if (extIndex != -1 && extIndex < filename.length - 1) {
      final extension = filename.substring(extIndex + 1).toLowerCase();
      return [extension];
    }
    return [];
  }

  Future<void> _downloadSingleFile(
    String remotePath,
    String localFilePath,
    String filename,
    int fileSize,
  ) async {
    RandomAccessFile? localFile;
    dynamic remote;

    try {
      remote = await _sftpClient.open(remotePath);
      _currentDownloadFile = remote;

      final file = File(localFilePath);
      localFile = await file.open(mode: FileMode.write);

      num offset = 0;
      const int chunkSize = 32 * 1024;

      while (offset < fileSize && !_cancelOperation) {
        if (!await _checkConnection()) break;

        final bytesToRead = (fileSize - offset) > chunkSize
            ? chunkSize
            : (fileSize - offset);

        final chunk = await remote.readBytes(
          offset: offset,
          length: bytesToRead,
        );

        if (chunk.isEmpty) {
          debugPrint('下载完成或文件为空: $filename');
          break;
        }

        await localFile.writeFrom(chunk, 0, chunk.length);
        offset += chunk.length;

        if (mounted) {
          setState(() {
            _downloadProgress = fileSize > 0 ? offset / fileSize : 0.0;
          });
        }
      }

      await localFile.flush();
      await localFile.close();
      await remote.close();
      _currentDownloadFile = null;

      debugPrint('文件下载完成: $filename -> $localFilePath');
    } catch (e) {
      debugPrint('下载文件 $filename 失败: $e');

      try {
        await localFile?.close();
        final tempFile = File(localFilePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (cleanupError) {
        debugPrint('清理失败文件时出错: $cleanupError');
      }

      rethrow;
    } finally {
      try {
        await localFile?.close();
      } catch (_) {}
      try {
        await remote?.close();
      } catch (_) {}
      _currentDownloadFile = null;
    }
  }

  void _showDownloadCompleteDialog(
    String saveDir,
    int successCount,
    int totalCount,
  ) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('下载完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('成功下载: $successCount / $totalCount 个文件'),
            const SizedBox(height: 16),
            const Text('保存位置:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(saveDir, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: saveDir));
              _showToast('路径已复制到剪贴板', icon: Icons.copy_rounded);
              Navigator.of(context).pop();
            },
            child: const Text('复制路径'),
          ),
        ],
      ),
    );
  }

  String _getSafeFileName(String filename) {
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
    }
    _currentUploader = null;
    _currentDownloadFile = null;

    if (mounted) {
      setState(() {
        _uploadProgress = 0.0;
        _downloadProgress = 0.0;
        _currentOperation = '';
      });

      if (_isProgressDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        _showToast('操作已取消');
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

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
      _showErrorDialog('读取文件属性失败', e.toString());
    }
  }

  Widget _buildListView({Key? key}) {
    return ListView.builder(
      key: key,
      itemCount: _fileList.length,
      itemBuilder: _buildFileItem,
    );
  }

  Widget _buildGridView({Key? key}) {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = _getCrossAxisCount(screenWidth);

    return GridView.builder(
      key: key,
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
              border: isSelected
                  ? Border.all(color: Colors.blueAccent, width: 1.3)
                  : null,
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
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
                ? octalString.substring(octalString.length - 3)
                : octalString;
            return _octalToPermissionString(lastDigits);
          }
        }
        if (mode.length >= 3) {
          final lastDigits = mode.length > 3
              ? mode.substring(mode.length - 3)
              : mode;
          if (RegExp(r'^\d+$').hasMatch(lastDigits))
            return _octalToPermissionString(lastDigits);
        }
        return '---------';
      }
      if (mode is int) return _intToPermissionString(mode);

      final modeStr = mode.toString();
      final digitMatch = RegExp(r'(\d{3,4})').firstMatch(modeStr);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        final lastThree = digits.length > 3
            ? digits.substring(digits.length - 3)
            : digits;
        return _octalToPermissionString(lastThree);
      }
      if (modeStr.length >= 9 && RegExp(r'^[rwsxt-]{9,}$').hasMatch(modeStr)) {
        return modeStr.length > 9
            ? modeStr.substring(modeStr.length - 9)
            : modeStr;
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

  Future<void> _createFile() async {
    if (!await _checkConnection()) return;

    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '文件名称',
            hintText: '输入新文件名称',
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
                await _createFileAction(textController.text.trim());
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDirectoryAction(String dirName) async {
    if (!await _checkConnection()) return;

    final newDirPath = _joinPath(_currentPath, dirName);

    try {
      await _sftpClient.mkdir(newDirPath);
      if (mounted) {
        _showToast('文件夹创建成功', icon: Icons.check_circle_outline_rounded);
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      // 权限不足时尝试sudo创建
      if (_isPermissionDeniedError(e)) {
        await _trySudoCreateDirectory(newDirPath);
      } else {
        _showErrorDialog('创建文件夹失败', e.toString());
      }
    }
  }

  Future<void> _createFileAction(String fileName) async {
    if (!await _checkConnection()) return;

    final newFilePath = _joinPath(_currentPath, fileName);

    try {
      final remote = await _sftpClient.open(
        newFilePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
      );
      await remote.close();

      if (mounted) {
        _showToast('文件创建成功', icon: Icons.check_circle_outline_rounded);
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      // 权限不足时尝试sudo创建
      if (_isPermissionDeniedError(e)) {
        await _trySudoCreateFile(newFilePath);
      } else {
        _showErrorDialog('创建文件失败', e.toString());
      }
    }
  }

  Future<bool> _saveFile(
    String remotePath,
    Uint8List data,
    String filename,
  ) async {
    if (!await _checkConnection()) return false; // 连接失败返回 false

    try {
      _showProgressDialog('保存文件', showCancel: false);

      final remote = await _sftpClient.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      await remote.writeBytes(data);
      await remote.close();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showToast('文件保存成功', icon: Icons.check_circle_outline_rounded);
      }
      return true;
    } catch (e) {
      // 权限不足时尝试sudo保存
      if (_isPermissionDeniedError(e)) {
        return await _trySudoSaveFile(remotePath, data, filename);
      } else if (mounted) {
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}
          _showErrorDialog('保存文件失败', e.toString());
      }
      return false;
    }
  }

  Future<bool> _trySudoSaveFile(
    String remotePath,
    Uint8List data,
    String filename,
  ) async {
    final password = await _showSudoPasswordDialog('保存文件');
    if (password == null || password.isEmpty) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      return false;
    }

    final tempPath = '/tmp/${DateTime.now().millisecondsSinceEpoch}_$filename';
    try {
      final remote = await _sftpClient.open(
        tempPath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      await remote.writeBytes(data);
      await remote.close();

      final command = 'mv "$tempPath" "$remotePath"';
      final success = await _executeSudoCommand(command, password);

      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}

        if (success) {
          _showToast('文件保存成功', icon: Icons.check_circle_outline_rounded);
          return true;
        } else {
          try {
            await _sftpClient.stat(remotePath);
            _showToast('文件保存成功', icon: Icons.check_circle_outline_rounded);
            return true;
          } catch (e) {
            try {
              await _sftpClient.remove(tempPath);
            } catch (_) {}
            _showErrorDialog('保存失败', '移动文件失败');
            return false;
          }
        }
      }
      return success;
    } catch (e) {
      debugPrint('sudo保存失败: $e');
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('保存失败', e.toString());
      }
      return false;
    }
  }

  Future<void> _copySelected() async {
    if (_selectedFiles.isEmpty) return;

    if (!await _checkConnection()) return;

    final newClipboardItems = <ClipboardItem>[];

    for (final name in _selectedFiles) {
      final remotePath = _joinPath(_currentPath, name);

      try {
        final stat = await _sftpClient.stat(remotePath);
        if (!_hasReadPermission(stat)) {
          _showErrorDialog('复制失败', '没有读取 $name 的权限');
          return;
        }
        newClipboardItems.add(
          ClipboardItem(
            path: remotePath,
            isDirectory: stat.isDirectory,
            name: name,
          ),
        );
      } catch (e) {
        _showErrorDialog('复制失败', '无法访问 $name: $e');
        return;
      }
    }

    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(newClipboardItems);
      _clipboardIsCut = false;
    });

    if (mounted) {
      _showToast(
        '已复制 ${_selectedFiles.length} 个项目',
        icon: Icons.copy_rounded,
      );
      _clearSelectionAndExitMultiSelect();
    }
  }

  Future<void> _cutSelected() async {
    if (_selectedFiles.isEmpty) return;

    if (!await _checkConnection()) return;

    final newClipboardItems = <ClipboardItem>[];

    for (final name in _selectedFiles) {
      final remotePath = _joinPath(_currentPath, name);

      try {
        final stat = await _sftpClient.stat(remotePath);
        if (!_hasReadPermission(stat)) {
          _showErrorDialog('剪切失败', '没有修改 $name 的权限');
          return;
        }
        newClipboardItems.add(
          ClipboardItem(
            path: remotePath,
            isDirectory: stat.isDirectory,
            name: name,
          ),
        );
      } catch (e) {
        _showErrorDialog('剪切失败', '无法访问 $name: $e');
        return;
      }
    }

    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(newClipboardItems);
      _clipboardIsCut = true;
    });

    if (mounted) {
      _showToast('已剪切 ${_selectedFiles.length} 个项目', icon: Icons.content_cut_rounded);
      _clearSelectionAndExitMultiSelect();
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

  Future<void> _showProgressDialog(
    String title, {
    required bool showCancel,
  }) async {
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
            final progress = _uploadProgress > 0
                ? _uploadProgress
                : _downloadProgress;
            final displayedText = _currentOperation.isEmpty
                ? '处理中...'
                : _currentOperation;
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
                      OutlinedButton(
                        onPressed: _cancelCurrentOperation,
                        child: const Text('取消'),
                      ),
                    ]
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
    if (_clipboardItems.isEmpty) return;

    if (!await _checkConnection()) return;

    _showProgressDialog('粘贴文件', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int totalCount = _clipboardItems.length;

    for (int i = 0; i < totalCount; i++) {
      if (_cancelOperation) break;
      if (!await _checkConnection()) break;

      final item = _clipboardItems[i];
      final newPath = _joinPath(_currentPath, item.name);

      setState(() {
        _currentOperation = '正在粘贴: ${item.name} (${i + 1} / $totalCount)';
      });

      try {
        if (_clipboardIsCut) {
          // 尝试普通移动
          await _sftpClient.rename(item.path, newPath);
          successCount++;
        } else {
          // 尝试普通复制
          final cmd = item.isDirectory
              ? 'cp -r "${_escapeShellArgument(item.path)}" "${_escapeShellArgument(newPath)}"'
              : 'cp "${_escapeShellArgument(item.path)}" "${_escapeShellArgument(newPath)}"';

          final session = await _sshClient!.execute(cmd);
          await session.done;

          if (session.exitCode == 0) {
            successCount++;
          } else {
            final stderrBytes = await session.stderr.toList();
            String stderr = '';
            try {
              stderr = utf8.decode(
                Uint8List.fromList(stderrBytes.expand((x) => x).toList()),
                allowMalformed: true,
              );
            } catch (e) {
              stderr = '无法解析错误信息';
            }
            debugPrint('复制失败: $stderr');

            // 尝试sudo复制
            if (await _trySudoCopy(item.path, newPath, item.isDirectory)) {
              successCount++;
            }
          }
        }
      } catch (e) {
        debugPrint('粘贴 ${item.name} 失败: $e');
        // 尝试sudo操作
        if (_clipboardIsCut) {
          if (await _trySudoMove(item.path, newPath)) {
            successCount++;
          }
        }
      }
    }

    if (mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}

      if (!_cancelOperation && mounted) {
        _showToast('粘贴完成: $successCount / $totalCount 个项目', icon: Icons.check_circle_outline_rounded);

        if (_clipboardIsCut) {
          setState(() {
            _clipboardItems.clear();
            _clipboardIsCut = false;
          });
        }

        await _loadDirectory(_currentPath);
      }
    }

    _currentOperation = '';
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          OutlinedButton(
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
    setState(() {
      _isMultiSelectMode = false;
      _selectedFiles.clear();
    });
    if (_currentPath != '/') {
      String parentPath = _normalizePath(_currentPath);
      if (parentPath.endsWith('/') && parentPath != '/') {
        parentPath = parentPath.substring(0, parentPath.length - 1);
      }
      final lastSlashIndex = parentPath.lastIndexOf('/');
      parentPath = lastSlashIndex > 0
          ? parentPath.substring(0, lastSlashIndex)
          : '/';
      _loadDirectory(_normalizePath(parentPath));
    }
  }

  void _exitApp() => Navigator.of(context).pop();

  bool _isPermissionDeniedError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('permission denied') ||
        errorStr.contains('access denied') ||
        errorStr.contains('not permitted') ||
        errorStr.contains('权限不足') ||
        errorStr.contains('拒绝访问');
  }

  Future<String?> _showSudoPasswordDialog(String operation) async {
    // 如果已经记住了密码，直接返回记住的密码
    if (_rememberedSudoPassword != null &&
        _rememberedSudoPassword!.isNotEmpty) {
      debugPrint('使用记住的sudo密码');
      return _rememberedSudoPassword;
    }

    if (_isSudoPromptOpen) return null;
    _isSudoPromptOpen = true;

    final passwordController = TextEditingController();
    bool rememberPassword = false;

    String? result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('需要root权限 - $operation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('当前操作需要以root权限执行，请输入当前用户的密码：'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '请输入密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              onSubmitted: (value) {
                Navigator.of(context).pop(value);
              },
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (context, setState) {
                return CheckboxListTile(
                  title: const Text('本次会话记住密码', style: TextStyle(fontSize: 14)),
                  value: rememberPassword,
                  onChanged: (value) {
                    setState(() {
                      rememberPassword = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                );
              },
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(passwordController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    _isSudoPromptOpen = false;

    if (result!.isNotEmpty && rememberPassword) {
      setState(() {
        _rememberedSudoPassword = result;
        _rememberSudoPassword = true;
      });
      debugPrint('已记住sudo密码（本次会话）');
    }

    return result;
  }

  void _clearRememberedSudoPassword() {
    setState(() {
      _rememberedSudoPassword = null;
      _rememberSudoPassword = false;
    });
    debugPrint('已清除记住的sudo密码');
  }


  Future<void> _showMoreActionSheet() async {
    setState(() {
      _sftpMenuIsOpen = !_sftpMenuIsOpen;
    });
  }

  void _closeSftpMenu() {
    if (!mounted) return;
    setState(() => _sftpMenuIsOpen = false);
  }

  Widget _buildSftpFloatingMenu() {
    final entries = <AppActionMenuEntry>[
      AppActionMenuEntry(
        icon: Icons.refresh_rounded,
        label: '刷新',
        onTap: () {
          _closeSftpMenu();
          _loadDirectory(_currentPath);
        },
      ),
      AppActionMenuEntry(
        icon: Icons.sync_rounded,
        label: '重新连接',
        onTap: () {
          _closeSftpMenu();
          _connectSftp();
        },
      ),
      if (_rememberedSudoPassword != null)
        AppActionMenuEntry(
          icon: Icons.lock_reset_rounded,
          label: '忘记sudo密码',
          onTap: () {
            _closeSftpMenu();
            _clearRememberedSudoPassword();
            AppToast.show(
              context,
              message: '已清除记住的sudo密码',
              icon: Icons.check_circle_outline_rounded,
            );
          },
        ),
      AppActionMenuEntry(
        icon: Icons.logout_rounded,
        label: '退出',
        destructive: true,
        onTap: () {
          _closeSftpMenu();
          _exitApp();
        },
      ),
    ];

    return Positioned(
      right: 10,
      top: 8,
      child: AppAnimatedActionMenu(
        visible: _sftpMenuIsOpen,
        child: AppActionMenu(width: 150, entries: entries),
      ),
    );
  }

  Future<bool> _executeSudoCommand(String command, String password) async {
    try {
      final escapedPassword = password.replaceAll("'", "'\\''");
      final escapedCommand = command.replaceAll("'", "'\\''");

      final fullCommand =
          "echo '$escapedPassword' | sudo -S $escapedCommand 2>&1";

      debugPrint('执行sudo命令: ${fullCommand.replaceAll(password, '******')}');

      final session = await _sshClient!.execute(fullCommand);

      final outputBuffer = StringBuffer();

      session.stdout.listen(
        (List<int> data) {
          final text = utf8.decode(data, allowMalformed: true);
          outputBuffer.write(text);
        },
        onError: (e) {
          debugPrint('读取sudo命令输出时出错: $e');
        },
      );

      await session.done;

      final output = outputBuffer.toString().trim();
      final exitCode = session.exitCode ?? -1;

      debugPrint('sudo命令退出码: $exitCode');
      if (output.isNotEmpty) {
        debugPrint('sudo命令输出: $output');
      }

      final lowerOutput = output.toLowerCase();
      if (lowerOutput.contains('incorrect password') ||
          lowerOutput.contains('sorry, try again')) {
        debugPrint('sudo密码错误');
        // 如果密码错误，清除记住的密码
        if (_rememberedSudoPassword != null) {
          _clearRememberedSudoPassword();
          if (mounted) {
            _showErrorDialog('密码错误', '记住的密码已失效，请重新输入');
          }
        } else {
          if (mounted) {
            _showErrorDialog('密码错误', '请检查密码是否正确');
          }
        }
        return false;
      }

      if (lowerOutput.contains('permission denied') ||
          lowerOutput.contains('不允许的操作') ||
          lowerOutput.contains('operation not permitted')) {
        debugPrint('权限被拒绝');
        return false;
      }

      if (exitCode == 0) {
        return true;
      }

      if (output.isNotEmpty && !output.contains('[sudo] password for')) {
        debugPrint('sudo命令可能失败: $output');
      }

      if ((exitCode == -1) &&
          (output.isEmpty || output.contains('[sudo] password for'))) {
        debugPrint('sudo命令退出码异常但可能成功');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('执行sudo命令失败: $e');
      return false;
    }
  }

  Future<bool> _trySudoCopy(
    String sourcePath,
    String destPath,
    bool isDirectory,
  ) async {
    final password = await _showSudoPasswordDialog('复制文件');
    if (password == null || password.isEmpty) return false;

    final command = isDirectory
        ? 'cp -r "${_escapeShellArgument(sourcePath)}" "${_escapeShellArgument(destPath)}"'
        : 'cp "${_escapeShellArgument(sourcePath)}" "${_escapeShellArgument(destPath)}"';

    try {
      await _sftpClient.stat(sourcePath);
    } catch (e) {
      return false;
    }

    final success = await _executeSudoCommand(command, password);

    if (success) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await _sftpClient.stat(destPath);
        return true;
      } catch (e) {
        return false;
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));

      try {
        await _sftpClient.stat(destPath);
        try {
          await _sftpClient.stat(sourcePath);
          return true;
        } catch (e) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
  }

  Future<bool> _trySudoMove(String sourcePath, String destPath) async {
    final password = await _showSudoPasswordDialog('移动文件');
    if (password == null || password.isEmpty) return false;

    final command =
        'mv "${_escapeShellArgument(sourcePath)}" "${_escapeShellArgument(destPath)}"';
    try {
      await _sftpClient.stat(sourcePath);
    } catch (e) {
      debugPrint('源文件不存在，无法移动: $sourcePath');
      return false;
    }

    final success = await _executeSudoCommand(command, password);

    if (success) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await _sftpClient.stat(destPath);
        try {
          await _sftpClient.stat(sourcePath);
          return false;
        } catch (e) {
          return true;
        }
      } catch (e) {
        return false;
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 500));

      try {
        await _sftpClient.stat(destPath);
        try {
          await _sftpClient.stat(sourcePath);
          return false;
        } catch (e) {
          return true;
        }
      } catch (e) {
        return false;
      }
    }
  }

  Future<void> _trySudoUpload(
    File localFile,
    String remotePath,
    String filename,
    int fileSize,
  ) async {
    if (!mounted) return;

    final password = await _showSudoPasswordDialog('上传文件');
    if (password == null || password.isEmpty) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('上传失败', '需要root权限但未提供密码');
      }
      return;
    }

    final tempPath = '/tmp/${DateTime.now().millisecondsSinceEpoch}_$filename';
    try {
      final remote = await _sftpClient.open(
        tempPath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      _currentUploader = remote;

      int offset = 0;
      final stream = localFile.openRead();
      await for (final chunk in stream) {
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

      await remote.close();
      _currentUploader = null;

      final moveCommand = 'mv "$tempPath" "$remotePath"';
      final success = await _executeSudoCommand(moveCommand, password);

      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}

        if (!_cancelOperation) {
          if (success) {
            _showToast(
              '上传完成 : $filename',
              icon: Icons.check_circle_outline_rounded,
              duration: const Duration(seconds: 3),
            );
            await _loadDirectory(_currentPath);
          } else {
            try {
              final stat = await _sftpClient.stat(remotePath);
              if (stat.size == fileSize) {
                _showToast(
                  '上传完成 : $filename',
                  icon: Icons.check_circle_outline_rounded,
                  duration: const Duration(seconds: 3),
                );
                await _loadDirectory(_currentPath);
              } else {
                _showErrorDialog('上传失败', '使用root移动文件失败');
              }
            } catch (e) {
              _showErrorDialog('上传失败', '使用root移动文件失败');
            }

            try {
              await _sftpClient.remove(tempPath);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('使用root上传失败: $e');
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        _showErrorDialog('上传失败', e.toString());
      }
    }
  }

  Future<bool> _trySudoDelete(String path, bool isDirectory) async {
    final password = await _showSudoPasswordDialog('删除文件');
    if (password == null || password.isEmpty) return false;

    final command = isDirectory ? 'rm -rf "$path"' : 'rm -f "$path"';
    return await _executeSudoCommand(command, password);
  }

  Future<void> _trySudoRename(
    String oldPath,
    String newPath,
    String oldName,
    String newName,
  ) async {
    final password = await _showSudoPasswordDialog('重命名文件');
    if (password == null || password.isEmpty) {
      _showErrorDialog('重命名失败', '需要root权限但未提供密码');
      return;
    }

    final command = 'mv "$oldPath" "$newPath"';
    final success = await _executeSudoCommand(command, password);

    if (success && mounted) {
      _showToast('重命名成功 : $oldName → $newName', icon: Icons.check_circle_outline_rounded);
      _clearSelectionAndExitMultiSelect();
      await _loadDirectory(_currentPath);
    } else {
      _showErrorDialog('重命名失败', '使用root重命名失败');
    }
  }

  Future<void> _trySudoCreateDirectory(String dirPath) async {
    final password = await _showSudoPasswordDialog('创建目录');
    if (password == null || password.isEmpty) {
      _showErrorDialog('创建失败', '需要root权限但未提供密码');
      return;
    }

    final command = 'mkdir -p "$dirPath"';
    final success = await _executeSudoCommand(command, password);

    if (success && mounted) {
      _showToast('文件夹创建成功', icon: Icons.check_circle_outline_rounded);
      await _loadDirectory(_currentPath);
    } else {
      _showErrorDialog('创建文件夹失败', 'sudo创建失败');
    }
  }

  Future<void> _trySudoCreateFile(String filePath) async {
    final password = await _showSudoPasswordDialog('创建文件');
    if (password == null || password.isEmpty) {
      _showErrorDialog('创建失败', '需要root权限但未提供密码');
      return;
    }

    final command = 'touch "$filePath"';
    final success = await _executeSudoCommand(command, password);

    if (success && mounted) {
      _showToast('文件创建成功', icon: Icons.check_circle_outline_rounded);
      await _loadDirectory(_currentPath);
    } else {
      _showErrorDialog('创建文件失败', 'sudo创建失败');
    }
  }

  @override
  @override
  void dispose() {
    _loadingAnimationController.dispose();
    _cancelCurrentOperation();
    _rememberedSudoPassword = null;
    try {
      _sftpClient?.close();
    } catch (_) {}
    try {
      _sshClient?.close();
    } catch (_) {}
    // 清理2FA Completer
    if (_twoFactorCompleter != null && !_twoFactorCompleter!.isCompleted) {
      _twoFactorCompleter!.complete(null);
    }
    // 退出时取消通知
    _notificationService.cancelConnectionNotification().catchError((e) {
      print('dispose中取消通知失败: $e');
    });
    super.dispose();
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotationTransition(
            turns: _loadingAnimation,
            child: const Icon(
              Icons.refresh,
              size: 48,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '正在加载...',
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          if (!_isConnected && !_isConnecting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '连接已断开',
                style: TextStyle(
                  color: Colors.red.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('目录为空', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildBlurAwareSftpStrip({
    required Widget child,
    double opacity = 0.34,
  }) {
    // SFTP 连接页地址栏和工具栏背后不是滚动内容，不再使用模糊，
    // 避免连接页操作区因 BackdropFilter 产生额外重绘。
    return child;
  }

  Future<void> _showPathInputDialog() async {
    final controller = TextEditingController(text: _currentPath);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入地址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'SFTP 路径',
            hintText: '/home/user',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );

    controller.dispose();
    final target = result?.trim();
    if (target == null || target.isEmpty || target == _currentPath) return;
    await _loadDirectory(target);
  }

  Widget _buildBodyContent() {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_fileList.isEmpty) {
      return _buildEmptyWidget();
    }

    return _viewMode == ViewMode.list
        ? _buildListView(key: const ValueKey('list'))
        : _buildGridView(key: const ValueKey('grid'));
  }

  late AnimationController _loadingAnimationController;
  late Animation<double> _loadingAnimation;

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedFiles.isNotEmpty;
    final singleSelection = _selectedFiles.length == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    final iconColor = _getIconColor(context);
    final disabledIconColor = _getDisabledIconColor(context);
    final displayTitle = 'SFTP-${widget.connection.name}';
    final Color appBarColor = _getAppBarColor();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final now = DateTime.now();

        final bool isInBlockingState = _isLoading || !_isConnected;

        if (!isInBlockingState && _currentPath != '/') {
          _goToParentDirectory();
          return;
        }

        final bool shouldExit =
            _lastBackPressedTime == null ||
            now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

        if (shouldExit) {
          _lastBackPressedTime = now;

          String hintText;
          if (isInBlockingState && _currentPath != '/') {
            hintText = '再按一次退出';
          } else {
            hintText = '再按一次退出';
          }

          _showToast(hintText, duration: const Duration(seconds: 2));
        } else {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          backgroundColor: appBarColor,
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          automaticallyImplyLeading: false,
          leading: _ismobile
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          title: Container(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(left: _ismobile ? 18.0 : 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.circle : Icons.circle_outlined,
                        color: Colors.white,
                        size: 8,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _status,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                      if (_needsTwoFactorAuth)
                        const Padding(padding: EdgeInsets.only(left: 8.0)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: '更多',
              onPressed: _showMoreActionSheet,
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildBlurAwareSftpStrip(
                  opacity: 0.36,
                  child: AppPressable(
                    borderRadius: BorderRadius.zero,
                    onTap: _showPathInputDialog,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _currentPath,
                              style: const TextStyle(
                                fontFamily: 'hmossans',
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.edit_location_alt_outlined,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildBlurAwareSftpStrip(
                  opacity: 0.30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    height: screenWidth < 600 ? 80 : 40,
                    child: screenWidth < 600
                        ? _buildDoubleRowToolbar(
                            iconColor,
                            disabledIconColor,
                            hasSelection,
                            singleSelection,
                          )
                        : _buildSingleRowToolbar(
                            iconColor,
                            disabledIconColor,
                            hasSelection,
                            singleSelection,
                            isWideScreen,
                          ),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _buildBodyContent(),
                  ),
                ),
              ],
            ),
            _buildSftpFloatingMenu(),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
    Color color, {
    double iconSize = 24,
  }) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
