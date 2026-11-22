import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_theme.dart';

/// Blocky progress bar. A null [value] shows a block sliding back and forth.
class PixelProgressBar extends StatefulWidget {
  const PixelProgressBar({super.key, required this.value, this.color = PixelColors.accent, this.height = 20, this.semanticLabel});

  final double? value;
  final Color color;
  final double height;
  final String? semanticLabel;

  @override
  State<PixelProgressBar> createState() => _PixelProgressBarState();
}

class _PixelProgressBarState extends State<PixelProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PixelProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      if (!_loop.isAnimating) _loop.repeat(reverse: true);
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value?.clamp(0.0, 1.0);
    return Semantics(
      label: widget.semanticLabel,
      value: value == null ? 'läuft' : '${(value * 100).round()} %',
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _BarPainter(value, _loop.value, widget.color),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter(this.value, this.phase, this.color);

  final double? value;
  final double phase;
  final Color color;

  static const u = PixelTheme.unit;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    canvas.drawPath(steppedRect(outer), PixelTheme.paint(PixelColors.shadow));
    final inner = outer.deflate(u);
    canvas.drawRect(inner, PixelTheme.paint(PixelColors.background));
    final track = inner.deflate(u);
    if (track.width <= 0) return;
    final value = this.value;
    final Rect fill;
    if (value == null) {
      final block = (track.width / 4 / u).floorToDouble() * u;
      final left = ((track.width - block) * phase / u).floorToDouble() * u;
      fill = Rect.fromLTWH(track.left + left, track.top, block, track.height);
    } else {
      // Snap to whole pixel units so the bar grows in steps.
      final width = (track.width * value / u).floorToDouble() * u;
      fill = Rect.fromLTWH(track.left, track.top, width, track.height);
    }
    if (fill.width <= 0) return;
    canvas.drawRect(fill, PixelTheme.paint(color));
    // Segment gaps every 4 units give the bar its block look.
    final gap = PixelTheme.paint(PixelColors.background);
    for (var x = track.left + 4 * u; x < fill.right; x += 4 * u) {
      canvas.drawRect(Rect.fromLTWH(x - u / 2, track.top, u / 2, track.height), gap);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value || old.phase != phase || old.color != color;
}
