import 'dart:async';
import 'dart:collection';

import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_button.dart';
import 'pixel_frame.dart';
import 'pixel_icon.dart';
import 'pixel_icons.dart';
import 'pixel_progress.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

class PixelDialogAction<T> {
  const PixelDialogAction(this.label, this.value, {this.style = PixelButtonStyle.secondary});

  final String label;
  final T value;
  final PixelButtonStyle style;
}

/// Modal pixel dialog; resolves with the chosen action's value or null when dismissed.
Future<T?> showPixelDialog<T>(
  BuildContext context, {
  required String title,
  required String message,
  required List<PixelDialogAction<T>> actions,
  PixelGlyph? icon,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0xB00D0D18),
      barrierLabel: 'Schließen',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: title,
              child: PixelPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (icon != null) ...[PixelIcon(icon, scale: 2), const PixelGap(3)],
                        Expanded(child: PixelText.heading(title)),
                      ],
                    ),
                    const PixelGap(3),
                    Flexible(child: SingleChildScrollView(child: PixelText(message, color: PixelColors.text))),
                    const PixelGap(4),
                    for (final action in actions) ...[
                      PixelButton(
                        label: action.label,
                        style: action.style,
                        expand: true,
                        onPressed: () => Navigator.of(context).pop(action.value),
                      ),
                      if (action != actions.last) const PixelGap(2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      transitionsBuilder: (context, animation, _, child) {
        // Scale in four hard steps instead of a smooth zoom.
        final stepped = (animation.value * 4).ceil() / 4;
        return Opacity(opacity: animation.value == 0 ? 0 : 1, child: Transform.scale(scale: 0.85 + 0.15 * stepped, child: child));
      },
    ),
  );
}

enum PixelToastKind { info, success, error }

/// Short message at the bottom of the screen; newer toasts replace older ones.
abstract final class PixelToast {
  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(BuildContext context, String message, {PixelToastKind kind = PixelToastKind.info}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    hide();
    final entry = OverlayEntry(builder: (context) => _Toast(message: message, kind: kind));
    _current = entry;
    overlay.insert(entry);
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
    _timer = Timer(const Duration(milliseconds: 2800), hide);
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message, required this.kind});

  final String message;
  final PixelToastKind kind;

  @override
  Widget build(BuildContext context) {
    final (glyph, color) = switch (kind) {
      PixelToastKind.info => (PixelIcons.info, PixelColors.accent),
      PixelToastKind.success => (PixelIcons.check, PixelColors.green),
      PixelToastKind.error => (PixelIcons.warning, PixelColors.red),
    };
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 88,
      child: _SlideIn(
        child: IgnorePointer(
          child: PixelPanel(
            borderColor: color,
            child: Row(
              children: [
                PixelIcon(glyph, scale: 1, color: color, secondColor: color),
                const PixelGap(3),
                Expanded(child: PixelText(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 220),
        builder: (context, t, child) =>
            Transform.translate(offset: Offset(0, (t * 6).round() * PixelTheme.unit), child: child),
        child: child,
      );
}

class TrophyPopupData {
  const TrophyPopupData({required this.glyph, required this.name, required this.description});

  final PixelGlyph glyph;
  final String name;
  final String description;
}

/// "Trophäe freigeschaltet!" card that bounces in; several unlocks are shown one after another.
abstract final class TrophyPopup {
  static final Queue<TrophyPopupData> _queue = Queue();
  static bool _showing = false;

  static void show(BuildContext context, TrophyPopupData data) {
    _queue.add(data);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) _next(overlay);
  }

  static void _next(OverlayState overlay) {
    if (_showing || _queue.isEmpty || !overlay.mounted) return;
    _showing = true;
    final data = _queue.removeFirst();
    late final OverlayEntry entry;
    var closed = false;
    void close() {
      if (closed) return;
      closed = true;
      if (entry.mounted) entry.remove();
      _showing = false;
      _next(overlay);
    }

    entry = OverlayEntry(builder: (context) => _TrophyCard(data: data, onClose: close));
    overlay.insert(entry);
    HapticFeedback.mediumImpact();
    SemanticsService.sendAnnouncement(
      View.of(overlay.context),
      'Trophäe freigeschaltet: ${data.name}',
      TextDirection.ltr,
    );
    Timer(const Duration(seconds: 4), close);
  }

  static void reset() {
    _queue.clear();
    _showing = false;
  }
}

class _TrophyCard extends StatelessWidget {
  const _TrophyCard({required this.data, required this.onClose});

  final TrophyPopupData data;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.paddingOf(context).top + 24,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (context, t, child) => Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        child: Semantics(
          button: true,
          label: 'Trophäe freigeschaltet: ${data.name}. ${data.description}',
          excludeSemantics: true,
          onTap: onClose,
          child: GestureDetector(
            onTap: onClose,
            child: PixelPanel(
              borderColor: PixelColors.yellow,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  PixelIcon(data.glyph, scale: 3, secondColor: PixelColors.yellow),
                  const PixelGap(4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const PixelText.small('TROPHÄE FREIGESCHALTET!', color: PixelColors.yellow),
                        PixelText.heading(data.name),
                        PixelText.small(data.description, color: PixelColors.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PixelProgressHandle {
  PixelProgressHandle._(this._navigator, this._route);

  final NavigatorState _navigator;
  final Route<void> _route;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (_route.isActive) _navigator.removeRoute(_route);
  }
}

/// Non-dismissible dialog with a live message and progress (null = still waiting).
PixelProgressHandle showPixelProgressDialog(
  BuildContext context, {
  required String title,
  required ValueListenable<String> message,
  required ValueListenable<double?> progress,
}) {
  final navigator = Navigator.of(context);
  final route = PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    barrierColor: const Color(0xB00D0D18),
    pageBuilder: (context, _, _) => PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: PixelPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PixelText.heading(title),
                  const PixelGap(3),
                  ValueListenableBuilder<String>(valueListenable: message, builder: (_, text, _) => PixelText(text)),
                  const PixelGap(3),
                  ValueListenableBuilder<double?>(
                    valueListenable: progress,
                    builder: (_, value, _) => PixelProgressBar(value: value, semanticLabel: title),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  navigator.push(route);
  return PixelProgressHandle._(navigator, route);
}
