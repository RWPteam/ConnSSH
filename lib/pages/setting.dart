import 'package:flutter/material.dart';

import '../services/setting_service.dart';
import '../widgets/app_style.dart';
import 'help.dart';
import 'settings/global.dart';
import 'settings/sftp.dart';
import 'settings/ssh.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => PageState();
}

class PageState extends State<SettingsPage> {
  final SettingsService Service = SettingsService();

  final List<Map<String, dynamic>> _menuItems = [
    {'title': 'SSH设置', 'subtitle': '字体大小、终端主题、快捷栏等', 'icon': Icons.terminal},
    {'title': 'SFTP设置', 'subtitle': '默认路径、下载目录等', 'icon': Icons.folder},
    {'title': '全局设置', 'subtitle': '页面主题、恢复默认设置', 'icon': Icons.settings},
    {'title': '帮助', 'subtitle': '帮助文档、版本信息', 'icon': Icons.help},
    {'title': '开放源代码许可', 'subtitle': '查看应用使用的许可证', 'icon': Icons.description},
  ];

  void _navigateToSettingsPage(int index, BuildContext context) {
    switch (index) {
      case 0:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SSHSettingsPage(
              settingsService: Service,
              onSettingsChanged: () => setState(() {}),
            ),
          ),
        );
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SFTPSettingsPage(
              settingsService: Service,
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
              settingsService: Service,
              onSettingsChanged: () => setState(() {}),
            ),
          ),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HelpPage()),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LicensePage()),
        );
        break;
    }
  }

  Widget _buildMenuItem(Map<String, dynamic> item, int index) {
    return AppMenuTile(
      icon: item['icon'],
      title: item['title'],
      subtitle: item['subtitle'],
      onTap: () => _navigateToSettingsPage(index, context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: const Text('设置'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                ..._menuItems.asMap().entries.map(
                      (entry) => _buildMenuItem(entry.value, entry.key),
                    ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                '鲁ICP备2024127829号-5A',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
