import 'dart:async';

import 'package:flutter/material.dart';

import 'app_style.dart';

class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppToastEntry(
        message: message,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
        duration: duration ??
            (actionLabel == null
                ? const Duration(milliseconds: 1800)
                : const Duration(seconds: 4)),
        onDismissed: () {
          if (_currentEntry == entry) {
            _currentEntry = null;
          }
          entry.remove();
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    final entry = _currentEntry;
    _currentEntry = null;
    entry?.remove();
  }
}

class _AppToastEntry extends StatefulWidget {
  const _AppToastEntry({
    required this.message,
    required this.duration,
    required this.onDismissed,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToastEntry> createState() => _AppToastEntryState();
}

class _AppToastEntryState extends State<_AppToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double topPadding = MediaQuery.paddingOf(context).top + 12;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _opacity,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AppGlassSurface(
                  borderRadius: AppRadius.largeRadius,
                  blurSigma: 12,
                  opacity: theme.brightness == Brightness.dark ? 0.62 : 0.78,
                  borderOpacity: 0.38,
                  enableBlur: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              widget.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (widget.actionLabel != null && widget.onAction != null) ...[
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: widget.onAction,
                              child: Text(widget.actionLabel!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
