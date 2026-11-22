import 'package:flutter/widgets.dart';

import 'pixel_theme.dart';

/// A 16×16 pixel graphic written as text rows: `#` main color, `+` second color,
/// anything else transparent. Short rows and missing rows count as empty.
class PixelGlyph {
  PixelGlyph(this.name, List<String> rows) : rows = List.unmodifiable(rows) {
    if (rows.length > size || rows.any((row) => row.length > size)) {
      throw ArgumentError('Glyph $name ist größer als ${size}x$size');
    }
  }

  static const size = 16;

  final String name;
  final List<String> rows;

  late final List<(int, int)> main = _cells('#');
  late final List<(int, int)> second = _cells('+');

  List<(int, int)> _cells(String mark) => [
        for (var y = 0; y < rows.length; y++)
          for (var x = 0; x < rows[y].length; x++)
            if (rows[y][x] == mark) (x, y),
      ];
}

class PixelIcon extends StatelessWidget {
  const PixelIcon(
    this.glyph, {
    super.key,
    this.scale = 2,
    this.color = PixelColors.text,
    this.secondColor = PixelColors.accent,
    this.semanticLabel,
  });

  final PixelGlyph glyph;

  /// Screen pixels per glyph pixel; integers keep every pixel the same size.
  final int scale;
  final Color color;
  final Color secondColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dimension = (PixelGlyph.size * scale).toDouble();
    final icon = CustomPaint(
      size: Size.square(dimension),
      painter: _GlyphPainter(glyph, scale.toDouble(), color, secondColor),
    );
    final label = semanticLabel;
    return label == null ? ExcludeSemantics(child: icon) : Semantics(label: label, image: true, child: icon);
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.scale, this.color, this.secondColor);

  final PixelGlyph glyph;
  final double scale;
  final Color color;
  final Color secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (cells, tone) in [(glyph.main, color), (glyph.second, secondColor)]) {
      if (cells.isEmpty) continue;
      final path = Path();
      for (final (x, y) in cells) {
        path.addRect(Rect.fromLTWH(x * scale, y * scale, scale, scale));
      }
      canvas.drawPath(path, PixelTheme.paint(tone));
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.scale != scale || old.color != color || old.secondColor != secondColor;
}
