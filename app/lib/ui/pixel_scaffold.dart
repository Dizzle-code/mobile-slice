import 'package:flutter/widgets.dart';

import 'pixel_button.dart';
import 'pixel_icons.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Screen frame: dotted background, optional header with back button, body, optional bottom bar.
class PixelScaffold extends StatelessWidget {
  const PixelScaffold({
    super.key,
    required this.body,
    this.title,
    this.onBack,
    this.actions = const [],
    this.bottom,
  });

  final String? title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final bottom = this.bottom;
    final onBack = this.onBack;
    return ColoredBox(
      color: PixelColors.background,
      child: CustomPaint(
        painter: const _DotGridPainter(),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: title == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          if (onBack != null) ...[
                            PixelIconButton(icon: PixelIcons.back, label: 'Zurück', onPressed: onBack),
                            const PixelGap(3),
                          ],
                          Expanded(
                            child: Semantics(header: true, child: PixelText.title(title, maxLines: 1)),
                          ),
                          for (final action in actions) ...[const PixelGap(2), action],
                        ],
                      ),
                    ),
            ),
            Expanded(child: SafeArea(top: title == null, bottom: bottom == null, child: body)),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const step = 6 * PixelTheme.unit;
    final dots = Path();
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        dots.addRect(Rect.fromLTWH(x, y, PixelTheme.unit / 2, PixelTheme.unit / 2));
      }
    }
    canvas.drawPath(dots, PixelTheme.paint(PixelColors.panel));
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
