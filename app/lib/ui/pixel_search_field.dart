import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Search input with a magnifier and a clear button that appears once something is typed.
class PixelSearchField extends StatefulWidget {
  const PixelSearchField({
    super.key,
    required this.controller,
    this.hint = 'Suchen',
    this.label = 'Suche',
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final String label;
  final FocusNode? focusNode;

  @override
  State<PixelSearchField> createState() => _PixelSearchFieldState();
}

class _PixelSearchFieldState extends State<PixelSearchField> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(PixelSearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _clear() {
    HapticFeedback.selectionClick();
    widget.controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final border = _focus.hasFocus ? PixelColors.accent : PixelColors.shadow;
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: PixelPanel(
        color: PixelColors.background,
        borderColor: border,
        shadow: false,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            PixelIcon(PixelIcons.search, scale: 1, color: PixelColors.muted, secondColor: PixelColors.muted),
            const PixelGap(2),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? ExcludeSemantics(child: PixelText(widget.hint, color: PixelColors.muted, maxLines: 1))
                        : const SizedBox.shrink(),
                  ),
                  Semantics(
                    label: widget.label,
                    textField: true,
                    child: EditableText(
                      controller: widget.controller,
                      focusNode: _focus,
                      style: PixelTheme.body,
                      cursorColor: PixelColors.accent,
                      backgroundCursorColor: PixelColors.muted,
                      cursorWidth: PixelTheme.unit / 2,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _focus.unfocus(),
                      selectionColor: PixelColors.accent.withValues(alpha: 0.4),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox(height: PixelTheme.minTouch, width: 12)
                  : Semantics(
                      button: true,
                      label: 'Suche leeren',
                      excludeSemantics: true,
                      onTap: _clear,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _clear,
                        child: SizedBox.square(
                          dimension: PixelTheme.minTouch,
                          child: Center(child: PixelIcon(PixelIcons.cross, scale: 1, color: PixelColors.muted, secondColor: PixelColors.muted)),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
