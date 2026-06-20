import 'dart:math' as math;

import 'package:connssh/main.dart';
import 'package:connssh/pages/settings/other.dart';
import 'package:flutter/material.dart';

import '../../services/setting_service.dart';
import '../../widgets/app_style.dart';
import '../../widgets/app_toast.dart';

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
  bool _blurEffectsEnabled = true;
  int _easterEggCount = 0;

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

  final List<_PaletteOption> _paletteOptions = const [
    _PaletteOption(id: 'default', label: '默认'),
    _PaletteOption(id: 'orange', label: '橙色'),
    _PaletteOption(id: 'green', label: '绿色'),
    _PaletteOption(id: 'yellow', label: '黄色'),
    _PaletteOption(id: 'red', label: '红色'),
    _PaletteOption(id: 'pink', label: '粉色'),
    _PaletteOption(id: 'purple', label: '紫色'),
    _PaletteOption(id: 'cyan', label: '青色'),
    _PaletteOption(id: 'indigo', label: '靛蓝'),
    _PaletteOption(id: 'monochrome', label: '黑白'),
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
      _blurEffectsEnabled = settings.blurEffectsEnabled;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = currentSettings.copyWith(
        defaultThemeMode: _themeMode,
        defaultPageTheme: _pageTheme,
        blurEffectsEnabled: _blurEffectsEnabled,
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

  Future<void> _setThemeMode(String mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    await _saveSettings();
    if (mounted) {
      AppToast.show(
        context,
        message: '已切换到${_themeModeLabels[mode] ?? mode}',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }

  Future<void> _setPalette(String theme) async {
    if (theme == 'monochrome') {
      setState(() {
        _easterEggCount++;
      });

      if (_easterEggCount >= 5 && _easterEggCount <= 32) {
        AppToast.show(
          context,
          message: '$_easterEggCount',
          icon: Icons.touch_app_rounded,
          duration: const Duration(milliseconds: 350),
        );
      }

      if (_easterEggCount >= 32) {
        _easterEggCount = 0;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EggPage()),
        );
      }
    }

    if (_pageTheme == theme) return;
    setState(() => _pageTheme = theme);
    await _saveSettings();
    if (mounted) {
      final option = _paletteOptions.firstWhere(
        (item) => item.id == theme,
        orElse: () => _PaletteOption(id: theme, label: theme),
      );
      AppToast.show(
        context,
        message: '已切换到${option.label}',
        icon: Icons.palette_outlined,
      );
    }
  }

  Future<void> _setBlurEffectsEnabled(bool value) async {
    if (_blurEffectsEnabled == value) return;
    setState(() => _blurEffectsEnabled = value);
    await _saveSettings();
    if (mounted) {
      AppToast.show(
        context,
        message: value ? '已开启模糊效果' : '已关闭模糊效果',
        icon: value ? Icons.blur_on_rounded : Icons.blur_off_rounded,
      );
    }
  }

  Color _displayColorFor(_PaletteOption option) {
    return _themeColors[option.id]!;
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: const Text('主题设置'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _ThemePreviewCard(),
                const SizedBox(height: 12),
                _ThemeControlPanel(
                  themeMode: _themeMode,
                  pageTheme: _pageTheme,
                  blurEffectsEnabled: _blurEffectsEnabled,
                  modeLabels: _themeModeLabels,
                  paletteOptions: _paletteOptions,
                  displayColorFor: _displayColorFor,
                  onThemeModeChanged: _setThemeMode,
                  onPaletteChanged: _setPalette,
                  onBlurChanged: _setBlurEffectsEnabled,
                ),
              ],
            ),
    );
  }
}

class _ThemePreviewCard extends StatefulWidget {
  const _ThemePreviewCard();

  @override
  State<_ThemePreviewCard> createState() => _ThemePreviewCardState();
}

class _ThemePreviewCardState extends State<_ThemePreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool blurEnabled = AppVisualEffects.blurEnabledOf(context);

    return ClipRRect(
      borderRadius: AppRadius.largeRadius,
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.36),
          borderRadius: AppRadius.largeRadius,
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final double value = _controller.value;
            final double enter = Curves.easeOutCubic.transform(
              math.min(value / 0.24, 1),
            );
            final double exit = value < 0.72
                ? 0
                : Curves.easeInCubic.transform(
                    math.min((value - 0.72) / 0.28, 1),
                  );
            final double progress = enter * (1 - exit);
            final double opacity = value < 0.10
                ? Curves.easeOut.transform(value / 0.10)
                : value > 0.78
                ? Curves.easeIn.transform(
                    1 - math.min((value - 0.78) / 0.22, 1),
                  )
                : 1;
            final double top = -18 + 42 * progress;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 64, 14, 14),
                    child: Column(
                      children: const [
                        _PreviewConnectionTile(title: '连接到服务器'),
                        SizedBox(height: 10),
                        _PreviewConnectionTile(title: '打开 SFTP', tag: '文件'),
                        SizedBox(height: 10),
                        _PreviewConnectionTile(title: '同步终端外观'),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: top,
                  left: 16,
                  right: 16,
                  child: Opacity(
                    opacity: opacity.clamp(0, 1),
                    child: Center(
                      child: AppGlassSurface(
                        borderRadius: AppRadius.largeRadius,
                        blurSigma: 10,
                        opacity: blurEnabled ? 0.34 : 0.98,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '当前主题预览',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
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

class _PreviewConnectionTile extends StatelessWidget {
  const _PreviewConnectionTile({required this.title, this.tag});

  final String title;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.72)
            : colorScheme.surfaceContainerHighest.withOpacity(0.36),
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, color: colorScheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: AppRadius.largeRadius,
              ),
              child: Text(
                tag!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeControlPanel extends StatelessWidget {
  const _ThemeControlPanel({
    required this.themeMode,
    required this.pageTheme,
    required this.blurEffectsEnabled,
    required this.modeLabels,
    required this.paletteOptions,
    required this.displayColorFor,
    required this.onThemeModeChanged,
    required this.onPaletteChanged,
    required this.onBlurChanged,
  });

  final String themeMode;
  final String pageTheme;
  final bool blurEffectsEnabled;
  final Map<String, String> modeLabels;
  final List<_PaletteOption> paletteOptions;
  final Color Function(_PaletteOption option) displayColorFor;
  final ValueChanged<String> onThemeModeChanged;
  final ValueChanged<String> onPaletteChanged;
  final ValueChanged<bool> onBlurChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '色彩模式',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ThemeModeChoice(
                label: modeLabels['system'] ?? '跟随系统',
                mode: 'system',
                selected: themeMode == 'system',
                onTap: () => onThemeModeChanged('system'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeChoice(
                label: modeLabels['light'] ?? '浅色模式',
                mode: 'light',
                selected: themeMode == 'light',
                onTap: () => onThemeModeChanged('light'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ThemeModeChoice(
                label: modeLabels['dark'] ?? '深色模式',
                mode: 'dark',
                selected: themeMode == 'dark',
                onTap: () => onThemeModeChanged('dark'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '配色方案',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: paletteOptions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, index) {
            final option = paletteOptions[index];
            return _PaletteChoice(
              option: option,
              color: displayColorFor(option),
              selected: pageTheme == option.id,
              onTap: () => onPaletteChanged(option.id),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.42),
            borderRadius: AppRadius.largeRadius,
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.55),
            ),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('使用模糊'),
            subtitle: const Text('关闭后使用实体背景'),
            trailing: AppSwitch(
              value: blurEffectsEnabled,
              onChanged: onBlurChanged,
            ),
            onTap: () => onBlurChanged(!blurEffectsEnabled),
          ),
        ),
      ],
    );
  }
}

class _ThemeModeChoice extends StatelessWidget {
  const _ThemeModeChoice({
    required this.label,
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withOpacity(0.90)
              : colorScheme.surface.withOpacity(0.48),
          borderRadius: AppRadius.largeRadius,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ThemeModeSwatch(mode: mode),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSwatch extends StatelessWidget {
  const _ThemeModeSwatch({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    Widget inner;
    switch (mode) {
      case 'light':
        inner = const ColoredBox(color: Colors.white);
        break;
      case 'dark':
        inner = const ColoredBox(color: Colors.black);
        break;
      case 'system':
      default:
        inner = const Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 11,
              child: ColoredBox(color: Colors.white),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 11,
              child: ColoredBox(color: Colors.black),
            ),
          ],
        );
    }

    return SizedBox(
      width: 22,
      height: 22,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.largeRadius,
          border: Border.all(color: outline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: ClipRRect(
            borderRadius: AppRadius.largeRadius,
            clipBehavior: Clip.antiAlias,
            child: inner,
          ),
        ),
      ),
    );
  }
}

class _PaletteChoice extends StatelessWidget {
  const _PaletteChoice({
    required this.option,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final _PaletteOption option;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: option.label,
      child: AppPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.largeRadius,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color: option.id == 'yellow'
                      ? Colors.black
                      : colorScheme.onPrimary,
                  size: 20,
                )
              : null,
        ),
      ),
    );
  }
}

class _PaletteOption {
  const _PaletteOption({required this.id, required this.label});

  final String id;
  final String label;
}
