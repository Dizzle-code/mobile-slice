import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Label plus an on/off switch; the whole row is the touch target.
class PixelToggle extends StatelessWidget {
  const PixelToggle({super.key, required this.label, required this.value, required this.onChanged, this.subtitle});

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final subtitle = this.subtitle;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      hint: subtitle,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: PixelTheme.minTouch),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelText(label, color: enabled ? PixelColors.text : PixelColors.muted),
                    if (subtitle != null) PixelText.small(subtitle, color: PixelColors.muted),
                  ],
                ),
              ),
              const PixelGap(3),
              SizedBox(
                width: 64,
                height: 36,
                child: CustomPaint(painter: _SwitchPainter(value, enabled)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  const _SwitchPainter(this.on, this.enabled);

  final bool on;
  final bool enabled;

  static const u = PixelTheme.unit;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Offset.zero & size;
    canvas.drawPath(steppedRect(body), PixelTheme.paint(PixelColors.shadow));
    final fill = !enabled ? PixelColors.panel : (on ? PixelColors.green : PixelColors.background);
    canvas.drawPath(steppedRect(body.deflate(u)), PixelTheme.paint(fill));
    final knobSize = size.height - 4 * u;
    final left = on ? size.width - 2 * u - knobSize : 2 * u;
    final knob = Rect.fromLTWH(left, 2 * u, knobSize, knobSize);
    canvas.drawPath(steppedRect(knob), PixelTheme.paint(enabled ? PixelColors.text : PixelColors.muted));
  }

  @override
  bool shouldRepaint(_SwitchPainter old) => old.on != on || old.enabled != enabled;
}
