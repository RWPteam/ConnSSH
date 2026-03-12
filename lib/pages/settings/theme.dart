import 'dart:math';
import 'package:flutter/material.dart';
import 'package:connssh/main.dart';
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';

class ThemeSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const ThemeSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  bool _isLoading = true;
  String _themeMode = 'system';
  String _pageTheme = 'default';

  final Map<String, String> _themeModeMap = {
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
  };

  final Map<String, Color> _themeColors = {
    'default': Color(0xFF6750A4),
    'orange': Color(0xFFFF6F00),
    'green': Color(0xFF4CAF50),
    'yellow': Color(0xFFFFC107),
    'red': Color(0xFFF44336),
    'pink': Color(0xFFE91E63),
    'purple': Color(0xFF9C27B0),
    'cyan': Colors.cyan,
    'indigo': Colors.indigo,
    'monochrome': Color(0xFF000000),
  };

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
    'monochrome'
  ];

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
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = AppSettings(
        defaultSftpPath: currentSettings.defaultSftpPath,
        defaultDownloadPath: currentSettings.defaultDownloadPath,
        defaultFontSize: currentSettings.defaultFontSize,
        defaultTermTheme: currentSettings.defaultTermTheme,
        termType: currentSettings.termType,
        defaultPageTheme: _pageTheme,
        defaultThemeMode: _themeMode,
      );

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();
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
    } else {
      return MediaQuery.of(context).platformBrightness;
    }
  }

  ColorScheme _generateColorScheme(Color seedColor, Brightness brightness) {
    if (seedColor == _themeColors['monochrome']) {
      if (brightness == Brightness.dark) {
        return ColorScheme(
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.grey[300]!,
          onSecondary: Colors.black,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Colors.grey[900]!,
          onSurface: Colors.white,
          surfaceContainerHighest: Colors.grey[800]!,
          onSurfaceVariant: Colors.grey[300]!,
          outline: Colors.grey[700]!,
          outlineVariant: Colors.grey[800]!,
          shadow: Colors.black,
          scrim: Colors.black54,
          inverseSurface: Colors.grey[200]!,
          onInverseSurface: Colors.black,
          inversePrimary: Colors.black,
          primaryContainer: Colors.grey[900]!,
          onPrimaryContainer: Colors.white,
          secondaryContainer: Colors.grey[800]!,
          onSecondaryContainer: Colors.white,
          tertiary: Colors.grey[500]!,
          onTertiary: Colors.black,
          tertiaryContainer: Colors.grey[700]!,
          onTertiaryContainer: Colors.white,
          errorContainer: Colors.red[900]!,
          onErrorContainer: Colors.white,
          surfaceTint: Colors.transparent,
        );
      } else {
        return ColorScheme(
          brightness: Brightness.light,
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.grey[700]!,
          onSecondary: Colors.white,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Colors.grey[100]!,
          onSurface: Colors.black,
          surfaceContainerHighest: Colors.grey[200]!,
          onSurfaceVariant: Colors.grey[800]!,
          outline: Colors.grey[300]!,
          outlineVariant: Colors.grey[200]!,
          shadow: Colors.black,
          scrim: Colors.black54,
          inverseSurface: Colors.grey[800]!,
          onInverseSurface: Colors.white,
          inversePrimary: Colors.white,
          primaryContainer: Colors.grey[100]!,
          onPrimaryContainer: Colors.black,
          secondaryContainer: Colors.grey[200]!,
          onSecondaryContainer: Colors.black,
          tertiary: Colors.grey[500]!,
          onTertiary: Colors.white,
          tertiaryContainer: Colors.grey[300]!,
          onTertiaryContainer: Colors.black,
          errorContainer: Colors.red[100]!,
          onErrorContainer: Colors.red[900]!,
          surfaceTint: Colors.transparent,
        );
      }
    }

    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  Widget _buildColorPalette(String theme) {
    final seedColor = _themeColors[theme]!;
    final brightness = _getDisplayBrightness();
    final colorScheme = _generateColorScheme(seedColor, brightness);
    final isSelected = _pageTheme == theme;

    return Stack(
      children: [
        Container(
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
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12.0),
              ),
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
          ),
      ],
    );
  }

  void _showThemeModeDialog() {
    String currentValue = _themeMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主题风格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _themeModes
              .map((mode) => RadioListTile<String>(
                    title: Text(_themeModeMap[mode] ?? mode),
                    value: mode,
                    groupValue: currentValue,
                    onChanged: (value) async {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _themeMode = value;
                        });
                        await _saveSettings();
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                // 横屏布局
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
                                        _themeModeMap[mode] ?? mode,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: _themeMode == mode
                                          ? Icon(
                                              Icons.check_circle,
                                              color: Theme.of(context)
                                                  .primaryColor,
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
                              const SizedBox(height: 16),
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
                                      SliverGridDelegateWithFixedCrossAxisCount(
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
                                      onTap: () async {
                                        setState(() {
                                          _pageTheme = theme;
                                        });
                                        await _saveSettings();
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12.0),
                                          border: Border.all(
                                            color: isSelected
                                                ? Theme.of(context).primaryColor
                                                : Colors.grey,
                                            width: isSelected ? 2.0 : 1.0,
                                          ),
                                          color: isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onInverseSurface
                                              : Colors.transparent,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _buildColorPalette(theme),
                                            const SizedBox(height: 8),
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
                      ),
                    ],
                  );
                } else {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        // 主题风格设置
                        Container(
                          margin: const EdgeInsets.symmetric(
                              vertical: 6.0, horizontal: 16.0),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey,
                              width: 1.0,
                            ),
                            borderRadius: BorderRadius.circular(12.0),
                            color: Colors.transparent,
                          ),
                          child: ListTile(
                            title: Text(
                              '主题风格',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              _themeModeMap[_themeMode] ?? _themeMode,
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
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
                              onTap: () async {
                                setState(() {
                                  _pageTheme = theme;
                                });
                                await _saveSettings();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12.0),
                                  border: Border.all(
                                    color: Colors.grey,
                                    width: 1.0,
                                  ),
                                  color: isSelected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onInverseSurface
                                      : Colors.transparent,
                                ),
                                child: Center(
                                  child: _buildColorPalette(theme),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                }
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

    final leftPaint = Paint()..color = primaryColor;
    canvas.drawPath(leftArc, leftPaint);

    final rightTopArc = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        pi / 2,
        false,
      )
      ..lineTo(center.dx, center.dy)
      ..close();

    final rightTopPaint = Paint()..color = surfaceColor;
    canvas.drawPath(rightTopArc, rightTopPaint);
    final rightBottomArc = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        pi / 2,
        -pi / 2,
        false,
      )
      ..lineTo(center.dx, center.dy)
      ..close();

    final rightBottomPaint = Paint()..color = secondaryColor;
    canvas.drawPath(rightBottomArc, rightBottomPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
