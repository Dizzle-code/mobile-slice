import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

class PixelOption<T> {
  const PixelOption(this.value, this.label, {this.subtitle, this.glyph, this.swatch});

  final T value;
  final String label;
  final String? subtitle;
  final PixelGlyph? glyph;
  final Color? swatch;
}

/// One row of equal segments; exactly one is selected.
class PixelSegmented<T> extends StatelessWidget {
  const PixelSegmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<PixelOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return PixelPanel(
      padding: EdgeInsets.zero,
      color: PixelColors.background,
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option.value == value,
                inMutuallyExclusiveGroup: true,
                label: option.label,
                excludeSemantics: true,
                onTap: onChanged == null ? null : () => onChanged!(option.value),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onChanged!(option.value);
                        },
                  child: Container(
                    height: PixelTheme.minTouch - 2 * PixelTheme.unit,
                    alignment: Alignment.center,
                    color: option.value == value ? PixelColors.accent : null,
                    child: PixelText(
                      option.label,
                      maxLines: 1,
                      color: option.value == value ? PixelColors.background : PixelColors.text,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical list of options with a square marker, optional color swatch and subtitle.
class PixelChoiceList<T> extends StatelessWidget {
  const PixelChoiceList({super.key, required this.options, required this.value, required this.onChanged});

  final List<PixelOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options) _row(option),
      ],
    );
  }

  Widget _row(PixelOption<T> option) {
    final selected = option.value == value;
    final subtitle = option.subtitle;
    final glyph = option.glyph;
    final swatch = option.swatch;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: option.label,
      hint: subtitle,
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged!(option.value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(option.value);
              },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: PixelTheme.minTouch + 8),
          child: Row(
            children: [
              SizedBox.square(dimension: 20, child: CustomPaint(painter: _MarkerPainter(selected))),
              const PixelGap(3),
              if (swatch != null) ...[
                SizedBox.square(
                  dimension: 20,
                  child: CustomPaint(painter: _SwatchPainter(swatch)),
                ),
                const PixelGap(2),
              ],
              if (glyph != null) ...[
                PixelIcon(glyph, scale: 1),
                const PixelGap(2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelText(option.label, color: selected ? PixelColors.accent : PixelColors.text),
                    if (subtitle != null) PixelText.small(subtitle, color: PixelColors.muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.selected);

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    const u = PixelTheme.unit;
    final box = Offset.zero & size;
    canvas.drawPath(steppedRect(box), PixelTheme.paint(selected ? PixelColors.accent : PixelColors.muted));
    canvas.drawRect(box.deflate(u), PixelTheme.paint(PixelColors.background));
    if (selected) canvas.drawRect(box.deflate(2 * u), PixelTheme.paint(PixelColors.accent));
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.selected != selected;
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawPath(steppedRect(box), PixelTheme.paint(PixelColors.shadow));
    canvas.drawRect(box.deflate(PixelTheme.unit), PixelTheme.paint(color));
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}
