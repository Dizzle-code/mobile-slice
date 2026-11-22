import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Stepped slider with a label row and a number field ("Füllung  [15] %") above the track.
class PixelSlider extends StatelessWidget {
  const PixelSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.format,
    this.unit = '',
    this.detail,
    this.inputDigits,
    this.toInput,
    this.fromInput,
  }) : assert(divisions > 0 && max > min);

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;
  final String Function(double value)? format;

  /// Shown after the number field.
  final String unit;

  /// Extra muted text under the label, e.g. the preset name.
  final String Function(double value)? detail;

  /// Decimals in the number field; derived from the step when null.
  final int? inputDigits;

  /// Maps the slider value to the number shown in the field (default: the value itself).
  final double Function(double value)? toInput;

  /// Maps a typed number back to a slider value (default: clamped to [min]..[max]).
  final double Function(double typed)? fromInput;

  double get _step => (max - min) / divisions;

  double _snap(double raw) {
    final steps = ((raw - min) / _step).round().clamp(0, divisions);
    return min + steps * _step;
  }

  String _text(double v) => format?.call(v) ?? v.toStringAsFixed(0);

  int get _digits {
    final step = _step;
    if (step >= 1) return 0;
    if (step >= 0.1) return 1;
    if (step >= 0.01) return 2;
    return 3;
  }

  void _setFrom(double dx, double width) {
    final next = _snap(min + (dx / width).clamp(0.0, 1.0) * (max - min));
    if (next != value) {
      HapticFeedback.selectionClick();
      onChanged?.call(next);
    }
  }

  void _typed(double typed) {
    final next = fromInput?.call(typed) ?? typed.clamp(min, max).toDouble();
    if (next != value) onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final current = value.clamp(min, max).toDouble();
    final up = _snap(current + _step);
    final down = _snap(current - _step);
    final detail = this.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelText(label, color: enabled ? PixelColors.text : PixelColors.muted),
                    if (detail != null) PixelText.small(detail(current), color: PixelColors.muted),
                  ],
                ),
              ),
            ),
            const PixelGap(2),
            _NumberField(
              label: '$label eingeben',
              value: toInput?.call(current) ?? current,
              digits: inputDigits ?? _digits,
              signed: min < 0,
              enabled: enabled,
              onSubmitted: _typed,
            ),
            if (unit.isNotEmpty) ...[
              const PixelGap(1),
              ExcludeSemantics(child: PixelText(unit, color: enabled ? PixelColors.accent : PixelColors.muted)),
            ],
          ],
        ),
        const PixelGap(1),
        Semantics(
          slider: true,
          label: label,
          enabled: enabled,
          value: _text(current),
          increasedValue: _text(up),
          decreasedValue: _text(down),
          onIncrease: enabled && up != current ? () => onChanged!(up) : null,
          onDecrease: enabled && down != current ? () => onChanged!(down) : null,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (d) => _setFrom(d.localPosition.dx, width) : null,
                onHorizontalDragUpdate: enabled ? (d) => _setFrom(d.localPosition.dx, width) : null,
                child: SizedBox(
                  height: PixelTheme.minTouch,
                  width: width,
                  child: CustomPaint(painter: _SliderPainter((current - min) / (max - min), enabled)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Compact number input; commits on Enter or when it loses focus, reverts on invalid input.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.digits,
    required this.signed,
    required this.enabled,
    required this.onSubmitted,
  });

  final String label;
  final double value;
  final int digits;
  final bool signed;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(double v) {
    var text = v.toStringAsFixed(widget.digits);
    // Keep values typed more precisely than the step visible instead of rounding them away.
    if (double.parse(text) != v) {
      text = v.toStringAsFixed(3);
      if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text.replaceAll('.', ',');
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && (old.value != widget.value || old.digits != widget.digits)) {
      _controller.text = _format(widget.value);
    }
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else {
      _commit();
    }
    setState(() {});
  }

  void _commit() {
    final typed = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (typed != null && typed.isFinite && widget.enabled) widget.onSubmitted(typed);
    // Show what the parent actually applied (clamped, rounded) or revert invalid input.
    _controller.text = _format(widget.value);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final border = _focus.hasFocus ? PixelColors.accent : PixelColors.shadow;
    final allowed = widget.signed ? RegExp(r'[-0-9,.]') : RegExp(r'[0-9,.]');
    return GestureDetector(
      onTap: enabled ? _focus.requestFocus : null,
      child: SizedBox(
        width: 76,
        child: PixelPanel(
          color: PixelColors.background,
          borderColor: border,
          shadow: false,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Semantics(
            label: widget.label,
            child: EditableText(
              controller: _controller,
              focusNode: _focus,
              readOnly: !enabled,
              style: PixelTheme.body.copyWith(color: enabled ? PixelColors.accent : PixelColors.muted),
              textAlign: TextAlign.right,
              cursorColor: PixelColors.accent,
              backgroundCursorColor: PixelColors.muted,
              cursorWidth: PixelTheme.unit / 2,
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: widget.signed),
              inputFormatters: [FilteringTextInputFormatter.allow(allowed)],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _focus.unfocus(),
              autocorrect: false,
              enableSuggestions: false,
              selectionColor: PixelColors.accent.withValues(alpha: 0.4),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter(this.fraction, this.enabled);

  final double fraction;
  final bool enabled;

  static const u = PixelTheme.unit;
  static const thumbWidth = 6 * u;

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = 4 * u;
    final track = Rect.fromLTWH(0, (size.height - trackHeight) / 2, size.width, trackHeight);
    canvas.drawPath(steppedRect(track), PixelTheme.paint(PixelColors.shadow));
    canvas.drawRect(track.deflate(u), PixelTheme.paint(PixelColors.background));
    final travel = size.width - thumbWidth;
    final left = (travel * fraction / u).roundToDouble() * u;
    final filled = Rect.fromLTRB(track.left + u, track.top + u, left + thumbWidth / 2, track.bottom - u);
    if (filled.width > 0) canvas.drawRect(filled, PixelTheme.paint(enabled ? PixelColors.accent : PixelColors.muted));
    final thumb = Rect.fromLTWH(left, (size.height - 10 * u) / 2, thumbWidth, 10 * u);
    canvas
      ..save()
      ..translate(thumb.left, thumb.top);
    PixelFramePainter(fill: enabled ? PixelColors.text : PixelColors.muted).paint(canvas, thumb.size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.fraction != fraction || old.enabled != enabled;
}
