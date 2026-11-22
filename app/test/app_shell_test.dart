import 'package:flutter_test/flutter_test.dart';

import 'support/fake_platform.dart';

void main() {
  testWidgets('Tab-Leiste wechselt zwischen den vier Bereichen', (tester) async {
    final platform = FakePlatform();
    addTearDown(platform.dispose);
    await pumpApp(tester, platform);
    expect(find.text('Werkstatt'), findsWidgets);
    for (final tab in ['Drucker', 'Verlauf', 'Trophäen']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(tab), findsWidgets, reason: tab);
    }
  });
}
