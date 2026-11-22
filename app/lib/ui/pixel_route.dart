import 'package:flutter/widgets.dart';

import 'pixel_theme.dart';

/// Page route that reveals the new page block by block, left to right.
class PixelRoute<T> extends PageRoute<T> {
  PixelRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 360);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      ColoredBox(color: PixelColors.background, child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) => animation.isCompleted
            ? child!
            : ClipPath(clipper: PixelWipeClipper(animation.value), child: child),
      );
}

class PixelWipeClipper extends CustomClipper<Path> {
  PixelWipeClipper(this.progress);

  final double progress;

  static const double cell = 8 * PixelTheme.unit;

  // Deterministic per-cell jitter so the wipe edge looks ragged but never flickers.
  static double _jitter(int col, int row) => ((col * 73856093) ^ (row * 19349663)).abs() % 1000 / 1000;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (progress >= 1) return path..addRect(Offset.zero & size);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final threshold = col / cols * 0.7 + _jitter(col, row) * 0.3;
        if (progress >= threshold) path.addRect(Rect.fromLTWH(col * cell, row * cell, cell, cell));
      }
    }
    return path;
  }

  @override
  bool shouldReclip(PixelWipeClipper old) => old.progress != progress;
}
