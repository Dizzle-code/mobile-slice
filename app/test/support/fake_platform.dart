import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/app_services.dart';
import 'package:mobile_slice/engine/slicer_channel.dart';
import 'package:mobile_slice/main.dart';
import 'package:mobile_slice/ui/pixel_overlay.dart';

const slicerChannel = MethodChannel('mobile_slice/slicer');

/// Stands in for MainActivity/SlicerService: answers channel calls and finishes engine jobs.
class FakePlatform {
  FakePlatform() : appDir = Directory.systemTemp.createTempSync('mobile_slice_test');

  final Directory appDir;
  final calls = <MethodCall>[];
  Map<String, Object?>? nextPick;

  /// What takeLaunch hands out next (shortcut, widget tap, shared file).
  Map<String, Object?>? nextLaunch;

  /// Builds the "finished" payload for a job; may write output files.
  Map<String, Object?> Function(Map<Object?, Object?> job) onJob = (job) => {'ok': false, 'error': 'nicht konfiguriert'};

  /// When false, jobs stay running until [finish] is called.
  bool autoFinish = true;
  Map<Object?, Object?>? runningJob;

  TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() => _messenger.setMockMethodCallHandler(slicerChannel, _handle);

  void dispose() {
    _messenger.setMockMethodCallHandler(slicerChannel, null);
    try {
      appDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; the temp folder is cleaned up later.
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'prepare':
        return {'appDir': appDir.path, 'engineDir': '${appDir.path}/engine', 'engineInstalled': true, 'model': 'Test', 'android': '16', 'cores': 8};
      case 'pickModel':
        return nextPick;
      case 'takeLaunch':
        final launch = nextLaunch;
        nextLaunch = null;
        return launch;
      case 'runJob':
        runningJob = call.arguments as Map<Object?, Object?>;
        if (autoFinish) scheduleMicrotask(finish);
        return true;
      case 'cancelJob':
        final job = runningJob;
        if (job != null) {
          runningJob = null;
          scheduleMicrotask(() => _send('finished', {'jobId': job['jobId'], 'ok': false, 'cancelled': true, 'error': 'Abgebrochen'}));
        }
        return true;
      default:
        return null;
    }
  }

  /// Android received a new intent while the app is running.
  void launch(Map<String, Object?> request) {
    nextLaunch = request;
    _send('launch', null);
  }

  void progress(int percent, String message) {
    final job = runningJob;
    if (job != null) _send('progress', {'jobId': job['jobId'], 'percent': percent, 'message': message});
  }

  void finish() {
    final job = runningJob;
    if (job == null) return;
    runningJob = null;
    _send('finished', {'jobId': job['jobId'], ...onJob(job)});
  }

  void _send(String method, Map<String, Object?>? args) {
    _messenger.handlePlatformMessage(
      slicerChannel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  List<Map<Object?, Object?>> get jobs =>
      [for (final c in calls) if (c.method == 'runJob') c.arguments as Map<Object?, Object?>];
}

/// Big enough that the lazily built screens (preset strip, long settings lists) are fully laid out.
void useLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<AppServices> pumpApp(WidgetTester tester, FakePlatform platform) async {
  platform.install();
  // Cached asset futures from an earlier test's fake-async zone would never complete.
  rootBundle.clear();
  TrophyPopup.reset();
  final services = AppServices(slicer: SlicerChannel());
  await tester.pumpWidget(MobileSliceApp(services: services));
  await settle(tester, until: () => find.byType(Navigator).evaluate().length > 1);
  return services;
}

/// Lets real IO and isolates run between frames until [until] holds.
Future<void> settle(WidgetTester tester, {required bool Function() until, int rounds = 100}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    if (until()) return;
  }
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ');
  fail('Bedingung nicht erreicht. Sichtbar: $texts');
}

Future<void> settleFinder(WidgetTester tester, Finder finder) => settle(tester, until: () => finder.evaluate().isNotEmpty);

