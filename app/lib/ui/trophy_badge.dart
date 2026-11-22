import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';
import 'pixel_progress.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// One trophy: colored and framed in yellow when earned, grey with progress when locked.
class TrophyBadge extends StatelessWidget {
  const TrophyBadge({
    super.key,
    required this.glyph,
    required this.name,
    required this.description,
    required this.unlocked,
    this.progress = 0,
    this.progressLabel,
  });

  final PixelGlyph glyph;
  final String name;
  final String description;
  final bool unlocked;
  final double progress;
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    final progressLabel = this.progressLabel;
    return Semantics(
      label: '$name, ${unlocked ? 'freigeschaltet' : 'gesperrt'}. $description'
          '${!unlocked && progressLabel != null ? '. Fortschritt $progressLabel' : ''}',
      excludeSemantics: true,
      child: PixelPanel(
        borderColor: unlocked ? PixelColors.yellow : PixelColors.shadow,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PixelIcon(
                  glyph,
                  scale: 3,
                  color: unlocked ? PixelColors.text : PixelColors.muted,
                  secondColor: unlocked ? PixelColors.yellow : PixelColors.panel,
                ),
                if (!unlocked)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: PixelIcon(PixelIcons.lock, scale: 1, color: PixelColors.muted, secondColor: PixelColors.muted),
                  ),
              ],
            ),
            const PixelGap(3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PixelText.heading(name, color: unlocked ? PixelColors.yellow : PixelColors.text, maxLines: 1),
                  PixelText.small(description, color: PixelColors.muted),
                  if (!unlocked) ...[
                    const PixelGap(2),
                    PixelProgressBar(value: progress, height: 16, color: PixelColors.muted),
                    if (progressLabel != null) ...[
                      const PixelGap(1),
                      PixelText.small(progressLabel, color: PixelColors.muted),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

