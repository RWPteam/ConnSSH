// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../widgets/app_style.dart';
import '../manage_connections.dart';
import '../manage_credentials.dart';
import '../manage_telnet.dart';

class ManageInfoPage extends StatelessWidget {
  const ManageInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_TransferMenuItem>[
      _TransferMenuItem(
        icon: Icons.terminal_rounded,
        title: 'SSH/SFTP连接',
        subtitle: '管理SSH和SFTP连接配置',
        pageBuilder: (_) => const ManageConnectionsPage(),
      ),
      _TransferMenuItem(
        icon: Icons.key_rounded,
        title: '认证凭证',
        subtitle: '管理用户名密码和密钥凭证',
        pageBuilder: (_) => const ManageCredentialsPage(),
      ),
      _TransferMenuItem(
        icon: Icons.settings_ethernet_rounded,
        title: 'Telnet连接',
        subtitle: '管理Telnet连接配置',
        pageBuilder: (_) => const ManageTelnetConnectionsPage(),
      ),
    ];

    return AppPageScaffold(
      title: const Text('管理信息'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              '集中管理连接、凭证和 Telnet 配置。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          ...items.map(
            (item) => AppMenuTile(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: item.pageBuilder),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferMenuItem {
  const _TransferMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder pageBuilder;
}
