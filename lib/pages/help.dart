import 'package:flutter/material.dart';
import 'dart:async';

import '../widgets/app_style.dart';

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
ConnSSH 版本 2.2.0

修复了以下问题：
* SFTP下载完文件会退回主页
新增功能：
* 终端页面支持复制了，长按文字选中后会直接复制到剪贴板

如有问题或建议，请前往本项目GitHub仓库提交issue
若您访问不便，可发送邮件至：
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
    _pageController = PageController(initialPage: 0, viewportFraction: 0.96);
    _startTimer();
  }

  void _startTimer() {
    final duration = _currentPage == helpItems.length - 1
        ? const Duration(seconds: 15)
        : const Duration(seconds: 6);

    _timer = Timer.periodic(duration, (timer) {
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

  void _jumpToLastPage() {
    final lastPageIndex = helpItems.length - 1;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        lastPageIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppPageScaffold(
      title: const Text('帮助'),
      actions: [
        AppIconActionButton(
          tooltip: '更新日志',
          icon: Icons.history_rounded,
          onPressed: _jumpToLastPage,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SettingCard(
              padding: const EdgeInsets.all(20),
              margin: EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ConnSSH',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '一个便捷的SSH和SFTP连接管理工具',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: helpItems.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
                _resetTimer();
              },
              itemBuilder: (context, index) {
                final item = helpItems[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: HelpCard(helpItem: item),
                );
              },
              scrollDirection: Axis.horizontal,
              pageSnapping: true,
              padEnds: true,
            ),
          ),
          const SizedBox(height: 12),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIconActionButton(
                    tooltip: '上一页',
                    icon: Icons.chevron_left_rounded,
                    onPressed: _currentPage > 0
                        ? () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                            _resetTimer();
                          }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_currentPage + 1} / ${helpItems.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 8),
                  AppIconActionButton(
                    tooltip: '下一页',
                    icon: Icons.chevron_right_rounded,
                    onPressed: _currentPage < helpItems.length - 1
                        ? () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                            _resetTimer();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HelpItem {
  final String title;
  final String content;
  final String? imagePath;

  HelpItem({required this.title, required this.content, this.imagePath});
}

class HelpCard extends StatelessWidget {
  final HelpItem helpItem;

  const HelpCard({super.key, required this.helpItem});

  @override
  Widget build(BuildContext context) {
    final bool isAboutFeedback = helpItem.title == '关于 & 反馈';
    final colorScheme = Theme.of(context).colorScheme;

    return SettingCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(8),
      child: isAboutFeedback
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildTextContent(context),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (helpItem.imagePath != null)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withOpacity(0.24),
                            borderRadius: AppRadius.mediumRadius,
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadius.mediumRadius,
                            child: helpItem.imagePath!.startsWith('http')
                                ? Image.network(
                                    helpItem.imagePath!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildImageErrorWidget(context),
                                  )
                                : Image.asset(
                                    helpItem.imagePath!,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _buildImageErrorWidget(context),
                                  ),
                          ),
                        ),
                      ),
                    if (helpItem.imagePath != null) const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: _buildTextContent(context),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildTextContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          helpItem.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          helpItem.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  Widget _buildImageErrorWidget(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 30,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '图片加载失败',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
