import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mobile_slice/printer/connection.dart';
import 'package:mobile_slice/printer/mqtt_client.dart';

/// In-memory connection; [onWrite] plays the server side.
class FakeConnection implements ByteConnection {
  FakeConnection({this.onWrite});

  final _toClient = StreamController<Uint8List>();
  final written = <int>[];
  void Function(FakeConnection self, List<int> bytes)? onWrite;
  bool closed = false;
  bool destroyed = false;

  @override
  Stream<Uint8List> get input => _toClient.stream;

  void reply(List<int> bytes) {
    if (!_toClient.isClosed) _toClient.add(Uint8List.fromList(bytes));
  }

  void replyText(String text) => reply(latin1.encode(text));

  void hangUp() => _toClient.close();

  @override
  void add(List<int> bytes) {
    written.addAll(bytes);
    onWrite?.call(this, bytes);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    closed = true;
    if (!_toClient.isClosed) await _toClient.close();
  }

  @override
  void destroy() {
    destroyed = true;
    if (!_toClient.isClosed) _toClient.close();
  }
}

/// Fake MQTT broker for one printer: accepts CONNECT with [accessCode], acks subscriptions,
/// records published requests and can push reports.
class FakeBroker {
  FakeBroker({this.accessCode = '12345678', this.serial = '01P00A000000001'});

  final String accessCode;
  final String serial;
  final requests = <Map<String, Object?>>[];
  final connections = <FakeConnection>[];
  FakeConnection? current;
  bool refuse = false;

  /// Answer to a `project_file` start like the real P1S; null = no answer at all.
  String? startResult = 'success';
  String startReason = 'success';

  Future<ByteConnection> connect() async {
    if (refuse) throw const MqttException('nicht erreichbar');
    final reader = MqttPacketReader();
    final connection = FakeConnection(onWrite: (self, bytes) {
      for (final packet in reader.add(bytes)) {
        _handle(self, packet);
      }
    });
    connections.add(connection);
    current = connection;
    return connection;
  }

  void _handle(FakeConnection c, MqttPacket packet) {
    switch (packet.type) {
      case MqttCodec.connect:
        final ok = utf8.decode(packet.body, allowMalformed: true).contains(accessCode);
        scheduleMicrotask(() => c.reply([0x20, 0x02, 0x00, ok ? 0 : 5]));
      case 0x80:
        scheduleMicrotask(() => c.reply([0x90, 0x03, packet.body[0], packet.body[1], 0x00]));
      case MqttCodec.publish:
        final length = (packet.body[0] << 8) | packet.body[1];
        final topic = utf8.decode(packet.body.sublist(2, 2 + length));
        if (topic == 'device/$serial/request') {
          final request = (jsonDecode(utf8.decode(packet.body.sublist(2 + length))) as Map).cast<String, Object?>();
          requests.add(request);
          final print = request['print'];
          final result = startResult;
          if (print is Map && print['command'] == 'project_file' && result != null) {
            scheduleMicrotask(() => report({
                  'print': {
                    'command': 'project_file',
                    'param': print['param'],
                    'sequence_id': print['sequence_id'],
                    'result': result,
                    'reason': startReason,
                  },
                }));
          }
        }
      case MqttCodec.pingreq:
        scheduleMicrotask(() => c.reply([0xD0, 0x00]));
      default:
        break;
    }
  }

  void report(Map<String, Object?> json) =>
      current?.reply(MqttCodec.encodePublish('device/$serial/report', utf8.encode(jsonEncode(json))));
}
