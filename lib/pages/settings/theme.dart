import 'dart:math';

import 'package:connssh/main.dart';
import 'package:connssh/pages/settings/other.dart';
import 'package:flutter/material.dart';

import '../../services/setting_service.dart';

class ThemeSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const ThemeSettingsPage({
    super.key,
    required this.settingsService,
    required this.onSettingsChanged,
  });

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  bool _isLoading = true;
  String _themeMode = 'system';
  String _pageTheme = 'default';
  bool _useMaterialYou = false;
  int _easterEggCount = 0;

  final List<String> _themeModes = ['system', 'light', 'dark'];
  final List<String> _pageThemes = [
    'default',
    'orange',
    'green',
    'yellow',
    'red',
    'pink',
    'purple',
    'cyan',
    'indigo',
    'monochrome',
  ];

  final Map<String, String> _themeModeLabels = {
    'system': '跟随系统',
    'light': '浅色模式',
    'dark': '深色模式',
  };

  final Map<String, Color> _themeColors = {
    'default': Colors.blueAccent,
    'orange': Colors.orange,
    'green': Colors.green,
    'yellow': Colors.yellow,
    'red': Colors.red,
    'pink': Colors.pink,
    'purple': Colors.purple,
    'cyan': Colors.cyan,
    'indigo': Colors.indigo,
    'monochrome': Colors.black,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _themeMode = settings.defaultThemeMode;
      _pageTheme = settings.defaultPageTheme;
      _useMaterialYou = settings.defaultPageTheme == 'materialyou';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = currentSettings.copyWith(
        defaultThemeMode: _themeMode,
        defaultPageTheme: _pageTheme,
      );
      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();
      // 重新加载应用主题
      MyApp.of(context)?.loadSettings();
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

  Brightness _getDisplayBrightness() {
    if (_themeMode == 'light') {
      return Brightness.light;
    } else if (_themeMode == 'dark') {
      return Brightness.dark;
    }
    return MediaQuery.of(context).platformBrightness;
  }

  ColorScheme _generateColorScheme(Color seedColor, Brightness brightness) {
    if (seedColor == _themeColors['monochrome']) {
      if (brightness == Brightness.dark) {
        return const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.grey,
          surface: Color(0xFF121212),
        );
      }
      return const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.grey,
        surface: Color(0xFFF5F5F5),
      );
    }
    return ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  }

  Widget _buildColorPalette(String theme) {
    final seedColor = _themeColors[theme]!;
    final brightness = _getDisplayBrightness();
    final colorScheme = _generateColorScheme(seedColor, brightness);
    final isSelected = _pageTheme == theme;

    return Stack(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CustomPaint(
            painter: _ColorPalettePainter(
              primaryColor: colorScheme.primary,
              surfaceColor: colorScheme.surface,
              secondaryColor: colorScheme.secondary,
            ),
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: colorScheme.onPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showThemeModeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主题风格'),
        content: RadioGroup<String>(
          groupValue: _themeMode,
          onChanged: (value) async {
            if (value != null) {
              Navigator.of(context).pop();
              setState(() => _themeMode = value);
              await _saveSettings();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _themeModes
                .map(
                  (mode) => RadioListTile<String>(
                    title: Text(_themeModeLabels[mode] ?? mode),
                    value: mode,
                    selected: _themeMode == mode,
                  ),
                )
                .toList(),
          ),
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

  Future<void> _onColorThemeTap(String theme) async {
    if (theme == 'monochrome') {
      setState(() {
        _easterEggCount++;
      });

      if (_easterEggCount >= 5 && _easterEggCount <= 32) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.removeCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('$_easterEggCount'),
            duration: const Duration(milliseconds: 200),
          ),
        );
      }

      if (_easterEggCount >= 32) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.removeCurrentSnackBar();
        _easterEggCount = 0;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EggPage()),
        );
      }
    }

    setState(() {
      _pageTheme = theme;
    });
    await _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (isLandscape) {
                  return Row(
                    children: [
                      Container(
                        width: constraints.maxWidth * 1 / 3,
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16.0),
                              child: Text(
                                '主题风格',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey,
                                    width: 1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                child: ListView.builder(
                                  itemCount: _themeModes.length,
                                  itemBuilder: (context, index) {
                                    final mode = _themeModes[index];
                                    return ListTile(
                                      title: Text(
                                        _themeModeLabels[mode] ?? mode,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: _themeMode == mode
                                          ? Icon(
                                              Icons.check_circle,
                                              color: Theme.of(
                                                context,
                                              ).primaryColor,
                                            )
                                          : null,
                                      onTap: () async {
                                        setState(() {
                                          _themeMode = mode;
                                        });
                                        await _saveSettings();
                                      },
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16.0,
                                            vertical: 12.0,
                                          ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SwitchListTile(
                                  title: const Text(
                                    '使用 Material You',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  value: _useMaterialYou,
                                  onChanged: (value) async {
                                    setState(() {
                                      _useMaterialYou = value;
                                      if (value) {
                                        _pageTheme = 'materialyou';
                                      } else if (_pageTheme == 'materialyou') {
                                        _pageTheme = 'default';
                                      }
                                    });
                                    await _saveSettings();
                                  },
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                              if (!_useMaterialYou) ...[
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 16.0),
                                  child: Text(
                                    '页面主题',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GridView.builder(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          childAspectRatio: 1.2,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                        ),
                                    itemCount: _pageThemes.length,
                                    itemBuilder: (context, index) {
                                      final theme = _pageThemes[index];
                                      final isSelected = _pageTheme == theme;

                                      return GestureDetector(
                                        onTap: () => _onColorThemeTap(theme),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12.0,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? Theme.of(
                                                      context,
                                                    ).primaryColor
                                                  : Colors.grey,
                                              width: isSelected ? 2.0 : 1.0,
                                            ),
                                            color: isSelected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onInverseSurface
                                                : Colors.transparent,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              _buildColorPalette(theme),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 6.0,
                          horizontal: 16.0,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1.0),
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: ListTile(
                          title: const Text(
                            '主题风格',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _themeModeLabels[_themeMode] ?? _themeMode,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey,
                          ),
                          onTap: _showThemeModeDialog,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 6.0,
                          horizontal: 16.0,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey, width: 1.0),
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: SwitchListTile(
                          title: const Text(
                            '使用 Material You',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          value: _useMaterialYou,
                          onChanged: (value) async {
                            setState(() {
                              _useMaterialYou = value;
                              if (value) {
                                _pageTheme = 'materialyou';
                              } else if (_pageTheme == 'materialyou') {
                                _pageTheme = 'default';
                              }
                            });
                            await _saveSettings();
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 16.0,
                          ),
                        ),
                      ),
                      if (!_useMaterialYou) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Text(
                            '页面主题',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _pageThemes.length,
                          itemBuilder: (context, index) {
                            final theme = _pageThemes[index];
                            final isSelected = _pageTheme == theme;

                            return GestureDetector(
                              onTap: () => _onColorThemeTap(theme),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                  color: isSelected
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onInverseSurface
                                      : Colors.transparent,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [_buildColorPalette(theme)],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ColorPalettePainter extends CustomPainter {
  final Color primaryColor;
  final Color surfaceColor;
  final Color secondaryColor;

  _ColorPalettePainter({
    required this.primaryColor,
    required this.surfaceColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final leftArc = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        -pi,
        false,
      )
      ..close();
    canvas.drawPath(leftArc, Paint()..color = primaryColor);

    final rightTopArc = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(rightTopArc, Paint()..color = surfaceColor);

    final rightBottomArc = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        pi / 2,
        -pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(rightBottomArc, Paint()..color = secondaryColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
