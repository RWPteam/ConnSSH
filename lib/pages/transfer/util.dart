import 'package:connssh/pages/tcpdebug.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_style.dart';
import '../cerreader.dart';
import '../keygen.dart';
import '../monitor.dart';

class UtilityToolsPage extends StatelessWidget {
  const UtilityToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_UtilityMenuItem>[
      _UtilityMenuItem(
        icon: Icons.dashboard_rounded,
        title: '服务器数据面板',
        subtitle: '实时监控服务器使用情况',
        pageBuilder: (_) => const MonitorServerPage(),
      ),
      _UtilityMenuItem(
        icon: Icons.security_rounded,
        title: '证书解析器',
        subtitle: '解析和查看证书信息',
        pageBuilder: (_) => const ReadCerInfoPage(),
      ),
      _UtilityMenuItem(
        icon: Icons.vpn_key_rounded,
        title: '密钥生成',
        subtitle: '生成SSH密钥对',
        pageBuilder: (_) => const KeygenPage(),
      ),
      _UtilityMenuItem(
        icon: Icons.swap_horiz_rounded,
        title: 'TCP调试助手',
        subtitle: '发送、获取TCP数据包',
        pageBuilder: (_) => const SocketDebugPage(),
      ),
    ];

    return AppPageScaffold(
      title: const Text('实用工具'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
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

class _UtilityMenuItem {
  const _UtilityMenuItem({
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
