// settings_page.dart
import 'dart:io';
import 'package:connssh/help_page.dart';
import 'package:connssh/main.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models/app_settings_model.dart';
import 'services/setting_service.dart';

// 二级设置页面 - SFTP设置
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
          decoration: const InputDecoration(
            hintText: '例如: /home/username',
            border: OutlineInputBorder(),
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
    if (Platform.isWindows) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Windows平台限制'),
          content: const Text('Windows平台无法直接选择目录，请在下载文件时选择保存位置。'),
          actions: [
            TextButton(
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
                border: const OutlineInputBorder(),
              ),
              readOnly: !Platform.isWindows,
            ),
            const SizedBox(height: 10),
            if (!Platform.isWindows)
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    String? selectedDirectory =
                        await FilePicker.platform.getDirectoryPath(
                      dialogTitle: '选择默认下载目录',
                    );

                    if (selectedDirectory != null) {
                      controller.text = selectedDirectory;
                    }
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
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

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLargeScreen = screenHeight >= 500;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      height: isLargeScreen ? 100 : 80,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: isLargeScreen ? 18 : 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: isLargeScreen
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: isLargeScreen ? 16.0 : 8.0,
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
      appBar: AppBar(
        title: const Text('SFTP设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                _buildSettingTile(
                  title: '默认SFTP路径',
                  subtitle: _sftpPath,
                  onTap: _showSftpPathDialog,
                ),
                _buildSettingTile(
                  title: '默认下载路径',
                  subtitle: _downloadPath.isEmpty
                      ? (Platform.isWindows
                          ? 'Windows平台需在下载时选择'
                          : '未设置，将在下载时询问')
                      : _downloadPath,
                  onTap: _showDownloadPathDialog,
                ),
              ],
            ),
    );
  }
}

// 二级设置页面 - SSH设置
class SSHSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const SSHSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SSHSettingsPage> createState() => _SSHSettingsPageState();
}

class _SSHSettingsPageState extends State<SSHSettingsPage> {
  bool _isLoading = true;
  double _fontSize = 12.0;
  String _termTheme = 'dark';
  String _termType = 'xterm-256color';
  final List<String> _termThemes = ['dark', 'black', 'light'];
  final List<String> _termTypes = ['vt100', 'xterm-256color', 'linux'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _fontSize = settings.defaultFontSize;
      _termTheme = settings.defaultTermTheme;
      _termType = settings.termType;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = AppSettings(
        defaultSftpPath: currentSettings.defaultSftpPath,
        defaultDownloadPath: currentSettings.defaultDownloadPath,
        defaultFontSize: _fontSize,
        defaultTermTheme: _termTheme,
        termType: _termType,
        defaultPageTheme: currentSettings.defaultPageTheme,
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

  void _showFontSizeDialog() {
    double currentValue = _fontSize;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('字体大小设置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('大小: '),
                    Expanded(
                      child: Slider(
                        value: currentValue,
                        min: 8,
                        max: 24,
                        divisions: 16,
                        label: currentValue.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            currentValue = value;
                          });
                        },
                      ),
                    ),
                    Text('${currentValue.toInt()}px'),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() {
                    _fontSize = currentValue;
                  });
                  Navigator.of(context).pop();
                  await _saveSettings();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTermThemeDialog() {
    String currentValue = _termTheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termThemes
              .map((theme) => RadioListTile<String>(
                    title: Text(theme),
                    value: theme,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termTheme = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showTermTypeDialog() {
    String currentValue = _termType;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termTypes
              .map((type) => RadioListTile<String>(
                    title: Text(type),
                    value: type,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termType = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showCustomShortcutBarMessage() {
    if (TargetPlatform == TargetPlatform.iOS ||
        TargetPlatform == TargetPlatform.ohos ||
        TargetPlatform == TargetPlatform.android) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('绝赞监修中...'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('绝赞监修中...'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLargeScreen = screenHeight >= 500;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      height: isLargeScreen ? 100 : 80,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: isLargeScreen ? 18 : 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: isLargeScreen
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: isLargeScreen ? 16.0 : 8.0,
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
      appBar: AppBar(
        title: const Text('SSH设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                _buildSettingTile(
                  title: '字体大小',
                  subtitle: '${_fontSize.toInt()}px',
                  onTap: _showFontSizeDialog,
                ),
                _buildSettingTile(
                  title: '终端主题',
                  subtitle: _termTheme,
                  onTap: _showTermThemeDialog,
                ),
                _buildSettingTile(
                  title: '终端类型',
                  subtitle: _termType,
                  onTap: _showTermTypeDialog,
                ),
                _buildSettingTile(
                  title: '自定义快捷栏',
                  subtitle: '配置快捷栏样式',
                  onTap: _showCustomShortcutBarMessage,
                ),
              ],
            ),
    );
  }
}

// 二级设置页面 - 全局设置
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
  String _pageTheme = 'default';
  final List<String> _pageThemes = [
    'default',
    'orange',
    'green',
    'yellow',
    'monochrome'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _pageTheme = settings.defaultPageTheme;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = AppSettings(
        defaultSftpPath: currentSettings.defaultSftpPath,
        defaultDownloadPath: currentSettings.defaultDownloadPath,
        defaultFontSize: currentSettings.defaultFontSize,
        defaultTermTheme: currentSettings.defaultTermTheme,
        termType: currentSettings.termType,
        defaultPageTheme: _pageTheme,
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

  void _showPageThemeDialog() {
    String currentValue = _pageTheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('页面主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _pageThemes
              .map((theme) => RadioListTile<String>(
                    title: Text(theme),
                    value: theme,
                    groupValue: currentValue,
                    onChanged: (value) async {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _pageTheme = value;
                        });
                        await _saveSettings();
                        MyApp.of(context)?.loadSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final defaultSettings = AppSettings();
              await widget.settingsService.saveSettings(defaultSettings);
              widget.onSettingsChanged();
              await _loadSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已恢复默认设置'),
                    duration: Duration(seconds: 2),
                  ),
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
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLargeScreen = screenHeight >= 500;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      height: isLargeScreen ? 100 : 80,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
            fontSize: isLargeScreen ? 18 : 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: isLargeScreen
            ? Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: isLargeScreen ? 16.0 : 8.0,
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
      appBar: AppBar(
        title: const Text('全局设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                _buildSettingTile(
                  title: '页面主题',
                  subtitle: _pageTheme,
                  onTap: _showPageThemeDialog,
                ),
                _buildSettingTile(
                  title: '恢复默认设置',
                  subtitle: '将所有设置恢复为默认值',
                  onTap: _resetToDefaults,
                ),
              ],
            ),
    );
  }
}

// 主设置页面 - 菜单形式
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();

  // 菜单项列表
  final List<Map<String, dynamic>> _menuItems = [
    {
      'title': 'SFTP设置',
      'subtitle': '默认路径、下载目录等',
    },
    {
      'title': 'SSH设置',
      'subtitle': '字体大小、终端主题、快捷栏等',
    },
    {
      'title': '全局设置',
      'subtitle': '页面主题、恢复默认设置',
    },
    {
      'title': '关于',
      'subtitle': '版本信息、帮助文档',
    },
  ];

  void _navigateToSettingsPage(int index, BuildContext context) {
    switch (index) {
      case 0:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SFTPSettingsPage(
              settingsService: _settingsService,
              onSettingsChanged: () => setState(() {}),
            ),
          ),
        );
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SSHSettingsPage(
              settingsService: _settingsService,
              onSettingsChanged: () => setState(() {}),
            ),
          ),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GlobalSettingsPage(
              settingsService: _settingsService,
              onSettingsChanged: () => setState(() {}),
            ),
          ),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HelpPage(),
          ),
        );
        break;
    }
  }

  Widget _buildMenuItem(Map<String, dynamic> item, int index) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLargeScreen = screenHeight >= 500;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      height: isLargeScreen ? 100 : 80,
      child: ListTile(
        title: Text(
          item['title'],
          style: TextStyle(
            fontSize: isLargeScreen ? 18 : 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: isLargeScreen
            ? Text(
                item['subtitle'],
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: () => _navigateToSettingsPage(index, context),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: isLargeScreen ? 16.0 : 8.0,
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
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 16),
              ..._menuItems.asMap().entries.map(
                    (entry) => _buildMenuItem(entry.value, entry.key),
                  ),
              const SizedBox(height: 60), // 为备案号留出空间
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 5,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: Colors.transparent,
              child: Text(
                '鲁ICP备2024127829号-5A',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
