import 'dart:convert';
import 'dart:io';

/// Small JSON documents in the app's private folder. Writes go to a temp file
/// first and are renamed into place, so a crash never leaves half a file.
class JsonStore {
  JsonStore(this.directory);

  final Directory directory;
  final _queues = <String, Future<void>>{};

  File _file(String name) {
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) throw ArgumentError('Ungültiger Name: $name');
    return File('${directory.path}${Platform.pathSeparator}$name.json');
  }

  /// Null when missing or unreadable (a broken file is kept as `<name>.json.broken`).
  Future<Object?> read(String name) async {
    final file = _file(name);
    await _queues[name];
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      await file.rename('${file.path}.broken');
      return null;
    }
  }

  Future<Map<String, Object?>?> readMap(String name) async {
    final value = await read(name);
    return value is Map ? value.cast<String, Object?>() : null;
  }

  /// Writes are serialized per document; the last write wins.
  Future<void> write(String name, Object? value) {
    final previous = _queues[name] ?? Future<void>.value();
    final next = previous.then((_) => _write(name, value));
    _queues[name] = next.catchError((_) {});
    return next;
  }

  Future<void> _write(String name, Object? value) async {
    final file = _file(name);
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent(' ').convert(value), flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete(String name) async {
    await _queues[name];
    final file = _file(name);
    if (await file.exists()) await file.delete();
  }
}
