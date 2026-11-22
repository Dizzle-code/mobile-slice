import 'package:flutter/widgets.dart';

/// The fixed 8-color palette and text scale every component draws with.
abstract final class PixelColors {
  static const background = Color(0xFF1B1B2F);
  static const panel = Color(0xFF2A2A48);
  static const accent = Color(0xFFFF8A3D);
  static const green = Color(0xFF5BD46A);
  static const red = Color(0xFFE8475B);
  static const yellow = Color(0xFFFFD447);
  static const text = Color(0xFFF2EFE6);
  static const muted = Color(0xFF8C8AA8);

  // Not a palette color: the background darkened for hard shadows and outlines.
  static const shadow = Color(0xFF0D0D18);
}

enum PixelTextKind { small, body, heading, title, display }

/// The selectable UI fonts. [scale] evens out how large each font looks at the same size.
enum AppFont {
  pixelify('Pixelify Sans', 'PixelifySans', 1, 'Die Pixel-Schrift der App'),
  atkinson('Atkinson Hyperlegible', 'AtkinsonHyperlegible', 0.9, 'Besonders gut lesbar'),
  system('System (Roboto)', null, 0.9, 'Die Schrift von Android');

  const AppFont(this.label, this.family, this.scale, this.description);

  final String label;

  /// Null uses the platform default.
  final String? family;
  final double scale;
  final String description;
}

abstract final class PixelTheme {
  /// The current UI font; the app rebuilds everything when it changes.
  static final font = ValueNotifier<AppFont>(AppFont.pixelify);

  static String? get fontFamily => font.value.family;

  /// Every size, gap and stroke is a multiple of this.
  static const double unit = 4;

  static const double minTouch = 48;

  static double fontSize(PixelTextKind kind) => switch (kind) {
        PixelTextKind.small => 12,
        PixelTextKind.body => 16,
        PixelTextKind.heading => 20,
        PixelTextKind.title => 24,
        PixelTextKind.display => 32,
      };

  static TextStyle text(PixelTextKind kind, {Color color = PixelColors.text}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize(kind) * font.value.scale,
        height: 1.25,
        color: color,
        letterSpacing: 0,
        fontWeight: kind == PixelTextKind.body || kind == PixelTextKind.small ? FontWeight.w400 : FontWeight.w600,
        decoration: TextDecoration.none,
      );

  static TextStyle get body => text(PixelTextKind.body);

  /// A paint that never smooths edges.
  static Paint paint(Color color) => Paint()
    ..color = color
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;
}

/// Gap of [units] × 4 px.
class PixelGap extends StatelessWidget {
  const PixelGap(this.units, {super.key});

  final int units;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: units * PixelTheme.unit);
}
