import 'dart:isolate';
import 'dart:convert';
import 'dart:typed_data';

class StlFormatException implements Exception {
  const StlFormatException(this.message);

  final String message;

  @override
  String toString() => 'STL-Fehler: $message';
}

/// Reads binary or ASCII STL into a flat list: 9 floats (3 vertices) per triangle.
Float32List readStl(Uint8List bytes) {
  if (bytes.length >= 84) {
    final data = ByteData.sublistView(bytes);
    final count = data.getUint32(80, Endian.little);
    // A binary file's size is fully determined by its triangle count.
    if (84 + count * 50 == bytes.length) return _readBinary(data, count);
  }
  final head = latin1.decode(bytes.sublist(0, bytes.length < 512 ? bytes.length : 512)).trimLeft().toLowerCase();
  if (head.startsWith('solid')) return _readAscii(latin1.decode(bytes));
  throw const StlFormatException('Datei ist weder binäres noch Text-STL');
}

Float32List _readBinary(ByteData data, int count) {
  final out = Float32List(count * 9);
  var offset = 84;
  for (var t = 0; t < count; t++) {
    final base = offset + 12;
    for (var i = 0; i < 9; i++) {
      out[t * 9 + i] = data.getFloat32(base + i * 4, Endian.little);
    }
    offset += 50;
  }
  _checkFinite(out);
  return out;
}

Float32List _readAscii(String text) {
  final values = <double>[];
  final pattern = RegExp(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', caseSensitive: false);
  for (final match in pattern.allMatches(text)) {
    for (var g = 1; g <= 3; g++) {
      final value = double.tryParse(match.group(g)!);
      if (value == null) throw StlFormatException('Ungültige Zahl "${match.group(g)}"');
      values.add(value);
    }
  }
  if (values.isEmpty) throw const StlFormatException('Keine Dreiecke gefunden');
  if (values.length % 9 != 0) throw const StlFormatException('Unvollständiges Dreieck');
  final out = Float32List.fromList(values);
  _checkFinite(out);
  return out;
}

void _checkFinite(Float32List values) {
  for (final v in values) {
    if (!v.isFinite) throw const StlFormatException('Ungültige Koordinate (NaN/unendlich)');
  }
}

/// Binary STL writer, used by tests and for exporting simple meshes.
Uint8List writeBinaryStl(Float32List triangles) {
  final count = triangles.length ~/ 9;
  final data = ByteData(84 + count * 50);
  data.setUint32(80, count, Endian.little);
  for (var t = 0; t < count; t++) {
    final base = 84 + t * 50 + 12;
    for (var i = 0; i < 9; i++) {
      data.setFloat32(base + i * 4, triangles[t * 9 + i], Endian.little);
    }
  }
  return data.buffer.asUint8List();
}

/// Parses off the UI thread. Top-level so the isolate closure captures only [bytes].
Future<Float32List> readStlInBackground(Uint8List bytes) => Isolate.run(() => readStl(bytes));
