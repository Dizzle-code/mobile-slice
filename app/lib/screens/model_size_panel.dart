import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../engine/profile_catalog.dart';
import '../model/mesh.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_stepper.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_text_field.dart';
import '../ui/pixel_theme.dart';
import '../util/format.dart';

const minModelScale = 0.05;
const maxModelScale = 50.0;

double clampScale(double scale) => double.parse(scale.clamp(minModelScale, maxModelScale).toStringAsFixed(4));

/// Whether the model, scaled uniformly around its base, fits the printer's build volume.
bool fitsBed(Bounds3 bounds, double scale, PrinterInfo printer) {
  const eps = 0.01;
  return bounds.sizeX * scale <= printer.bedX + eps &&
      bounds.sizeY * scale <= printer.bedY + eps &&
      bounds.sizeZ * scale <= printer.height + eps;
}

/// Largest scale that still fits the build volume, rounded down to 0.1 %.
double fitToBedScale(Bounds3 bounds, PrinterInfo printer) {
  final limits = [
    if (bounds.sizeX > 0) printer.bedX / bounds.sizeX,
    if (bounds.sizeY > 0) printer.bedY / bounds.sizeY,
    if (bounds.sizeZ > 0) printer.height / bounds.sizeZ,
  ];
  if (limits.isEmpty) return 1;
  return clampScale((limits.reduce(math.min) * 1000).floor() / 1000);
}

/// Model size as percent and linked X/Y/Z millimetres; changing one changes all.
class ModelSizePanel extends StatefulWidget {
  const ModelSizePanel({super.key, required this.bounds, required this.scale, required this.printer, required this.onChanged});

  final Bounds3 bounds;
  final double scale;
  final PrinterInfo printer;
  final ValueChanged<double>? onChanged;

  @override
  State<ModelSizePanel> createState() => _ModelSizePanelState();
}

class _ModelSizePanelState extends State<ModelSizePanel> {
  late final _fields = [for (var i = 0; i < 3; i++) TextEditingController()];

  List<double> get _sizes => [widget.bounds.sizeX, widget.bounds.sizeY, widget.bounds.sizeZ];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ModelSizePanel old) {
    super.didUpdateWidget(old);
    if (old.scale != widget.scale || old.bounds != widget.bounds) _sync();
  }

  void _sync() {
    for (var i = 0; i < 3; i++) {
      _fields[i].text = decimal(_sizes[i] * widget.scale, 1);
    }
  }

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _set(double scale) => widget.onChanged?.call(clampScale(scale));

  void _fromField(int axis, String text) {
    final mm = double.tryParse(text.trim().replaceAll(',', '.'));
    final original = _sizes[axis];
    if (mm == null || mm <= 0 || original <= 0) {
      setState(_sync);
      return;
    }
    _set(mm / original);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final fits = fitsBed(widget.bounds, widget.scale, widget.printer);
    final percent = widget.scale * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PixelStepper(
          label: 'Größe',
          value: double.parse(percent.toStringAsFixed(1)),
          min: minModelScale * 100,
          max: maxModelScale * 100,
          step: 5,
          format: (v) => '${decimal(v, v == v.roundToDouble() ? 0 : 1)} %',
          onChanged: enabled ? (v) => _set(v / 100) : null,
        ),
        const PixelGap(3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, axis) in ['X', 'Y', 'Z'].indexed) ...[
              if (i > 0) const PixelGap(2),
              Expanded(
                child: PixelTextField(
                  controller: _fields[i],
                  label: '$axis in mm',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onSubmitted: enabled ? (text) => _fromField(i, text) : null,
                ),
              ),
            ],
          ],
        ),
        const PixelGap(1),
        PixelText.small(
          fits ? 'Seiten bleiben im Verhältnis. Bett: ${decimal(widget.printer.bedX, 0)} × ${decimal(widget.printer.bedY, 0)} × ${decimal(widget.printer.height, 0)} mm'
              : 'Zu groß für das Druckbett.',
          color: fits ? PixelColors.muted : PixelColors.red,
        ),
        const PixelGap(3),
        Row(
          children: [
            Expanded(
              child: PixelButton(
                label: 'Auf Bett einpassen',
                icon: PixelIcons.resize,
                onPressed: enabled ? () => _set(fitToBedScale(widget.bounds, widget.printer)) : null,
              ),
            ),
            const PixelGap(2),
            PixelButton(label: '100 %', onPressed: enabled && widget.scale != 1 ? () => _set(1) : null),
          ],
        ),
      ],
    );
  }
}
