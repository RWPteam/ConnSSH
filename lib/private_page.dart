// privacy_policy_page.dart
import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('隐私政策'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connecter 隐私政策',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              '最后更新日期：2025年11月4日',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 24),
            
            // 在这里添加你的隐私政策内容
            _PolicySection(
              title: '1. 我们如何收集和使用您的个人信息',
              content: '我们仅在有合法性基础的情形下才会使用您的个人信息。根据适用的法律，我们可能会基于您的同意、为履行/订立您与我们的合同所必需、履行法定义务所必需等合法性基础，使用您的个人信息。我们为您提供了基本功能服务和全量功能服务，您可以前往管理连接进行选择，不同设备或版本其路径可能存在差异，具体以您当前使用的设备为准。在基本功能服务下不收集个人信息，仅提供SSH连接基本功能，不提供SFTP管理等其他附加功能，这可能会影响您的使用体验。',
            ),
            _PolicySection(
              title: '2. 管理您的个人信息',
              content: '如您对您的数据主体权利有进一步要求或存在任何疑问、意见或建议，可通过本声明中“如何联系我们”章节中所述方式与我们取得联系，并行使您的相关权利。',
            ),
            _PolicySection(
              title: '3. 信息存储地点及期限',
              content: '我们承诺，除法律法规另有规定外，我们对您的信息的保存期限应当为实现处理目的所必要的最短时间。上述信息将会传输并保存至中国境内的服务器。',
            ),
            _PolicySection(
              title: '4. 如何联系我们',
              content: '您可通过以下方式联系我们，并行使您的相关权利，我们会尽快回复。邮箱：samuioto@outlook.com',
            ),
            SizedBox(height: 32),
            Text(
              '如果您对我们的回复不满意, 特别是当个人信息处理行为损害了您的合法权益时您还可以通过向有管辖权的人民法院提起诉讼、向行业自律协会或政府相关管理机构投诉等外部途径进行解决。 您也可以向我们了解可能适用的相关投诉途径的信息。',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String content;
  
  const _PolicySection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }
}