import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppRadius {
  AppRadius._();

  static const double small = 12;
  static const double medium = 16;
  static const double large = 18;
  static const double sheet = 24;

  static BorderRadius get smallRadius => BorderRadius.circular(small);
  static BorderRadius get mediumRadius => BorderRadius.circular(medium);
  static BorderRadius get largeRadius => BorderRadius.circular(large);
  static BorderRadius get sheetRadius => BorderRadius.circular(sheet);
}

class AppSpacing {
  AppSpacing._();

  static const double page = 16;
  static const double cardGap = 12;
}

class AppVisualEffects extends InheritedWidget {
  const AppVisualEffects({
    super.key,
    required this.blurEnabled,
    required super.child,
  });

  final bool blurEnabled;

  static bool blurEnabledOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppVisualEffects>()
            ?.blurEnabled ??
        true;
  }

  @override
  bool updateShouldNotify(AppVisualEffects oldWidget) {
    return blurEnabled != oldWidget.blurEnabled;
  }
}

bool _routeAnimationsSettled(BuildContext context) {
  final route = ModalRoute.of(context);
  final double animationValue = route?.animation?.value ?? 1;
  final double secondaryValue = route?.secondaryAnimation?.value ?? 0;
  return animationValue >= 0.999 && secondaryValue <= 0.001;
}

List<Listenable> _routeAnimationListenables(BuildContext context) {
  final route = ModalRoute.of(context);
  return <Listenable>[
    if (route?.animation != null) route!.animation!,
    if (route?.secondaryAnimation != null) route!.secondaryAnimation!,
  ];
}

class AppThemeFactory {
  AppThemeFactory._();

  static ThemeData build({
    required Brightness brightness,
    required Color seedColor,
    ColorScheme? dynamicScheme,
    bool monochrome = false,
    String? fontFamily,
    SystemUiOverlayStyle? systemOverlayStyle,
  }) {
    final bool isLight = brightness == Brightness.light;
    final ColorScheme colorScheme = dynamicScheme ??
        (monochrome
            ? _monochromeScheme(brightness)
            : ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: brightness,
              ));
    final Color scaffoldBackground = isLight
        ? const Color(0xFFF7F8FC)
        : colorScheme.surface;
    final Color cardColor = isLight
        ? Colors.white
        : colorScheme.surfaceContainerLow;

    final ButtonStyle sharedButtonStyle = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(0, 44)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
      ),
      elevation: WidgetStateProperty.all(0),
      shadowColor: WidgetStateProperty.all(Colors.transparent),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );

    return ThemeData(
      fontFamily: fontFamily,
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBackground,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemOverlayStyle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: AppRadius.largeRadius,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.largeRadius,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.largeRadius,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.largeRadius,
          side: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(style: sharedButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: sharedButtonStyle.copyWith(
          side: WidgetStateProperty.all(
            BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: sharedButtonStyle.copyWith(
          minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(const CircleBorder()),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.largeRadius),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    );
  }

  static ColorScheme _monochromeScheme(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return ColorScheme(
        brightness: Brightness.dark,
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.grey.shade300,
        onSecondary: Colors.black,
        error: Colors.redAccent,
        onError: Colors.white,
        surface: Colors.grey.shade900,
        onSurface: Colors.white,
        surfaceContainerHighest: Colors.grey.shade800,
        onSurfaceVariant: Colors.grey.shade300,
        outline: Colors.grey.shade700,
        outlineVariant: Colors.grey.shade800,
        shadow: Colors.black,
        scrim: Colors.black54,
        inverseSurface: Colors.grey.shade200,
        onInverseSurface: Colors.black,
        inversePrimary: Colors.black,
        primaryContainer: Colors.grey.shade900,
        onPrimaryContainer: Colors.white,
        secondaryContainer: Colors.grey.shade800,
        onSecondaryContainer: Colors.white,
        tertiary: Colors.grey.shade500,
        onTertiary: Colors.black,
        tertiaryContainer: Colors.grey.shade700,
        onTertiaryContainer: Colors.white,
        errorContainer: Colors.red.shade900,
        onErrorContainer: Colors.white,
        surfaceTint: Colors.transparent,
      );
    }
    return ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.grey.shade700,
      onSecondary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: Colors.grey.shade100,
      onSurface: Colors.black,
      surfaceContainerHighest: Colors.grey.shade200,
      onSurfaceVariant: Colors.grey.shade800,
      outline: Colors.grey.shade300,
      outlineVariant: Colors.grey.shade200,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: Colors.grey.shade800,
      onInverseSurface: Colors.white,
      inversePrimary: Colors.white,
      primaryContainer: Colors.grey.shade100,
      onPrimaryContainer: Colors.black,
      secondaryContainer: Colors.grey.shade200,
      onSecondaryContainer: Colors.black,
      tertiary: Colors.grey.shade500,
      onTertiary: Colors.white,
      tertiaryContainer: Colors.grey.shade300,
      onTertiaryContainer: Colors.black,
      errorContainer: Colors.red.shade100,
      onErrorContainer: Colors.red.shade900,
      surfaceTint: Colors.transparent,
    );
  }
}

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onChanged != null;
    final Color trackColor = value
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest.withOpacity(0.94);
    final Color thumbColor = value
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant.withOpacity(enabled ? 0.90 : 0.42);

    return Semantics(
      toggled: value,
      enabled: enabled,
      button: true,
      child: AppPressable(
        enabled: enabled,
        borderRadius: AppRadius.largeRadius,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 54,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: trackColor.withOpacity(enabled ? 1 : 0.44),
            borderRadius: AppRadius.largeRadius,
            border: Border.all(
              color: value
                  ? colorScheme.primary.withOpacity(0.56)
                  : colorScheme.outlineVariant.withOpacity(0.72),
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: thumbColor,
                borderRadius: AppRadius.largeRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppPressable extends StatelessWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = borderRadius ?? AppRadius.largeRadius;
    final bool canTap = enabled && (onTap != null || onLongPress != null);
    if (!canTap) return child;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}

class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blurSigma = 8,
    this.padding,
    this.opacity,
    this.borderOpacity = 0.28,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final double? opacity;
  final double borderOpacity;

  Widget _buildSurface(BuildContext context, {required bool allowBlur}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool blurEnabled = AppVisualEffects.blurEnabledOf(context) && allowBlur;
    final BorderRadius radius = borderRadius ?? AppRadius.largeRadius;
    final double backgroundOpacity = blurEnabled
        ? (opacity ?? (isDark ? 0.42 : 0.36))
        : (isDark ? 0.94 : 0.98);
    final Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: (isDark ? colorScheme.surface : Colors.white)
            .withOpacity(backgroundOpacity),
        borderRadius: radius,
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(
            blurEnabled ? borderOpacity : 0.5,
          ),
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (!blurEnabled) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.hardEdge,
          child: content,
        ),
      );
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.hardEdge,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppVisualEffects.blurEnabledOf(context)) {
      return _buildSurface(context, allowBlur: false);
    }

    final listenables = _routeAnimationListenables(context);
    if (listenables.isEmpty) {
      return _buildSurface(context, allowBlur: true);
    }

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        return _buildSurface(
          context,
          allowBlur: _routeAnimationsSettled(context),
        );
      },
    );
  }
}

class AppFloatingAppBarBackground extends StatelessWidget {
  const AppFloatingAppBarBackground({super.key});

  Widget _buildBackground(BuildContext context, {required bool allowBlur}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool blurEnabled = AppVisualEffects.blurEnabledOf(context);

    if (!blurEnabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surface : Colors.white,
        ),
        child: const SizedBox.expand(),
      );
    }

    if (!allowBlur) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: (isDark ? colorScheme.surface : Colors.white)
              .withOpacity(isDark ? 0.30 : 0.24),
        ),
        child: const SizedBox.expand(),
      );
    }

    return RepaintBoundary(
      child: ClipRect(
        clipBehavior: Clip.hardEdge,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (isDark ? colorScheme.surface : Colors.white)
                  .withOpacity(isDark ? 0.30 : 0.24),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenables = _routeAnimationListenables(context);

    if (listenables.isEmpty) {
      return _buildBackground(context, allowBlur: true);
    }

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        return _buildBackground(context, allowBlur: _routeAnimationsSettled(context));
      },
    );
  }
}

class AppFloatingAppBar extends StatelessWidget {
  const AppFloatingAppBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.leading,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight = kToolbarHeight,
  });

  final Widget title;
  final List<Widget> actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final double toolbarHeight;

  static double heightOf(BuildContext context, {double toolbarHeight = kToolbarHeight}) {
    return MediaQuery.paddingOf(context).top + toolbarHeight;
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    final route = ModalRoute.of(context);
    final bool canPop = automaticallyImplyLeading && (route?.canPop ?? false);
    final Widget? leadingWidget = leading ??
        (canPop
            ? AppIconActionButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null);
    final TextStyle? textStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        );

    return Positioned(
      left: 0,
      top: 0,
      right: 0,
      child: SizedBox(
        height: top + toolbarHeight,
        child: Stack(
          children: [
            const Positioned.fill(child: AppFloatingAppBarBackground()),
            Positioned(
              left: 0,
              right: 0,
              top: top,
              height: toolbarHeight,
              child: IconTheme.merge(
                data: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
                child: DefaultTextStyle.merge(
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Row(
                    children: [
                      if (leadingWidget != null)
                        SizedBox(
                          width: 56,
                          height: toolbarHeight,
                          child: Center(child: leadingWidget),
                        )
                      else
                        const SizedBox(width: 16),
                      Expanded(child: title),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Row(mainAxisSize: MainAxisSize.min, children: actions),
                        const SizedBox(width: 8),
                      ] else
                        const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  final Widget title;
  final Widget body;
  final List<Widget> actions;
  final Widget? bottom;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    final double topPadding = AppFloatingAppBar.heightOf(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: body,
            ),
          ),
          AppFloatingAppBar(
            title: title,
            actions: actions,
            automaticallyImplyLeading: automaticallyImplyLeading,
          ),
          if (bottom != null)
            Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
        ],
      ),
    );
  }
}

class AppIconActionButton extends StatelessWidget {
  const AppIconActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 24,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: AppPressable(
        enabled: enabled,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: enabled
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant.withOpacity(0.38),
          ),
        ),
      ),
    );
  }
}

class AppBlurredColoredBackground extends StatelessWidget {
  const AppBlurredColoredBackground({
    super.key,
    required this.color,
    this.opacity = 0.58,
    this.blurSigma = 12,
  });

  final Color color;
  final double opacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final bool blurEnabled = AppVisualEffects.blurEnabledOf(context);
    if (!blurEnabled) {
      return ColoredBox(color: color, child: const SizedBox.expand());
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: ColoredBox(
          color: color.withOpacity(opacity),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class AppActionMenuEntry {
  const AppActionMenuEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

class AppActionMenu extends StatelessWidget {
  const AppActionMenu({
    super.key,
    required this.entries,
    this.width = 154,
  });

  final List<AppActionMenuEntry> entries;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AppGlassSurface(
      blurSigma: 14,
      opacity: 0.46,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: entries
            .map(
              (entry) => _AppActionMenuItem(
                width: width,
                icon: entry.icon,
                label: entry.label,
                destructive: entry.destructive,
                onTap: entry.onTap,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _AppActionMenuItem extends StatelessWidget {
  const _AppActionMenuItem({
    required this.width,
    required this.icon,
    required this.label,
    required this.destructive,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color color = destructive ? colorScheme.error : colorScheme.primary;
    return AppPressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: 42,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: destructive ? colorScheme.error : null,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}


class AppAnimatedActionMenu extends StatefulWidget {
  const AppAnimatedActionMenu({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topRight,
  });

  final bool visible;
  final Widget child;
  final Alignment alignment;

  @override
  State<AppAnimatedActionMenu> createState() => _AppAnimatedActionMenuState();
}

class _AppAnimatedActionMenuState extends State<AppAnimatedActionMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  bool _buildChild = false;

  @override
  void initState() {
    super.initState();
    _buildChild = widget.visible;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visible ? 1 : 0,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _scale = Tween<double>(begin: 0.92, end: 1).animate(curved);
    _slide = Tween<Offset>(begin: const Offset(0.04, -0.04), end: Offset.zero)
        .animate(curved);
  }

  @override
  void didUpdateWidget(AppAnimatedActionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      setState(() => _buildChild = true);
      _controller.forward();
    } else {
      _controller.reverse().whenComplete(() {
        if (mounted && !widget.visible) {
          setState(() => _buildChild = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_buildChild) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.visible,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            alignment: widget.alignment,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

void showAppAnchoredActionMenu(
  BuildContext context, {
  required BuildContext anchorContext,
  required List<AppActionMenuEntry> entries,
  double width = 170,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final anchorObject = anchorContext.findRenderObject();
  final overlayObject = overlay?.context.findRenderObject();
  if (overlay == null || anchorObject is! RenderBox || overlayObject is! RenderBox) {
    return;
  }

  final anchorTopLeft = overlayObject.globalToLocal(
    anchorObject.localToGlobal(Offset.zero),
  );
  final overlaySize = overlayObject.size;
  final estimatedHeight = entries.length * 42.0 + 16;
  final topBelow = anchorTopLeft.dy + anchorObject.size.height + 6;
  final double maxTop = overlaySize.height - estimatedHeight - 12 < 12
      ? 12
      : overlaySize.height - estimatedHeight - 12;
  final double maxRight = overlaySize.width - width - 12 < 12
      ? 12
      : overlaySize.width - width - 12;
  final double top = (topBelow + estimatedHeight > overlaySize.height - 12
          ? (anchorTopLeft.dy - estimatedHeight - 6)
          : topBelow)
      .clamp(12.0, maxTop)
      .toDouble();
  final double right = (overlaySize.width - anchorTopLeft.dx - anchorObject.size.width)
      .clamp(12.0, maxRight)
      .toDouble();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppAnchoredActionMenuOverlay(
      top: top,
      right: right,
      width: width,
      entries: entries,
      onRemove: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AppAnchoredActionMenuOverlay extends StatefulWidget {
  const _AppAnchoredActionMenuOverlay({
    required this.top,
    required this.right,
    required this.width,
    required this.entries,
    required this.onRemove,
  });

  final double top;
  final double right;
  final double width;
  final List<AppActionMenuEntry> entries;
  final VoidCallback onRemove;

  @override
  State<_AppAnchoredActionMenuOverlay> createState() =>
      _AppAnchoredActionMenuOverlayState();
}

class _AppAnchoredActionMenuOverlayState extends State<_AppAnchoredActionMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _scale = Tween<double>(begin: 0.92, end: 1).animate(curved);
    _slide = Tween<Offset>(begin: const Offset(0.04, -0.04), end: Offset.zero)
        .animate(curved);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss([VoidCallback? afterDismiss]) async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    if (mounted) {
      widget.onRemove();
      afterDismiss?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuEntries = widget.entries
        .map(
          (entry) => AppActionMenuEntry(
            icon: entry.icon,
            label: entry.label,
            destructive: entry.destructive,
            onTap: () => _dismiss(entry.onTap),
          ),
        )
        .toList(growable: false);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _dismiss(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: widget.top,
          right: widget.right,
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                alignment: Alignment.topRight,
                child: AppActionMenu(width: widget.width, entries: menuEntries),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SettingCard extends StatelessWidget {
  const SettingCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    // 设置页卡片背后是纯色页面背景，不需要 BackdropFilter。
    // 用实体背景可以避免路由切换动画期间大量模糊层同时重绘导致卡顿。
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainerLow : Colors.white,
          borderRadius: AppRadius.largeRadius,
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(0.52),
          ),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.largeRadius,
          clipBehavior: Clip.antiAlias,
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

class AppMenuTile extends StatelessWidget {
  const AppMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingCard(
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.10),
            borderRadius: AppRadius.largeRadius,
          ),
          child: Icon(icon, color: colorScheme.primary, size: 22),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class AppActionSheetItem<T> {
  const AppActionSheetItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<AppActionSheetItem<T>> items,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: items.map((item) {
                    final Color foreground = item.destructive
                        ? colorScheme.error
                        : colorScheme.onSurface;
                    return ListTile(
                      leading: Icon(
                        item.icon,
                        color: item.destructive ? colorScheme.error : colorScheme.primary,
                      ),
                      title: Text(item.label, style: TextStyle(color: foreground)),
                      onTap: () => Navigator.of(context).pop(item.value),
                    );
                  }).toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
