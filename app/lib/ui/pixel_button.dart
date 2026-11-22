import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

enum PixelButtonStyle { primary, secondary, danger }

/// Pressable pixel button: sinks 4 px into its shadow while held.
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = PixelButtonStyle.secondary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PixelGlyph? icon;
  final PixelButtonStyle style;
  final bool expand;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = switch ((widget.style, _enabled)) {
      (_, false) => (PixelColors.panel, PixelColors.muted),
      (PixelButtonStyle.primary, _) => (PixelColors.accent, PixelColors.background),
      (PixelButtonStyle.danger, _) => (PixelColors.red, PixelColors.text),
      (PixelButtonStyle.secondary, _) => (PixelColors.panel, PixelColors.text),
    };
    final icon = widget.icon;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          PixelIcon(icon, scale: 1, color: ink, secondColor: ink),
          const PixelGap(2),
        ],
        Flexible(child: PixelText(widget.label, color: ink, maxLines: 1, align: TextAlign.center)),
      ],
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onTap: _enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: PixelTheme.minTouch + PixelTheme.unit),
          child: PixelPanel(
            color: fill,
            shadow: _enabled,
            pressed: _pressed,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(widthFactor: 1, heightFactor: 1, child: content),
          ),
        ),
      ),
    );
  }
}

/// Square button with just a glyph, e.g. "back" in a header.
class PixelIconButton extends StatefulWidget {
  const PixelIconButton({super.key, required this.icon, required this.label, required this.onPressed, this.color});

  final PixelGlyph icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  State<PixelIconButton> createState() => _PixelIconButtonState();
}

class _PixelIconButtonState extends State<PixelIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: PixelTheme.minTouch + PixelTheme.unit,
          child: PixelPanel(
            color: widget.color ?? PixelColors.panel,
            shadow: enabled,
            pressed: _pressed,
            padding: EdgeInsets.zero,
            child: Center(
              child: PixelIcon(
                widget.icon,
                scale: 1,
                color: enabled ? PixelColors.text : PixelColors.muted,
                secondColor: enabled ? PixelColors.accent : PixelColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
