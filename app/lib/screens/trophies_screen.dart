import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../data/print_history.dart';
import '../trophies/trophy_catalog.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_progress.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/trophy_badge.dart';
import '../util/format.dart';

class TrophiesScreen extends StatelessWidget {
  const TrophiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return PixelScaffold(
      title: 'Trophäen',
      body: ValueListenableBuilder<Map<String, DateTime>>(
        valueListenable: services.trophies.unlocked,
        builder: (context, unlocked, _) => ValueListenableBuilder<List<PrintRecord>>(
          valueListenable: services.history.records,
          builder: (context, records, _) {
            final trophyContext = TrophyContext(records);
            final catalog = services.trophies.catalog;
            // Earned first (newest on top), then the closest to unlocking.
            final sorted = [...catalog]..sort((a, b) {
                final ua = unlocked[a.id], ub = unlocked[b.id];
                if (ua != null && ub != null) return ub.compareTo(ua);
                if (ua != null) return -1;
                if (ub != null) return 1;
                return b.progress(trophyContext).fraction.compareTo(a.progress(trophyContext).fraction);
              });
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                PixelPanel(
                  borderColor: PixelColors.yellow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        PixelIcon(PixelIcons.trophy, scale: 2, secondColor: PixelColors.yellow),
                        const PixelGap(3),
                        Expanded(child: PixelText.heading('${unlocked.length} von ${catalog.length} freigeschaltet')),
                      ]),
                      const PixelGap(2),
                      PixelProgressBar(
                        value: catalog.isEmpty ? 0 : unlocked.length / catalog.length,
                        color: PixelColors.yellow,
                        semanticLabel: 'Trophäen',
                      ),
                    ],
                  ),
                ),
                const PixelGap(4),
                for (final trophy in sorted) ...[
                  _badge(trophy, unlocked[trophy.id], trophyContext),
                  const PixelGap(2),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _badge(Trophy trophy, DateTime? unlockedAt, TrophyContext context) {
    final progress = trophy.progress(context);
    return TrophyBadge(
      glyph: trophy.glyph,
      name: trophy.name,
      description: unlockedAt == null ? trophy.description : '${trophy.description} · ${formatDateTime(unlockedAt)}',
      unlocked: unlockedAt != null,
      progress: progress.fraction,
      progressLabel: progress.label,
    );
  }
}
