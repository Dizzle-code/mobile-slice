import 'package:flutter/foundation.dart';

import '../ui/pixel_theme.dart';
import 'json_store.dart';

/// App-wide preferences: the UI font (applied to [PixelTheme] as soon as it loads) and the filament price.
class AppSettings {
  AppSettings(this.store);

  final JsonStore store;
  static const _name = 'app_settings';
  static const defaultPricePerKg = 25.0;

  AppFont get font => PixelTheme.font.value;

  /// Euro per kilogram, used for the material cost estimates.
  final pricePerKg = ValueNotifier<double>(defaultPricePerKg);

  Future<void> load() async {
    final json = await store.readMap(_name);
    final name = json?['font'];
    PixelTheme.font.value = AppFont.values.firstWhere((f) => f.name == name, orElse: () => AppFont.pixelify);
    final price = json?['pricePerKg'];
    pricePerKg.value = price is num && price > 0 && price <= 1000 ? price.toDouble() : defaultPricePerKg;
  }

  Future<void> setFont(AppFont font) async {
    PixelTheme.font.value = font;
    await _save();
  }

  Future<void> setPricePerKg(double price) async {
    pricePerKg.value = price;
    await _save();
  }

  Future<void> _save() => store.write(_name, {'font': font.name, 'pricePerKg': pricePerKg.value});
}

/// Material cost for [grams] at [pricePerKg].
double filamentCost(double grams, double pricePerKg) => grams / 1000 * pricePerKg;
