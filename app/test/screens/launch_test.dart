import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/app_shell.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/model/stl_reader.dart';
import 'package:mobile_slice/screens/model_screen.dart';

import '../model/model_test.dart' show box;
import '../support/fake_platform.dart';

void main() {
  late FakePlatform platform;
  setUp(() {
    platform = FakePlatform();
    platform.onJob = (job) {
      final stl = File('${job['outputDir']}/preview.stl')..writeAsBytesSync(writeBinaryStl(box(118, 118, 0, 138, 138, 20)));
      return {'ok': true, 'previewPath': stl.path, 'engine': {'fits': true}};
    };
  });
  tearDown(() => platform.dispose());

  int tab(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell)).index;

  test('LaunchRequest aus der Kanal-Nachricht', () {
    expect(LaunchRequest.fromMap({'type': 'action', 'action': 'printer'}).action, 'printer');
    final file = LaunchRequest.fromMap({'type': 'file', 'path': '/m/1_benchy.3mf', 'name': 'benchy.3mf', 'bytes': 12});
    expect(file.model!.name, 'benchy.3mf');
    expect(file.model!.bytes, 12);
    expect(LaunchRequest.fromMap({'type': 'error', 'message': 'kaputt'}).error, 'kaputt');
  });

  testWidgets('Shortcut beim Start und Widget-Tipp im Betrieb wechseln den Tab', (tester) async {
    platform.nextLaunch = {'type': 'action', 'action': 'history'};
    await pumpApp(tester, platform);
    await settle(tester, until: () => tab(tester) == 2);
    expect(find.text('Noch keine Drucke'), findsOneWidget);

    platform.launch({'type': 'action', 'action': 'trophies'});
    await settle(tester, until: () => tab(tester) == 3);
    platform.launch({'type': 'action', 'action': 'home'});
    await settle(tester, until: () => tab(tester) == 0);
  });

  testWidgets('Geteilte Modelldatei öffnet sich direkt, Fehler kommen als Meldung', (tester) async {
    final services = await pumpApp(tester, platform);
    platform.launch({'type': 'action', 'action': 'printer'});
    await settle(tester, until: () => tab(tester) == 1);

    final dir = Directory('${platform.appDir.path}/models')..createSync();
    final file = File('${dir.path}/1_benchy.stl')..writeAsBytesSync(writeBinaryStl(box(0, 0, 0, 5, 5, 5)));
    platform.launch({'type': 'file', 'path': file.path, 'name': 'benchy.stl', 'bytes': 684});
    await settleFinder(tester, find.byType(ModelScreen));
    expect(tab(tester), 0);
    expect(services.recent.models.value.single.name, 'benchy.stl');
    await settle(tester, until: () => platform.jobs.isNotEmpty);
    expect(platform.jobs.last['model'], file.path);

    platform.launch({'type': 'error', 'message': 'Bitte eine .stl- oder .3mf-Datei wählen (gewählt: bild.png)'});
    await settleFinder(tester, find.textContaining('bild.png'));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Shortcut „Modell öffnen“ startet die Dateiauswahl', (tester) async {
    await pumpApp(tester, platform);
    platform.launch({'type': 'action', 'action': 'open_model'});
    await settle(tester, until: () => platform.calls.any((c) => c.method == 'pickModel'));
  });

  testWidgets('MakerWorld-Knopf öffnet die Seite im Browser', (tester) async {
    useLargeScreen(tester);
    await pumpApp(tester, platform);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('MakerWorld öffnen'));
    await tester.pump();
    final call = platform.calls.lastWhere((c) => c.method == 'openUrl');
    expect(call.arguments, {'url': 'https://makerworld.com/de'});
  });

  testWidgets('Widgets bekommen nach dem Start ihre Daten', (tester) async {
    await pumpApp(tester, platform);
    await settle(tester, until: () => platform.calls.any((c) => c.method == 'updateWidgets'));
    final data = platform.calls.lastWhere((c) => c.method == 'updateWidgets').arguments as Map;
    expect(data['p_state'], 'Nicht eingerichtet');
    expect(data['w_trophies'], 'Trophäen 0 / 14');
  });
}
