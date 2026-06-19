import 'package:connssh/main.dart';
import 'package:flutter/material.dart';
import '../toolbar_customizer.dart';
import '../../services/setting_service.dart';
import '../../widgets/app_style.dart';
import '../../widgets/app_toast.dart';

class SSHSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const SSHSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SSHSettingsPage> createState() => _SSHSettingsPageState();
}

class _SSHSettingsPageState extends State<SSHSettingsPage> {
  bool _isLoading = true;
  double _fontSize = 12.0;
  String _termTheme = 'dark';
  String _termType = 'xterm-256color';
  String _defaultFonts = 'maple';

  final Map<String, String> _fontMap = {
    'maple': 'maple（默认）',
    'droidsans': 'Droid Sans Mono',
    'ohossans': 'HarmonyOS Sans',
    'jetbrain': 'Jetbrain Mono',
    'roboto': 'Roboto',
    'sauce': 'Sauce Code Pro',
  };

  final List<String> _fontList = [
    'maple',
    'droidsans',
    'ohossans',
    'jetbrain',
    'roboto',
    'sauce',
  ];

  final Map<String, String> _termThemeMap = {
    'dark': '深色',
    'black': '高对比度',
    'light': '浅色',
    'xshell': 'XShell',
    'dracula': 'Dracula Dark',
    'druvbox': 'Druvbox Dark',
  };

  final Map<String, Map<String, Color>> _themeColors = {
    'dark': {
      'bg': Color(0XFF1E1E1E),
      'fg': Color(0XFFCCCCCC),
      'red': Color(0XFFCD3131),
      'green': Color(0XFF0DBC79),
      'blue': Color(0XFF2472C8),
    },
    'black': {
      'bg': Color(0XFF000000),
      'fg': Color(0XFFFFFFFF),
      'red': Color(0XFFCD3131),
      'green': Color(0XFF0DBC79),
      'blue': Color(0XFF2472C8),
    },
    'light': {
      'bg': Color(0XFFF8F4E8),
      'fg': Color(0XFF222222),
      'red': Color(0XFFAA2222),
      'green': Color(0XFF008800),
      'blue': Color(0XFF0044BB),
    },
    'xshell': {
      'bg': Color(0XFF000000),
      'fg': Color(0XFFF0F0F0),
      'red': Color(0XFFCD0000),
      'green': Color(0XFF00CD00),
      'blue': Color(0XFF0000EE),
    },
    'dracula': {
      'bg': Color(0XFF282A36),
      'fg': Color(0XFFF8F8F2),
      'red': Color(0XFFFF5555),
      'green': Color(0XFF50FA7B),
      'blue': Color(0XFF8BE9FD),
    },
    'druvbox': {
      'bg': Color(0XFF282828),
      'fg': Color(0XFFEBDBB2),
      'red': Color(0XFFCC241D),
      'green': Color(0XFF98971A),
      'blue': Color(0XFF458588),
    },
  };

  final List<String> _termThemes = [
    'dark',
    'black',
    'light',
    'xshell',
    'dracula',
    'druvbox',
  ];
  final List<String> _termTypes = [
    'xterm-256color',
    'xterm',
    'xterm-color',
    'vt100',
    'linux',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _fontSize = settings.defaultFontSize;
      _termTheme = settings.defaultTermTheme;
      _termType = settings.termType;
      _defaultFonts = settings.defaultFonts;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = currentSettings.copyWith(
        defaultFontSize: _fontSize,
        defaultTermTheme: _termTheme,
        termType: _termType,
        defaultFonts: _defaultFonts,
      );

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();
      MyApp.of(this.context)?.loadSettings();
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('保存失败'),
            content: Text(e.toString()),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _showFontSizeDialog() async {
    double currentValue = _fontSize;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        '字体大小设置',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Text('大小: '),
                              Expanded(
                                child: Slider(
                                  value: currentValue,
                                  min: 8,
                                  max: 24,
                                  divisions: 16,
                                  label: currentValue.toStringAsFixed(1),
                                  onChanged: (value) {
                                    modalSetState(() {
                                      currentValue = value;
                                    });
                                  },
                                ),
                              ),
                              Text('${currentValue.toInt()}px'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      setState(() {
        _fontSize = currentValue;
      });
      await _saveSettings();
      if (mounted) {
        AppToast.show(
          context,
          message: '已更新字体大小',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  Future<void> _showFontFamilyDialog() async {
    final value = await _showSelectionSheet<String>(
      title: '选择字体',
      values: _fontList,
      currentValue: _defaultFonts,
      labelBuilder: (font) => _fontMap[font] ?? font,
      trailingBuilder: (font) => _buildFontPreview(font),
    );

    if (value != null) {
      setState(() {
        _defaultFonts = value;
      });
      await _saveSettings();
      if (mounted) {
        AppToast.show(
          context,
          message: '已切换字体',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  Future<void> _showTermThemeDialog() async {
    final value = await _showSelectionSheet<String>(
      title: '终端主题',
      values: _termThemes,
      currentValue: _termTheme,
      labelBuilder: (theme) => _termThemeMap[theme] ?? theme,
      trailingBuilder: _buildThemePreview,
    );

    if (value != null) {
      setState(() {
        _termTheme = value;
      });
      await _saveSettings();
      if (mounted) {
        AppToast.show(
          context,
          message: '已切换终端主题',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  Widget _buildFontPreview(String font) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
        borderRadius: AppRadius.smallRadius,
      ),
      child: Text(
        'Aa',
        style: TextStyle(
          fontFamily: font == 'maple' ? null : font,
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildThemePreview(String themeKey) {
    final colors = _themeColors[themeKey];
    if (colors == null) {
      return Container();
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildColorSquare(colors['bg']!, Colors.white),
          const SizedBox(width: 2),
          _buildColorSquare(colors['fg']!, Colors.black),
          const SizedBox(width: 2),
          _buildColorSquare(colors['red']!, Colors.white),
          const SizedBox(width: 2),
          _buildColorSquare(colors['green']!, Colors.white),
          const SizedBox(width: 2),
          _buildColorSquare(colors['blue']!, Colors.white),
        ],
      ),
    );
  }

  Widget _buildColorSquare(Color color, Color textColor) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.smallRadius,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    );
  }

  Future<void> _showTermTypeDialog() async {
    final value = await _showSelectionSheet<String>(
      title: '终端类型',
      values: _termTypes,
      currentValue: _termType,
      labelBuilder: (type) => type,
    );

    if (value != null) {
      setState(() {
        _termType = value;
      });
      await _saveSettings();
      if (mounted) {
        AppToast.show(
          context,
          message: '已切换终端类型',
          icon: Icons.check_circle_outline_rounded,
        );
      }
    }
  }

  Future<T?> _showSelectionSheet<T>({
    required String title,
    required List<T> values,
    required T currentValue,
    required String Function(T value) labelBuilder,
    Widget Function(T value)? trailingBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: values.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final value = values[index];
                      final bool selected = value == currentValue;
                      return AppPressable(
                        onTap: () => Navigator.of(context).pop(value),
                        borderRadius: AppRadius.largeRadius,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withOpacity(0.72)
                                : Colors.transparent,
                            borderRadius: AppRadius.largeRadius,
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(labelBuilder(value))),
                              if (trailingBuilder != null)
                                trailingBuilder(value),
                              const SizedBox(width: 8),
                              AnimatedOpacity(
                                opacity: selected ? 1 : 0,
                                duration: const Duration(milliseconds: 160),
                                child: Icon(
                                  Icons.check_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomShortcutBarMessage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ToolbarCustomizationPage(
          settingsService: widget.settingsService,
          onSettingsChanged: () {
            _loadSettings();
            widget.onSettingsChanged();
          },
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AppMenuTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: const Text('SSH设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildSettingTile(
                  title: '字体',
                  subtitle: _fontMap[_defaultFonts] ?? _defaultFonts,
                  onTap: _showFontFamilyDialog,
                  icon: Icons.font_download,
                ),
                _buildSettingTile(
                  title: '字体大小',
                  subtitle: '${_fontSize.toInt()}px',
                  onTap: _showFontSizeDialog,
                  icon: Icons.text_fields,
                ),
                _buildSettingTile(
                  title: '终端主题',
                  subtitle: _termThemeMap[_termTheme] ?? _termTheme,
                  onTap: _showTermThemeDialog,
                  icon: Icons.palette,
                ),
                _buildSettingTile(
                  title: '终端类型',
                  subtitle: _termType,
                  onTap: _showTermTypeDialog,
                  icon: Icons.category,
                ),
                _buildSettingTile(
                  title: '自定义快捷栏',
                  subtitle: '配置快捷栏样式',
                  onTap: _showCustomShortcutBarMessage,
                  icon: Icons.dashboard_customize,
                ),
              ],
            ),
    );
  }
}
