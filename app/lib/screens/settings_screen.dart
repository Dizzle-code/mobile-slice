import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_choice.dart';
import '../ui/pixel_stepper.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _shareLog(BuildContext context) async {
    try {
      await AppScope.of(context).slicer.shareLog();
    } on PlatformException catch (e) {
      if (context.mounted) PixelToast.show(context, e.code == 'empty' ? 'Noch kein Log vorhanden' : (e.message ?? e.code));
    }
  }

  Future<void> _confirm(BuildContext context, String title, String message, Future<void> Function() action, String done) async {
    final yes = await showPixelDialog<bool>(
      context,
      title: title,
      message: message,
      icon: PixelIcons.warning,
      actions: const [
        PixelDialogAction('Abbrechen', false),
        PixelDialogAction('Löschen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (yes != true) return;
    await action();
    if (context.mounted) PixelToast.show(context, done, kind: PixelToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final catalog = services.catalog;
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: PixelPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [PixelText.heading(title), const PixelGap(2), ...children],
            ),
          ),
        );
    return PixelScaffold(
      title: 'Einstellungen',
      onBack: () => Navigator.of(context).maybePop(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          section('Darstellung', [
            const PixelText.small('Schrift', color: PixelColors.muted),
            ValueListenableBuilder<AppFont>(
              valueListenable: PixelTheme.font,
              builder: (context, font, _) => PixelChoiceList<AppFont>(
                options: [for (final f in AppFont.values) PixelOption(f, f.label, subtitle: f.description)],
                value: font,
                onChanged: services.appSettings.setFont,
              ),
            ),
            const PixelGap(2),
            const PixelPanel(
              color: PixelColors.background,
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PixelText.heading('Vorschau'),
                  PixelText('Schichthöhe 0,20 mm · Füllung 15 % · 1 h 02 min'),
                  PixelText.small('Il1 O0 rn m · ÄÖÜ äöüß', color: PixelColors.muted),
                ],
              ),
            ),
          ]),
          section('Filament', [
            ValueListenableBuilder<double>(
              valueListenable: services.appSettings.pricePerKg,
              builder: (context, price, _) => PixelStepper(
                label: 'Preis pro Kilogramm',
                value: price,
                min: 5,
                max: 200,
                step: 1,
                format: (v) => '${v.round()} €',
                onChanged: services.appSettings.setPricePerKg,
              ),
            ),
            const PixelGap(1),
            const PixelText.small('Für die geschätzten Materialkosten nach dem Slicen und im Verlauf.', color: PixelColors.muted),
          ]),
          section('Gerät und Engine', [
            PixelText.small(services.device.summary, color: PixelColors.muted),
            PixelText.small(
              services.device.engineInstalled ? 'Slicer-Engine installiert' : (services.slicer.desktop ? 'Slicer-Engine fehlt in dieser Installation!' : 'Slicer-Engine fehlt in dieser APK!'),
              color: services.device.engineInstalled ? PixelColors.green : PixelColors.red,
            ),
            PixelText.small('Profile: ${catalog.printer.name}, ${catalog.processes.length} Schichthöhen, ${catalog.filaments.length} Filamente',
                color: PixelColors.muted),
          ]),
          section('Diagnose', [
            const PixelText.small('Das Log enthält Engine-Ausgaben und Messwerte jedes Vorschau- und Slice-Laufs.',
                color: PixelColors.muted),
            const PixelGap(2),
            PixelButton(
              label: services.slicer.desktop ? 'Diagnose-Log speichern' : 'Diagnose-Log teilen',
              icon: services.slicer.desktop ? PixelIcons.save : PixelIcons.share,
              expand: true,
              onPressed: () => _shareLog(context),
            ),
          ]),
          section('Daten', [
            PixelButton(
              label: 'Verlauf löschen',
              icon: PixelIcons.cross,
              expand: true,
              onPressed: () => _confirm(context, 'Verlauf löschen?', 'Alle Einträge und die Statistik werden gelöscht. Trophäen bleiben.',
                  services.history.clear, 'Verlauf gelöscht'),
            ),
            const PixelGap(2),
            PixelButton(
              label: 'Trophäen zurücksetzen',
              icon: PixelIcons.trophy,
              expand: true,
              onPressed: () => _confirm(context, 'Trophäen zurücksetzen?',
                  'Alle Trophäen werden wieder gesperrt. Was der Verlauf noch hergibt, wird sofort neu verliehen.', () async {
                await services.trophies.reset();
                await services.trophies.check(services.history.records.value);
              }, 'Trophäen zurückgesetzt'),
            ),
          ]),
          section('Lizenzen', [
            const PixelText.small(
              'Die Slicer-Engine basiert auf OrcaSlicer (Snapmaker-Fork) und dem Android-Rezept von OrcaXR, '
              'beide unter der GNU AGPL-3.0. Quellcode: github.com/Snapmaker/OrcaSlicer, github.com/ignacio82/OrcaXR. '
              'Druckerprofile stammen aus den Bambu-Lab-Profilen von OrcaSlicer.',
              color: PixelColors.muted,
            ),
            const PixelGap(2),
            PixelButton(
              label: 'Schrift: Pixelify Sans (OFL)',
              icon: PixelIcons.info,
              expand: true,
              onPressed: () => Navigator.of(context).push(PixelRoute<void>(
                builder: (_) => const _FontLicense(title: 'Pixelify Sans', asset: 'assets/fonts/OFL.txt'),
              )),
            ),
            const PixelGap(2),
            PixelButton(
              label: 'Schrift: Atkinson Hyperlegible (OFL)',
              icon: PixelIcons.info,
              expand: true,
              onPressed: () => Navigator.of(context).push(PixelRoute<void>(
                builder: (_) => const _FontLicense(title: 'Atkinson Hyperlegible', asset: 'assets/fonts/OFL-AtkinsonHyperlegible.txt'),
              )),
            ),
          ]),
        ],
      ),
    );
  }
}

class _FontLicense extends StatelessWidget {
  const _FontLicense({required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) => PixelScaffold(
        title: title,
        onBack: () => Navigator.of(context).maybePop(),
        body: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.all(16),
            children: [PixelText.small(snapshot.data ?? 'Lädt …')],
          ),
        ),
      );
}
