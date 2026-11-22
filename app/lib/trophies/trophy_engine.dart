import 'package:flutter/foundation.dart';

import '../data/json_store.dart';
import '../data/print_history.dart';
import 'trophy_catalog.dart';

/// Keeps which trophies are earned (and when) and finds new ones after each history change.
class TrophyEngine {
  TrophyEngine(this.store, {List<Trophy>? catalog}) : catalog = catalog ?? trophyCatalog;

  final JsonStore store;
  final List<Trophy> catalog;
  static const _name = 'trophies';

  /// Trophy id → unlock time.
  final unlocked = ValueNotifier<Map<String, DateTime>>(const {});

  Future<void> load() async {
    final json = await store.readMap(_name);
    if (json == null) return;
    final map = <String, DateTime>{};
    json.forEach((id, value) {
      final time = DateTime.tryParse(value?.toString() ?? '');
      if (time != null) map[id] = time;
    });
    unlocked.value = Map.unmodifiable(map);
  }

  /// Returns trophies unlocked by this check, in catalog order. Earned trophies stay earned.
  Future<List<Trophy>> check(List<PrintRecord> records, {DateTime? now}) async {
    final context = TrophyContext(records);
    final fresh = [
      for (final trophy in catalog)
        if (!unlocked.value.containsKey(trophy.id) && trophy.progress(context).done) trophy,
    ];
    if (fresh.isEmpty) return const [];
    final time = now ?? DateTime.now();
    unlocked.value = Map.unmodifiable({...unlocked.value, for (final t in fresh) t.id: time});
    await store.write(_name, unlocked.value.map((id, t) => MapEntry(id, t.toIso8601String())));
    return fresh;
  }

  Future<void> reset() async {
    unlocked.value = const {};
    await store.delete(_name);
  }
}
