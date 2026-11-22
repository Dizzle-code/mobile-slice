import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'connection.dart';

class MqttException implements Exception {
  const MqttException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MqttMessage {
  const MqttMessage(this.topic, this.payload);

  final String topic;
  final Uint8List payload;

  String get text => utf8.decode(payload, allowMalformed: true);
}

/// Packet encoding for the MQTT 3.1.1 subset the printer needs (QoS 0 only).
abstract final class MqttCodec {
  static const connect = 0x10, connack = 0x20, publish = 0x30, subscribe = 0x82, suback = 0x90;
  static const pingreq = 0xC0, pingresp = 0xD0, disconnect = 0xE0;

  static Uint8List remainingLength(int length) {
    if (length < 0 || length > 268435455) throw ArgumentError('Paket zu groß');
    final out = <int>[];
    do {
      var byte = length % 128;
      length ~/= 128;
      if (length > 0) byte |= 0x80;
      out.add(byte);
    } while (length > 0);
    return Uint8List.fromList(out);
  }

  static List<int> _string(String value) {
    final bytes = utf8.encode(value);
    return [bytes.length >> 8, bytes.length & 0xFF, ...bytes];
  }

  static Uint8List _packet(int header, List<int> body) =>
      Uint8List.fromList([header, ...remainingLength(body.length), ...body]);

  static Uint8List encodeConnect({required String clientId, String? username, String? password, int keepAliveSeconds = 60}) {
    var flags = 0x02;
    if (username != null) flags |= 0x80;
    if (password != null) flags |= 0x40;
    return _packet(connect, [
      ..._string('MQTT'),
      0x04,
      flags,
      keepAliveSeconds >> 8,
      keepAliveSeconds & 0xFF,
      ..._string(clientId),
      if (username != null) ..._string(username),
      if (password != null) ..._string(password),
    ]);
  }

  static Uint8List encodeSubscribe(int packetId, String topic) =>
      _packet(subscribe, [packetId >> 8, packetId & 0xFF, ..._string(topic), 0x00]);

  static Uint8List encodePublish(String topic, List<int> payload) => _packet(publish, [..._string(topic), ...payload]);

  static final Uint8List ping = Uint8List.fromList([pingreq, 0]);
  static final Uint8List bye = Uint8List.fromList([disconnect, 0]);
}

/// One parsed packet: first header byte and body.
class MqttPacket {
  const MqttPacket(this.header, this.body);

  final int header;
  final Uint8List body;

  int get type => header & 0xF0;
}

/// Splits a byte stream into MQTT packets, however the bytes are chunked.
class MqttPacketReader {
  final _buffer = BytesBuilder(copy: true);
  Uint8List _pending = Uint8List(0);

  List<MqttPacket> add(List<int> chunk) {
    _buffer.add(_pending);
    _buffer.add(chunk);
    var data = _buffer.takeBytes();
    final packets = <MqttPacket>[];
    var offset = 0;
    while (true) {
      if (data.length - offset < 2) break;
      var multiplier = 1, length = 0, index = offset + 1;
      var complete = false;
      while (index < data.length) {
        final byte = data[index++];
        length += (byte & 0x7F) * multiplier;
        if (byte & 0x80 == 0) {
          complete = true;
          break;
        }
        multiplier *= 128;
        if (multiplier > 128 * 128 * 128) throw const MqttException('Ungültige Paketlänge');
      }
      if (!complete || data.length - index < length) break;
      packets.add(MqttPacket(data[offset], Uint8List.sublistView(data, index, index + length)));
      offset = index + length;
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(data, offset));
    data = Uint8List(0);
    return packets;
  }
}

/// Minimal MQTT 3.1.1 client over any [ByteConnection].
class MqttClient {
  MqttClient({
    required this.connector,
    required this.clientId,
    this.username,
    this.password,
    this.keepAlive = const Duration(seconds: 30),
  });

  final Future<ByteConnection> Function() connector;
  final String clientId;
  final String? username;
  final String? password;
  final Duration keepAlive;

  ByteConnection? _connection;
  StreamSubscription<Uint8List>? _sub;
  final _reader = MqttPacketReader();
  final _messages = StreamController<MqttMessage>.broadcast();
  final _done = Completer<Object?>();
  Completer<void>? _connack;
  final _subacks = <int, Completer<void>>{};
  int _packetId = 0;
  Timer? _pingTimer;
  DateTime _lastSeen = DateTime.now();

  Stream<MqttMessage> get messages => _messages.stream;

  /// Completes when the connection ends: null after [disconnect], otherwise the error.
  Future<Object?> get done => _done.future;

  bool get isConnected => _connection != null && !_done.isCompleted;

  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    final connection = await connector();
    _connection = connection;
    _sub = connection.input.listen(_onData, onError: (Object e) => _close(e), onDone: () => _close(const MqttException('Verbindung vom Drucker getrennt')));
    _connack = Completer<void>();
    connection.add(MqttCodec.encodeConnect(
      clientId: clientId,
      username: username,
      password: password,
      keepAliveSeconds: keepAlive.inSeconds,
    ));
    try {
      await _connack!.future.timeout(timeout, onTimeout: () => throw const MqttException('Drucker antwortet nicht (MQTT)'));
    } catch (e) {
      _close(e);
      rethrow;
    }
    _lastSeen = DateTime.now();
    _pingTimer = Timer.periodic(keepAlive, (_) => _ping());
  }

  Future<void> subscribe(String topic, {Duration timeout = const Duration(seconds: 10)}) {
    final id = _nextId();
    final completer = Completer<void>();
    _subacks[id] = completer;
    _send(MqttCodec.encodeSubscribe(id, topic));
    return completer.future.timeout(timeout, onTimeout: () => throw const MqttException('Abo wurde nicht bestätigt'));
  }

  void publish(String topic, String payload) => _send(MqttCodec.encodePublish(topic, utf8.encode(payload)));

  Future<void> disconnect() async {
    final connection = _connection;
    if (connection != null && !_done.isCompleted) {
      connection.add(MqttCodec.bye);
      await connection.flush().catchError((_) {});
    }
    _close(null);
  }

  int _nextId() => _packetId = _packetId % 65535 + 1;

  void _send(Uint8List packet) {
    final connection = _connection;
    if (connection == null || _done.isCompleted) throw const MqttException('Nicht verbunden');
    connection.add(packet);
  }

  void _ping() {
    if (DateTime.now().difference(_lastSeen) > keepAlive * 2) {
      _close(const MqttException('Keine Antwort vom Drucker (Zeitüberschreitung)'));
      return;
    }
    try {
      _send(MqttCodec.ping);
    } on MqttException catch (e) {
      _close(e);
    }
  }

  void _onData(Uint8List chunk) {
    _lastSeen = DateTime.now();
    final List<MqttPacket> packets;
    try {
      packets = _reader.add(chunk);
    } on MqttException catch (e) {
      _close(e);
      return;
    }
    for (final packet in packets) {
      switch (packet.type) {
        case MqttCodec.connack:
          final code = packet.body.length >= 2 ? packet.body[1] : 255;
          if (code == 0) {
            _connack?.complete();
          } else {
            _connack?.completeError(MqttException(switch (code) {
              4 || 5 => 'Zugangscode falsch oder LAN-Modus aus',
              2 => 'Client-ID abgelehnt',
              3 => 'MQTT-Dienst nicht verfügbar',
              _ => 'Verbindung abgelehnt (Code $code)',
            }));
          }
        case MqttCodec.suback:
          if (packet.body.length >= 3) {
            final id = (packet.body[0] << 8) | packet.body[1];
            final completer = _subacks.remove(id);
            if (packet.body[2] == 0x80) {
              completer?.completeError(const MqttException('Abo abgelehnt (Seriennummer prüfen)'));
            } else {
              completer?.complete();
            }
          }
        case MqttCodec.publish:
          _onPublish(packet);
        default:
          break;
      }
    }
  }

  void _onPublish(MqttPacket packet) {
    final body = packet.body;
    if (body.length < 2) return;
    final topicLength = (body[0] << 8) | body[1];
    if (body.length < 2 + topicLength) return;
    final topic = utf8.decode(body.sublist(2, 2 + topicLength), allowMalformed: true);
    final qos = (packet.header >> 1) & 0x03;
    // QoS 1/2 messages carry a packet id before the payload.
    final start = 2 + topicLength + (qos > 0 ? 2 : 0);
    if (start > body.length) return;
    _messages.add(MqttMessage(topic, Uint8List.sublistView(body, start)));
  }

  void _close(Object? error) {
    if (_done.isCompleted) return;
    _pingTimer?.cancel();
    _sub?.cancel();
    final connection = _connection;
    _connection = null;
    connection?.destroy();
    if (_connack != null && !_connack!.isCompleted) _connack!.completeError(error ?? const MqttException('Getrennt'));
    for (final c in _subacks.values) {
      if (!c.isCompleted) c.completeError(error ?? const MqttException('Getrennt'));
    }
    _subacks.clear();
    _done.complete(error);
    _messages.close();
  }
}
