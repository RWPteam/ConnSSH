import 'package:flutter/material.dart';
import '../toolbar_customizer.dart';
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';

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
    'droidsan': 'Droid Sans Mono',
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
    'sauce'
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
    'druvbox'
  ];
  final List<String> _termTypes = [
    'xterm-256color',
    'xterm',
    'xterm-color',
    'vt100',
    'linux'
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
      final newSettings = AppSettings(
        defaultSftpPath: currentSettings.defaultSftpPath,
        defaultDownloadPath: currentSettings.defaultDownloadPath,
        defaultFontSize: _fontSize,
        defaultTermTheme: _termTheme,
        termType: _termType,
        defaultPageTheme: currentSettings.defaultPageTheme,
        defaultThemeMode: currentSettings.defaultThemeMode,
        defaultFonts: _defaultFonts,
      );

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();
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

  void _showFontSizeDialog() {
    double currentValue = _fontSize;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('字体大小设置'),
            content: Column(
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
                          setState(() {
                            currentValue = value;
                          });
                        },
                      ),
                    ),
                    Text('${currentValue.toInt()}px'),
                  ],
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: () async {
                  setState(() {
                    _fontSize = currentValue;
                  });
                  Navigator.of(context).pop();
                  await _saveSettings();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFontFamilyDialog() {
    String currentValue = _defaultFonts;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择字体'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _fontList
              .map((font) => RadioListTile<String>(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(_fontMap[font] ?? font),
                        ),
                        // 字体示例
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Aa',
                            style: TextStyle(
                              fontFamily: font == 'maple' ? null : font,
                              fontSize: 16,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: font,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _defaultFonts = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showTermThemeDialog() {
    String currentValue = _termTheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termThemes
              .map((theme) => RadioListTile<String>(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(_termThemeMap[theme] ?? theme),
                        ),
                        // 配色示例
                        _buildThemePreview(theme),
                      ],
                    ),
                    value: theme,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termTheme = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemePreview(String themeKey) {
    final colors = _themeColors[themeKey];
    if (colors == null) {
      return Container();
    }

    return Container(
      margin: EdgeInsets.only(left: 8),
      child: Row(
        children: [
          _buildColorSquare(colors['bg']!, Colors.white),
          SizedBox(width: 2),
          _buildColorSquare(colors['fg']!, Colors.black),
          SizedBox(width: 2),
          _buildColorSquare(colors['red']!, Colors.white),
          SizedBox(width: 2),
          _buildColorSquare(colors['green']!, Colors.white),
          SizedBox(width: 2),
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
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.grey.shade400,
          width: 0.5,
        ),
      ),
    );
  }

  void _showTermTypeDialog() {
    String currentValue = _termType;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termTypes
              .map((type) => RadioListTile<String>(
                    title: Text(type),
                    value: type,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termType = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
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
        title: const Text('SSH设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
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
            ),
    );
  }
}
