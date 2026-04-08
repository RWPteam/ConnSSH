import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';

class SFTPSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const SFTPSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SFTPSettingsPage> createState() => _SFTPSettingsPageState();
}

class _SFTPSettingsPageState extends State<SFTPSettingsPage> {
  bool _isLoading = true;
  String _sftpPath = '/';
  String _downloadPath = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _sftpPath = settings.defaultSftpPath ?? '/';
      _downloadPath = settings.defaultDownloadPath ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = AppSettings(
        defaultSftpPath: _sftpPath.isEmpty ? null : _sftpPath,
        defaultDownloadPath: _downloadPath.isEmpty ? null : _downloadPath,
        defaultFontSize: currentSettings.defaultFontSize,
        defaultTermTheme: currentSettings.defaultTermTheme,
        termType: currentSettings.termType,
        defaultPageTheme: currentSettings.defaultPageTheme,
        defaultThemeMode: currentSettings.defaultThemeMode,
      );

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置已保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('保存失败'),
            content: Text(e.toString()),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showSftpPathDialog() {
    final controller = TextEditingController(text: _sftpPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('默认SFTP路径'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '例如: /home/username',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
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
              setState(() {
                _sftpPath = controller.text.trim();
              });
              Navigator.of(context).pop();
              await _saveSettings();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showDownloadPathDialog() {
    if (Platform.isWindows || Platform.operatingSystem == 'ohos') {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('提示'),
          content: const Text('您所使用的平台请在下载文件时选择保存位置'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController(text: _downloadPath);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('默认下载路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: Platform.isAndroid ? '留空将在每次下载时询问' : '请输入下载目录路径',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              readOnly: !Platform.isWindows,
            ),
            const SizedBox(height: 10),
            if (!Platform.isWindows)
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    String? selectedDirectory =
                        await FilePicker.getDirectoryPath(
                          dialogTitle: '选择默认下载目录',
                        );

                    controller.text = selectedDirectory!;
                  } catch (e) {
                    debugPrint('选择目录失败: $e');
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('选择目录'),
              ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () async {
              setState(() {
                _downloadPath = '';
              });
              Navigator.of(context).pop();
              await _saveSettings();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已清除默认下载路径'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: const Text('清除'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              setState(() {
                _downloadPath = controller.text.trim();
              });
              Navigator.of(context).pop();
              await _saveSettings();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDownloadPath() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认清除'),
          content: const Text('确定要清除默认下载路径吗？清除后下载文件时将需要手动选择保存位置。'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              child: const Text('清除'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        setState(() {
          _downloadPath = '';
        });
        await _saveSettings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已清除默认下载路径'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('清除失败'),
            content: Text(e.toString()),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showClearButton = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey, width: 1.0),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showClearButton && _downloadPath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                  onPressed: _clearDownloadPath,
                  tooltip: '清除下载路径',
                ),
              ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 16.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SFTP设置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildSettingTile(
                    title: '默认SFTP路径',
                    subtitle: _sftpPath,
                    icon: Icons.folder,
                    onTap: _showSftpPathDialog,
                  ),
                  _buildSettingTile(
                    title: '默认下载路径',
                    subtitle: _downloadPath.isEmpty
                        ? (Platform.isWindows ? 'Windows平台需在下载时选择' : '未设置')
                        : _downloadPath,
                    icon: Icons.download,
                    onTap: _showDownloadPathDialog,
                    showClearButton: true,
                  ),
                ],
              ),
            ),
    );
  }
}
