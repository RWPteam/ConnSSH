// main_page.dart
import 'package:flutter/material.dart';
import 'manage_connections_page.dart';
import 'manage_credentials_page.dart';
import 'quick_connect_dialog.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH工具'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 快速连接按钮
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => const QuickConnectDialog(),
                  );
                },
                icon: const Icon(Icons.bolt),
                label: const Text('快速连接'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // 管理已保存的连接按钮
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageConnectionsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_ethernet),
                label: const Text('管理已保存的连接'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            

            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ManageCredentialsPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.vpn_key),
                label: const Text('管理认证凭证'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // 关于按钮
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'SSH工具',
                    applicationVersion: '1.0.0',
                  );
                },
                icon: const Icon(Icons.info),
                label: const Text('关于'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}