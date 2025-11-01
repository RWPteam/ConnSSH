// settings_page.dart
import 'dart:io';

import 'package:connecter/help_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models/app_settings_model.dart';
import 'services/setting_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _sftpPathController = TextEditingController();
  final TextEditingController _downloadPathController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.getSettings();
    setState(() {
      _sftpPathController.text = settings.defaultSftpPath ?? '/';
      _downloadPathController.text = settings.defaultDownloadPath ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final newSettings = AppSettings(
        defaultSftpPath: _sftpPathController.text.trim().isEmpty 
            ? null 
            : _sftpPathController.text.trim(),
        defaultDownloadPath: _downloadPathController.text.trim().isEmpty
            ? null
            : _downloadPathController.text.trim(),
      );

      await _settingsService.saveSettings(newSettings);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
        Navigator.of(context).pop();
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

  Future<void> _selectDownloadDirectory() async {
    // Windows平台下直接显示提示，不允许选择目录
    if (Platform.isWindows) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('功能受限'),
            content: const Text('windows平台无法直接选择目录，下载文件时会提示。'),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择默认下载目录',
      );
      
      if (selectedDirectory != null && mounted) {
        setState(() {
          _downloadPathController.text = selectedDirectory;
        });
      }
    } catch (e) {
      debugPrint('选择目录失败: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择目录失败'),
            content: Text('当前平台不支持目录选择，请手动输入路径或使用默认设置。\n\n错误: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // SFTP 初始路径设置
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SFTP 初始路径',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _sftpPathController,
                            decoration: const InputDecoration(
                              labelText: '默认SFTP路径',
                              hintText: '例如: /home/username',
                              border: UnderlineInputBorder(),
                              prefixIcon: Icon(Icons.folder),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '连接SFTP时默认打开的目录路径',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 下载路径设置
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '下载保存路径',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _downloadPathController,
                                  decoration: InputDecoration(
                                    labelText: '默认下载路径',
                                    hintText: Platform.isWindows 
                                        ? 'Windows平台不支持目录选择' 
                                        : '留空则使用平台默认',
                                    border: const UnderlineInputBorder(),
                                    prefixIcon: const Icon(Icons.download),
                                  ),
                                  // Windows平台只读，不允许编辑
                                  readOnly: Platform.isWindows,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Windows平台隐藏目录选择按钮
                              if (!Platform.isWindows)
                                IconButton(
                                  icon: const Icon(Icons.folder_open),
                                  onPressed: _selectDownloadDirectory,
                                  tooltip: '选择目录',
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            Platform.isWindows 
                                ? 'Windows平台不支持目录选择功能，如需自定义路径请手动输入' 
                                : Platform.isAndroid 
                                    ? '留空将使用 Downloads 目录' 
                                    : '无需修改',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_downloadPathController.text.isEmpty)
                            if (!Platform.isWindows)
                                OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _downloadPathController.text = '';
                                  });
                                },
                                child: const Text('使用平台默认路径'),
                              ),
                        ],
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // 操作按钮
                  Row(
                    children: [    
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const HelpPage()),
                            );
                          },
                          child: const Text('帮助'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saveSettings,
                          child: const Text('保存'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _sftpPathController.text = '/';
                            _downloadPathController.text = '';
                          },
                          child: const Text('默认'),
                        ),
                      ),
                    ],
                  ),

                ],
              ),
            ),
    );
  }
}



