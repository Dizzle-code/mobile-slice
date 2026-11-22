import 'package:flutter/widgets.dart';

import 'pixel_button.dart';
import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

/// Bottom sheet that slides up in hard steps; resolves with the value passed to `Navigator.pop`.
Future<T?> showPixelSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  PixelGlyph? icon,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0xB00D0D18),
      barrierLabel: 'Schließen',
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, _, _) => PixelSheet(title: title, icon: icon, child: Builder(builder: builder)),
      transitionsBuilder: (context, animation, _, child) {
        // Slide in four hard steps instead of a smooth glide.
        final stepped = (animation.value * 4).ceil() / 4;
        return FractionalTranslation(translation: Offset(0, 1 - stepped), child: child);
      },
    ),
  );
}

/// The sheet's frame: title row with a close button, scrollable content, keyboard-aware.
class PixelSheet extends StatelessWidget {
  const PixelSheet({super.key, required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final PixelGlyph? icon;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final icon = this.icon;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: (media.size.height - media.viewInsets.bottom) * 0.85),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: title,
            child: PixelPanel(
              shadow: false,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + media.padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[PixelIcon(icon, scale: 2), const PixelGap(3)],
                      Expanded(child: PixelText.heading(title)),
                      PixelIconButton(icon: PixelIcons.cross, label: 'Schließen', onPressed: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                  const PixelGap(3),
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
