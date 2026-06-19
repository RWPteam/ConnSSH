import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:connssh/main.dart';
import 'package:path/path.dart' as path;
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';
import '../../widgets/app_style.dart';
import '../../widgets/app_toast.dart';
import '../../services/backup_service.dart';
import '../../services/storage_service.dart';
import 'theme.dart';

class GlobalSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const GlobalSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<GlobalSettingsPage> createState() => _GlobalSettingsPageState();
}

class _GlobalSettingsPageState extends State<GlobalSettingsPage> {
  bool _isLoading = true;
  late BackupService _backupService;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initBackupService();
  }

  void _initBackupService() {
    final storageService = StorageService();
    _backupService = BackupService(
      storageService: storageService,
      settingsService: widget.settingsService,
    );
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = false;
    });
  }

  void _showBackupDialog() {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool passwordObscure = true;
    bool confirmPasswordObscure = true;

    // 保存主页面的 context
    final BuildContext pageContext = context;

    showDialog(
      context: pageContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('备份数据'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: passwordObscure,
                      decoration: InputDecoration(
                        labelText: '请设置密码',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            passwordObscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => passwordObscure = !passwordObscure,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: confirmPasswordObscure,
                      decoration: InputDecoration(
                        labelText: '确认密码',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            confirmPasswordObscure
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => confirmPasswordObscure =
                                !confirmPasswordObscure,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (Platform.isAndroid)
                      const Text(
                        '备份文件将保存在应用私有目录中，您可以通过文件管理器访问。',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (passwordController.text.isEmpty) {
                      AppToast.show(
                        pageContext,
                        message: '请输入密码',
                        icon: Icons.info_outline_rounded,
                      );
                      return;
                    }
                    if (passwordController.text !=
                        confirmPasswordController.text) {
                      AppToast.show(
                        pageContext,
                        message: '两次输入的密码不一致',
                        icon: Icons.info_outline_rounded,
                      );
                      return;
                    }

                    Navigator.of(context).pop();

                    final completer = Completer<void>();

                    final loadingDialogFuture = showDialog(
                      context: pageContext,
                      barrierDismissible: false,
                      builder: (context) => const AlertDialog(
                        backgroundColor: Colors.transparent,
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在备份数据...'),
                          ],
                        ),
                      ),
                    );

                    Future<void> backupOperation() async {
                      try {
                        final filePath = await _backupService.backupData(
                          passwordController.text,
                        );

                        if (!mounted) return;

                        completer.complete();

                        await Future.delayed(const Duration(milliseconds: 100));

                        if (Navigator.of(
                          pageContext,
                          rootNavigator: true,
                        ).canPop()) {
                          Navigator.of(pageContext, rootNavigator: true).pop();
                        }

                        await loadingDialogFuture;

                        _showResultDialog(
                          pageContext,
                          '备份成功',
                          '备份文件已保存到:\n$filePath',
                        );
                      } catch (e) {
                        if (!mounted) return;

                        completer.completeError(e);

                        await Future.delayed(const Duration(milliseconds: 100));

                        if (Navigator.of(
                          pageContext,
                          rootNavigator: true,
                        ).canPop()) {
                          Navigator.of(pageContext, rootNavigator: true).pop();
                        }

                        await loadingDialogFuture;

                        _showResultDialog(
                          pageContext,
                          '备份失败',
                          '错误: $e\n请检查存储空间',
                        );
                      }
                    }

                    backupOperation();
                  },
                  child: const Text('备份'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showResultDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    final passwordController = TextEditingController();
    bool isObscure = true;
    String? selectedFilePath;
    bool useAppBackupDir = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('恢复数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  // 文件选择
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final FilePickerResult? result =
                            await FilePicker.pickFiles(
                              type: FileType.any,
                              dialogTitle: '选择备份文件',
                              allowMultiple: false,
                            );

                        if (result != null && result.files.isNotEmpty) {
                          PlatformFile file = result.files.first;
                          setState(() {
                            selectedFilePath = file.path;
                            useAppBackupDir = false;
                          });
                        }
                      } catch (e) {}
                    },
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      selectedFilePath != null && !useAppBackupDir
                          ? path.basename(selectedFilePath!)
                          : '选择备份文件',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 从应用备份目录读取
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final files = await _backupService.getBackupFiles();
                        if (!mounted) return;
                        if (files.isEmpty) {
                          AppToast.show(
                            context,
                            message: '备份目录中没有找到备份文件',
                            icon: Icons.info_outline_rounded,
                          );
                          return;
                        }
                        final selected = await showDialog<FileSystemEntity>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('选择备份文件'),
                            content: Container(
                              width: double.maxFinite,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: files.length,
                                itemBuilder: (ctx, index) {
                                  final file = files[index];
                                  final fileName = path.basename(file.path);
                                  return ListTile(
                                    title: Text(fileName),
                                    onTap: () => Navigator.of(ctx).pop(file),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                        if (selected != null) {
                          setState(() {
                            selectedFilePath = selected.path;
                            useAppBackupDir = true;
                          });
                        }
                      } catch (e) {
                        AppToast.show(
                          context,
                          message: '读取备份目录失败: $e',
                          icon: Icons.error_outline_rounded,
                        );
                      }
                    },
                    icon: const Icon(Icons.storage),
                    label: Text(
                      useAppBackupDir && selectedFilePath != null
                          ? path.basename(selectedFilePath!)
                          : '从应用备份目录读取',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (useAppBackupDir && selectedFilePath != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '已选择应用备份目录中的文件',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (selectedFilePath != null && !useAppBackupDir) ...[
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscure,
                    onChanged: (value) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: '备份密码',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            isObscure = !isObscure;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '警告：恢复操作将覆盖当前所有连接、凭证和设置！',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed:
                    selectedFilePath == null || passwordController.text.isEmpty
                    ? null
                    : () async {
                        // 确认恢复
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('这是最后一次确认'),
                            content: const Text(
                              '此操作将覆盖所有现有数据，且不可撤销，确定要恢复吗？',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                              OutlinedButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  if (Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).canPop()) {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                  }
                                  final NavigatorState navigator = Navigator.of(
                                    this.context,
                                    rootNavigator: true,
                                  );
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const AlertDialog(
                                      backgroundColor: Colors.transparent,
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text('正在恢复数据...'),
                                        ],
                                      ),
                                    ),
                                  );

                                  try {
                                    final backupData = await _backupService
                                        .restoreData(
                                          selectedFilePath!,
                                          passwordController.text,
                                        );

                                    await _backupService.applyRestoredData(
                                      backupData,
                                    );

                                    if (navigator.canPop()) {
                                      navigator.pop();
                                    }

                                    // 刷新应用
                                    widget.onSettingsChanged();
                                    MyApp.of(this.context)?.loadSettings();

                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('恢复成功'),
                                        content: Text(
                                          '数据已成功恢复！\n'
                                          '备份时间：${backupData.backupTime.toString().substring(0, 19)}\n'
                                          '包含连接：${backupData.connections.length}个\n'
                                          '包含凭证：${backupData.credentials.length}个',
                                        ),
                                        actions: [
                                          OutlinedButton(
                                            onPressed: () {
                                              if (navigator.canPop()) {
                                                navigator.pop();
                                              }
                                            },
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                  } catch (e) {
                                    // 关闭加载对话框
                                    if (Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).canPop()) {
                                      Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).pop();
                                    }

                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('恢复失败'),
                                        content: Text(e.toString()),
                                        actions: [
                                          OutlinedButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                child: const Text('确定恢复'),
                              ),
                            ],
                          ),
                        );
                      },
                child: const Text('恢复'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要恢复所有设置为默认值吗？此操作不可撤销。'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final defaultSettings = AppSettings();
              await widget.settingsService.saveSettings(defaultSettings);
              widget.onSettingsChanged();
              MyApp.of(context)?.loadSettings();
              if (mounted) {
                AppToast.show(
                  context,
                  message: '已恢复默认设置',
                  icon: Icons.check_circle_outline_rounded,
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AppMenuTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }


  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: const Text('全局设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                  _buildSettingTile(
                    icon: Icons.color_lens,
                    title: '主题设置',
                    subtitle: '主题风格和页面主题',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ThemeSettingsPage(
                            settingsService: widget.settingsService,
                            onSettingsChanged: widget.onSettingsChanged,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.backup,
                    title: '备份数据',
                    subtitle: '加密备份所有连接和设置',
                    onTap: _showBackupDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.restore,
                    title: '恢复数据',
                    subtitle: '从备份文件恢复数据',
                    onTap: _showRestoreDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.settings_backup_restore,
                    title: '恢复默认设置',
                    subtitle: '将所有设置恢复为默认值',
                    onTap: _resetToDefaults,
                  ),
              ],
            ),
    );
  }
}
