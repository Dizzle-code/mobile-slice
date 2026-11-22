import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/slicer_channel.dart';
import 'json_store.dart';

/// The last opened models (their copies live in the app's `models` folder).
class RecentModels {
  RecentModels(this.store, {required this.modelsDir, this.limit = 8});

  final JsonStore store;

  /// Only files in here are deleted when they drop off the list.
  final Directory modelsDir;
  final int limit;
  final models = ValueNotifier<List<PickedModel>>(const []);
  static const _name = 'recent';

  Future<void> load() async {
    final json = await store.read(_name);
    if (json is! List) return;
    models.value = List.unmodifiable([
      for (final item in json.whereType<Map>())
        if (item['path'] is String && File(item['path'] as String).existsSync())
          PickedModel(path: item['path'] as String, name: item['name']?.toString() ?? '?', bytes: (item['bytes'] as num?)?.toInt() ?? 0),
    ]);
  }

  Future<void> add(PickedModel model) async {
    final next = [model, ...models.value.where((m) => m.path != model.path)];
    final dropped = next.skip(limit).toList();
    models.value = List.unmodifiable(next.take(limit));
    await store.write(_name, [for (final m in models.value) {'path': m.path, 'name': m.name, 'bytes': m.bytes}]);
    for (final old in dropped) {
      final file = File(old.path);
      if (file.parent.absolute.path == modelsDir.absolute.path && await file.exists()) await file.delete();
    }
  }
}
