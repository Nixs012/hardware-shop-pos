import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Premium shared button system — reusable across the entire POS app.
///
/// Variants (use the static factory or named constructors):
///   * [PrimaryButton.primary]  — solid blue fill
///   * [PrimaryButton.secondary] — elevated dark surface with border
///   * [PrimaryButton.outline] — transparent fill, border
///   * [PrimaryButton.icon]    — icon-only, ≥44px, with tooltip + semantics
///   * [PrimaryButton.destructive] — restrained red, only for destructive actions
///
/// States supported: normal, hover (web/desktop only), focus, pressed
/// (slight scale + opacity), disabled. 150ms transitions.
/// Respects reduced-motion via [MediaQuery.disableAnimations].
class PrimaryButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? tooltip;
  final String? semanticsLabel;
  final double radius;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final double? width;
  final Color? foregroundColor;
  final Color? backgroundColor;

  const PrimaryButton.primary({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.tooltip,
    this.semanticsLabel,
    this.radius = AppTheme.radiusMd,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.width,
    this.foregroundColor,
    this.backgroundColor,
  }) : _variant = _PrimaryVariant.primary;

  const PrimaryButton.secondary({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.tooltip,
    this.semanticsLabel,
    this.radius = AppTheme.radiusMd,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.width,
    this.foregroundColor,
    this.backgroundColor,
  }) : _variant = _PrimaryVariant.secondary;

  const PrimaryButton.outline({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.tooltip,
    this.semanticsLabel,
    this.radius = AppTheme.radiusMd,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.width,
    this.foregroundColor,
    this.backgroundColor,
  }) : _variant = _PrimaryVariant.outline;

  const PrimaryButton.icon({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.isLoading = false,
    this.tooltip,
    this.semanticsLabel,
    this.radius = AppTheme.radiusSm,
    this.fontSize = 14,
    this.padding = const EdgeInsets.all(10),
    this.width,
    this.foregroundColor,
    this.backgroundColor,
  }) : _variant = _PrimaryVariant.icon;

  const PrimaryButton.destructive({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.tooltip,
    this.semanticsLabel,
    this.radius = AppTheme.radiusMd,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    this.width,
    this.foregroundColor,
    this.backgroundColor,
  }) : _variant = _PrimaryVariant.destructive;

  final _PrimaryVariant _variant;

  bool get enabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final useAnimations = MediaQuery.of(context).disableAnimations == false;
    final isHover = _variant == _PrimaryVariant.icon
        ? false
        : _HoverWatcher.of(context)?.isHovering ?? false;

    // Resolve colours per variant
    final Color bg;
    final Color fg;
    final Color? border;
    final double opacity = enabled && isHover ? 0.85 : 1.0;

    switch (_variant) {
      case _PrimaryVariant.primary:
        bg = backgroundColor ?? AppTheme.primaryColor;
        fg = foregroundColor ?? AppTheme.textPrimary;
        border = null;
        break;
      case _PrimaryVariant.secondary:
        bg = backgroundColor ?? AppTheme.cardBackground;
        fg = foregroundColor ?? AppTheme.textPrimary;
        border = AppTheme.borderColor;
        break;
      case _PrimaryVariant.outline:
        bg = backgroundColor ?? Colors.transparent;
        fg = foregroundColor ?? AppTheme.textPrimary;
        border = AppTheme.borderColor;
        break;
      case _PrimaryVariant.icon:
        bg = backgroundColor ?? AppTheme.cardBackground;
        fg = foregroundColor ?? AppTheme.textPrimary;
        border = AppTheme.borderColor;
        break;
      case _PrimaryVariant.destructive:
        bg = backgroundColor ?? AppTheme.errorColor.withValues(alpha: 0.12);
        fg = foregroundColor ?? AppTheme.errorColor;
        border = AppTheme.borderColor;
        break;
    }

    final child = _buildChild(fg);

    Widget button = _variant == _PrimaryVariant.icon
        ? IconButton(
            onPressed: enabled ? onPressed : null,
            tooltip: tooltip,
            icon: child,
            style: IconButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              minimumSize: const Size(44, 44),
              padding: padding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: BorderSide(color: border ?? Colors.transparent, width: 1),
              ),
            ),
          )
        : ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: bg.withValues(alpha: opacity),
              foregroundColor: fg,
              disabledBackgroundColor: AppTheme.borderColor.withValues(alpha: 0.3),
              disabledForegroundColor: AppTheme.textSecondary,
              padding: padding,
              minimumSize: const Size(44, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
                side: BorderSide(color: border ?? Colors.transparent, width: 1),
              ),
              animationDuration: useAnimations ? const Duration(milliseconds: 150) : Duration.zero,
            ),
            child: child,
          );

    // Wrap with tooltip if specified (for non-icon variants)
    if (tooltip != null && _variant != _PrimaryVariant.icon) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    // Apply width constraint
    if (width != null && _variant != _PrimaryVariant.icon) {
      button = SizedBox(
        width: width,
        child: button,
      );
    }

    // Icon-only variant gets semantics
    if (_variant == _PrimaryVariant.icon) {
      return Semantics(
        label: semanticsLabel,
        button: true,
        child: button,
      );
    }
    return button;
  }

  Widget _buildChild(Color fg) {
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: fontSize,
            height: fontSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: fg,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(label!),
          ],
        ],
      );
    }

    if (_variant == _PrimaryVariant.icon) {
      return icon != null
          ? Icon(icon, color: fg, size: fontSize + 4)
          : const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: fontSize + 4),
          const SizedBox(width: 8),
        ],
        if (label != null) Text(label!),
      ],
    );
  }
}

// Internal hover watcher for web/desktop hover state.
class _HoverWatcher extends InheritedWidget {
  final bool isHovering;

  const _HoverWatcher({
    super.key,
    required this.isHovering,
    required super.child,
  });

  static _HoverWatcher? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_HoverWatcher>();
  }

  @override
  bool updateShouldNotify(_HoverWatcher old) => isHovering != old.isHovering;
}

class _HoverWatcherHost extends StatefulWidget {
  final Widget child;
  const _HoverWatcherHost({super.key, required this.child});

  @override
  State<_HoverWatcherHost> createState() => _HoverWatcherHostState();
}

class _HoverWatcherHostState extends State<_HoverWatcherHost> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: _HoverWatcher(
        isHovering: isHovering,
        child: widget.child,
      ),
    );
  }
}

enum _PrimaryVariant {
  primary,
  secondary,
  outline,
  icon,
  destructive,
}
