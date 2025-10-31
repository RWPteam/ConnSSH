import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '欢迎使用 Connecter!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Connecter 是一个便捷的SSH和SFTP连接管理工具',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              _buildHelpSection(
                title: '快速连接',
                content: '使用快速连接来进行SSH/SFTP的连接操作。您连接过的主机也会自动添加到最近连接中',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                title: '管理连接和凭证',
                content: '在"管理认证凭证"和"管理连接"页面，可以管理您的连接和凭证信息',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                title: 'SSH页面',
                content: '安卓设备点击空白处可唤起输入法，Windows可直接进行输入，快捷键暂未开发，敬请期待',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                title: 'SFTP页面',
                content: '在顶部进行文件操作，请注意，目前的上传、下载逻辑存在较大问题，请尽量不要应用于生产环境',
              ),
              const SizedBox(height: 16),
              _buildHelpSection(
                title: '反馈',
                content: '如有问题或建议，请在github页面发布issue',
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'connecter',
                      applicationVersion: '1.0 Beta 3',
                    );
                  },
                  child: const Text('关于'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
