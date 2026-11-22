import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_button.dart';
import 'pixel_frame.dart';
import 'pixel_icons.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// − value + control for exact numbers (wall count, temperatures, millimetres).
class PixelStepper extends StatelessWidget {
  const PixelStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.format,
  }) : assert(max > min && step > 0);

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? format;

  String _text(double v) => format?.call(v) ?? v.toStringAsFixed(0);

  /// Snaps to the step grid (from [min]) and avoids floating point dust like 0.30000000000000004.
  double _snap(double raw) {
    final steps = ((raw - min) / step).round();
    final snapped = (min + steps * step).clamp(min, max).toDouble();
    return double.parse(snapped.toStringAsFixed(6));
  }

  void _set(double next) {
    final snapped = _snap(next);
    if (snapped == value) return;
    HapticFeedback.selectionClick();
    onChanged?.call(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final canDown = enabled && value > min;
    final canUp = enabled && value < max;
    return Semantics(
      label: label,
      value: _text(value),
      increasedValue: canUp ? _text(_snap(value + step)) : null,
      decreasedValue: canDown ? _text(_snap(value - step)) : null,
      onIncrease: canUp ? () => _set(value + step) : null,
      onDecrease: canDown ? () => _set(value - step) : null,
      excludeSemantics: true,
      child: Row(
        children: [
          PixelIconButton(icon: PixelIcons.minus, label: '$label verringern', onPressed: canDown ? () => _set(value - step) : null),
          const PixelGap(2),
          Expanded(
            child: PixelPanel(
              color: PixelColors.background,
              shadow: false,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: PixelText.heading(_text(value), align: TextAlign.center, maxLines: 1),
            ),
          ),
          const PixelGap(2),
          PixelIconButton(icon: PixelIcons.plus, label: '$label erhöhen', onPressed: canUp ? () => _set(value + step) : null),
        ],
      ),
    );
  }
}
