import 'package:flutter/widgets.dart';

import 'pixel_theme.dart';

/// A rectangle with one-step "stair" corners.
Path steppedRect(Rect r, [double u = PixelTheme.unit]) => Path()
  ..addRect(Rect.fromLTRB(r.left + u, r.top, r.right - u, r.bottom))
  ..addRect(Rect.fromLTRB(r.left, r.top + u, r.right, r.bottom - u));

/// Draws a stepped frame with an outline and a hard shadow straight down.
/// The bottom [PixelTheme.unit] of the size is reserved for the shadow; when
/// [pressed], the frame sits in that space instead and the shadow disappears.
class PixelFramePainter extends CustomPainter {
  const PixelFramePainter({
    required this.fill,
    this.border = PixelColors.shadow,
    this.shadow = true,
    this.pressed = false,
  });

  final Color fill;
  final Color? border;
  final bool shadow;
  final bool pressed;

  static const double u = PixelTheme.unit;

  @override
  void paint(Canvas canvas, Size size) {
    final reserved = shadow ? u : 0.0;
    final top = pressed ? reserved : 0.0;
    final body = Rect.fromLTWH(0, top, size.width, size.height - reserved);
    if (body.width < 3 * u || body.height < 3 * u) return;
    if (shadow && !pressed) canvas.drawPath(steppedRect(body.shift(const Offset(0, u))), PixelTheme.paint(PixelColors.shadow));
    final border = this.border;
    if (border == null) {
      canvas.drawPath(steppedRect(body), PixelTheme.paint(fill));
    } else {
      canvas.drawPath(steppedRect(body), PixelTheme.paint(border));
      canvas.drawPath(steppedRect(body.deflate(u)), PixelTheme.paint(fill));
    }
  }

  @override
  bool shouldRepaint(PixelFramePainter old) =>
      old.fill != fill || old.border != border || old.shadow != shadow || old.pressed != pressed;
}

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.color = PixelColors.panel,
    this.borderColor = PixelColors.shadow,
    this.padding = const EdgeInsets.all(12),
    this.shadow = true,
    this.pressed = false,
  });

  final Widget child;
  final Color color;
  final Color? borderColor;
  final EdgeInsets padding;
  final bool shadow;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    const u = PixelTheme.unit;
    final inset = borderColor == null ? 0.0 : u;
    final reserved = shadow ? u : 0.0;
    return CustomPaint(
      painter: PixelFramePainter(fill: color, border: borderColor, shadow: shadow, pressed: pressed),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          inset + padding.left,
          inset + padding.top + (pressed ? reserved : 0),
          inset + padding.right,
          inset + padding.bottom + (pressed ? 0 : reserved),
        ),
        child: child,
      ),
    );
  }
}
