import 'package:flutter/material.dart';
import 'dart:async';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final List<HelpItem> helpItems = [
    HelpItem(
      title: '快速连接',
      content: '使用快速连接来进行SSH/SFTP的连接操作。您连接过的主机也会自动添加到最近连接中',
      imagePath: 'assets/quickconn.png',
    ),
    HelpItem(
      title: '管理连接',
      content: '在管理信息功能中可以管理保存的连接。您可以将现有的连接复制为其他类型，也可以进行编辑、导入、导出等操作',
      imagePath: 'assets/mana_conn.png',
    ),
    HelpItem(
      title: '管理凭证',
      content: '在管理信息功能中可以管理保存的凭证。导入连接同时会导入所使用的凭证，您可在此对凭证进行编辑等操作',
      imagePath: 'assets/mana_cer.png',
    ),
    HelpItem(
      title: 'Telnet功能（Beta）',
      content:
          '在快速连接中点击telnet按钮即可使用，支持连接常见的服务器，支持用户名密码的自动输入。由于telnet标准不一致情况较多，如遇到无法使用等问题请及时反馈',
      imagePath: 'assets/telnet.png',
    ),
    HelpItem(
      title: 'SSH功能',
      content: '在设置页面可以修改默认终端类型、默认主题、默认字体大小等，您也可以在页面的菜单中修改主题、字体大小。',
      imagePath: 'assets/ssh.png',
    ),
    HelpItem(
      title: 'SSH多会话',
      content: '您可在菜单中开启多会话功能，目前该功能支持同时开启两个会话',
      imagePath: 'assets/ssh_multi.png',
    ),
    HelpItem(
      title: 'SFTP功能',
      content: 'SFTP连接后可通过顶部工具栏进行操作，支持侧滑返回上级，可通过切换视图按钮切换列表/图标视图',
      imagePath: 'assets/sftp.png',
    ),
    HelpItem(
      title: '文本编辑',
      content: '可以直接编辑服务器上的文件，支持常见文本格式和编码，支持代码高亮',
      imagePath: 'assets/textedit.png',
    ),
    HelpItem(
      title: '关于 & 反馈',
      content: '''
ConnSSH 版本 1.3.0

此版本更新内容：

新增功能
• 服务器数据面板支持查看网络和进程占用情况
• 增加TCP调试工具
• 支持基于TOTP的2FA验证
• Telnet模式终端支持自定义

问题改进
• 修复HarmonyOS粘贴按钮无法使用的问题
• 修复SSH字体设置展示页面相关问题
• 修复部分场景无法读取/保存文件的问题
• 修正部分界面显示和文字提示


如有问题或建议，请发送邮件至：
samuioto@outlook.com
        ''',
      imagePath: null,
    ),
  ];

  late PageController _pageController;
  late Timer _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_currentPage < helpItems.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _resetTimer() {
    _timer.cancel();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ConnSSH',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '一个便捷的SSH和SFTP连接管理工具',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: helpItems.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                  // 手动切换时重置计时器
                  _resetTimer();
                },
                itemBuilder: (context, index) {
                  final item = helpItems[index];
                  return HelpCard(helpItem: item);
                },
                scrollDirection: Axis.horizontal,
                pageSnapping: true,
                padEnds: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(helpItems.length, (index) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentPage == index
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                      ),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0
                      ? () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                          );
                          // 手动切换时重置计时器
                          _resetTimer();
                        }
                      : null,
                ),
                const SizedBox(width: 20),
                Text(
                  '${_currentPage + 1} / ${helpItems.length}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < helpItems.length - 1
                      ? () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                          );
                          // 手动切换时重置计时器
                          _resetTimer();
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class HelpItem {
  final String title;
  final String content;
  final String? imagePath;

  HelpItem({
    required this.title,
    required this.content,
    this.imagePath,
  });
}

class HelpCard extends StatelessWidget {
  final HelpItem helpItem;

  const HelpCard({super.key, required this.helpItem});

  @override
  Widget build(BuildContext context) {
    final bool isAboutFeedback = helpItem.title == '关于 & 反馈';

    if (isAboutFeedback) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helpItem.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    helpItem.content,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (helpItem.imagePath != null)
                    LayoutBuilder(
                      builder: (context, innerConstraints) {
                        final textHeight = _calculateTextHeight(
                          helpItem.title,
                          helpItem.content,
                          innerConstraints.maxWidth,
                        );
                        final totalHeight = constraints.maxHeight;
                        const padding = 16.0;
                        const imageTextSpacing = 8.0;
                        const textBottomMargin = 16.0;
                        final maxImageHeight = totalHeight -
                            textHeight -
                            padding * 2 -
                            imageTextSpacing -
                            textBottomMargin;

                        return Container(
                          height: maxImageHeight.clamp(100, double.infinity),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            color: Colors.transparent,
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: helpItem.imagePath!.startsWith('http')
                                ? Image.network(
                                    helpItem.imagePath!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildImageErrorWidget();
                                    },
                                  )
                                : Image.asset(
                                    helpItem.imagePath!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildImageErrorWidget();
                                    },
                                  ),
                          ),
                        );
                      },
                    ),
                  if (helpItem.imagePath != null) const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              helpItem.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              helpItem.content,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.5,
                              ),
                              maxLines: null,
                              overflow: TextOverflow.visible,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
  }

  double _calculateTextHeight(String title, String content, double maxWidth) {
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );
    titlePainter.layout(maxWidth: maxWidth - 32);
    final titleHeight = titlePainter.size.height;

    final contentPainter = TextPainter(
      text: TextSpan(
        text: content,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
        ),
      ),
      maxLines: null,
      textDirection: TextDirection.ltr,
    );
    contentPainter.layout(maxWidth: maxWidth - 32);
    final contentHeight = contentPainter.size.height;

    return titleHeight + 8 + contentHeight + 16;
  }

  Widget _buildImageErrorWidget() {
    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.image_not_supported,
              size: 30,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              '图片加载失败',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
