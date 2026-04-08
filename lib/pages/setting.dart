import 'package:flutter/material.dart';
import 'help.dart';
import 'settings/ssh.dart';
import 'settings/sftp.dart';
import 'settings/global.dart';
import '../../services/setting_service.dart';

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
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            item['icon'],
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          item['title'],
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          item['subtitle'],
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: () => _navigateToSettingsPage(index, context),
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
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._menuItems.asMap().entries.map(
                    (entry) => _buildMenuItem(entry.value, entry.key),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: Colors.transparent,
            child: Text(
              '鲁ICP备2024127829号-5A',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}
