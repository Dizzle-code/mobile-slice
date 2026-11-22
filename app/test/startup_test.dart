import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_slice/main.dart';

// Plain test (no testWidgets): no binding exists yet, exactly like a real app start.
void main() {
  test('App lässt sich ohne vorher initialisiertes Flutter erzeugen', () {
    expect(createApp, returnsNormally);
  });
}
