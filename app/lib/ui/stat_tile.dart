import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// A big number with icon and caption, e.g. "12 Drucke".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.glyph, required this.value, required this.label, this.color = PixelColors.accent});

  final PixelGlyph glyph;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: PixelPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIcon(glyph, scale: 2, secondColor: color),
            const PixelGap(2),
            PixelText.title(value, color: color, maxLines: 1),
            PixelText.small(label, color: PixelColors.muted, maxLines: 2),
          ],
        ),
      ),
    );
  }
}
