import 'package:connssh/pages/tcpdebug.dart';
import 'package:flutter/material.dart';
import '../monitor.dart';
import '../cerreader.dart';
import '../keygen.dart';

class UtilityToolsPage extends StatelessWidget {
  const UtilityToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实用工具'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildToolTile(
                      context: context,
                      icon: Icons.dashboard,
                      title: '服务器数据面板',
                      subtitle: '实时监控服务器使用情况',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MonitorServerPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildToolTile(
                      context: context,
                      icon: Icons.security,
                      title: '证书解析器',
                      subtitle: '解析和查看证书信息',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReadCerInfoPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildToolTile(
                      context: context,
                      icon: Icons.vpn_key,
                      title: '密钥生成',
                      subtitle: '生成SSH密钥对',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const KeygenPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildToolTile(
                      context: context,
                      icon: Icons.transfer_within_a_station,
                      title: 'TCP调试助手',
                      subtitle: '发送、获取TCP数据包',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SocketDebugPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 100,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.grey,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
