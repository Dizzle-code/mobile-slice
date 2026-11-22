import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Single-line text input built directly on [EditableText].
class PixelTextField extends StatefulWidget {
  const PixelTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final String? errorText;

  @override
  State<PixelTextField> createState() => _PixelTextFieldState();
}

class _PixelTextFieldState extends State<PixelTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorText;
    final border = error != null ? PixelColors.red : (_focus.hasFocus ? PixelColors.accent : PixelColors.shadow);
    final hint = widget.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PixelText.small(widget.label, color: PixelColors.muted),
        const PixelGap(1),
        GestureDetector(
          onTap: _focus.requestFocus,
          child: PixelPanel(
            color: PixelColors.background,
            borderColor: border,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Stack(
              children: [
                if (hint != null)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? ExcludeSemantics(child: PixelText(hint, color: PixelColors.muted, maxLines: 1))
                        : const SizedBox.shrink(),
                  ),
                Semantics(
                  label: widget.label,
                  child: EditableText(
                    controller: widget.controller,
                    focusNode: _focus,
                    style: PixelTheme.body,
                    cursorColor: PixelColors.accent,
                    backgroundCursorColor: PixelColors.muted,
                    cursorWidth: PixelTheme.unit / 2,
                    keyboardType: widget.keyboardType,
                    obscureText: widget.obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: widget.inputFormatters,
                    textInputAction: widget.textInputAction,
                    onSubmitted: widget.onSubmitted,
                    selectionColor: PixelColors.accent.withValues(alpha: 0.4),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const PixelGap(1),
          PixelText.small(error, color: PixelColors.red),
        ],
      ],
    );
  }
}
