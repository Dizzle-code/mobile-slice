import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'connection.dart';
import 'ftps_client.dart';
import 'mqtt_client.dart';
import 'printer_config.dart';
import 'printer_status.dart';

enum LinkState { off, connecting, online, error }

class PrinterLink {
  const PrinterLink(this.state, [this.message]);

  final LinkState state;
  final String? message;
}

class PrinterException implements Exception {
  const PrinterException(this.message, {this.details});

  final String message;

  /// Raw printer reply, for the diagnostics log.
  final String? details;

  @override
  String toString() => message;
}

typedef MqttConnector = Future<ByteConnection> Function(PrinterConfig config, CertificatePins pins);
typedef UploaderFactory = FtpsClient Function(PrinterConfig config, CertificatePins pins);

/// Talks to one P1S in LAN mode: live status over MQTT, file upload over FTPS, print commands.
class BambuPrinter {
  BambuPrinter({
    required PrinterConfig config,
    this.onPinsChanged,
    MqttConnector? mqttConnector,
    UploaderFactory? uploader,
    this.reconnectDelays = const [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 30)],
    this.startTimeout = const Duration(seconds: 15),
  })  : _config = config,
        _mqttConnector = mqttConnector ?? _realMqtt,
        _uploader = uploader ?? _realFtps {
    _pins = CertificatePins(config.pins, _pinsChanged);
  }

  static const mqttPort = 8883;
  static const ftpsPort = 990;

  PrinterConfig _config;
  late CertificatePins _pins;
  final void Function(PrinterConfig config)? onPinsChanged;
  final MqttConnector _mqttConnector;
  final UploaderFactory _uploader;
  final List<Duration> reconnectDelays;

  /// How long to wait for the printer to accept a print start.
  final Duration startTimeout;

  static const developerModeHint =
      'Bei aktueller Firmware müssen am Drucker „Nur LAN“ und der Entwicklermodus eingeschaltet sein '
      '(Einstellungen → WLAN).';

  final link = ValueNotifier(const PrinterLink(LinkState.off));
  final status = ValueNotifier(const PrinterStatus());
  final _reports = StreamController<PrinterStatus>.broadcast();
  final _startReplies = StreamController<Map<String, Object?>>.broadcast();

  MqttClient? _mqtt;
  bool _wanted = false;
  int _attempt = 0;
  Timer? _retry;
  int _sequence = 0;

  PrinterConfig get config => _config;

  /// Every merged status, also when nothing visible changed.
  Stream<PrinterStatus> get reports => _reports.stream;

  bool get online => link.value.state == LinkState.online;

  void _pinsChanged(Map<String, String> pins) {
    _config = _config.copyWith(pins: pins);
    onPinsChanged?.call(_config);
  }

  /// Switching printer data drops the connection and the stored certificate when the IP changes.
  Future<void> updateConfig(PrinterConfig config) async {
    await disconnect();
    _config = config;
    _pins = CertificatePins(config.pins, _pinsChanged);
    status.value = const PrinterStatus();
  }

  void forgetCertificate() => _pins.clear();

  Future<void> connect() async {
    _wanted = true;
    _retry?.cancel();
    if (_mqtt?.isConnected == true || link.value.state == LinkState.connecting) return;
    await _open();
  }

  Future<void> _open() async {
    link.value = const PrinterLink(LinkState.connecting);
    final client = MqttClient(
      connector: () => _mqttConnector(_config, _pins),
      clientId: 'mobile-slice-${Random().nextInt(1 << 30)}',
      username: 'bblp',
      password: _config.accessCode,
    );
    try {
      await client.connect();
      client.messages.listen(_onMessage);
      await client.subscribe(_config.reportTopic);
      _mqtt = client;
      _attempt = 0;
      link.value = const PrinterLink(LinkState.online);
      requestFullStatus();
      unawaited(client.done.then((error) => _onClosed(client, error)));
    } catch (e) {
      await client.disconnect();
      link.value = PrinterLink(LinkState.error, describeError(e));
      _scheduleRetry(e);
    }
  }

  void _onClosed(MqttClient client, Object? error) {
    if (_mqtt != client) return;
    _mqtt = null;
    if (!_wanted) {
      link.value = const PrinterLink(LinkState.off);
      return;
    }
    link.value = PrinterLink(LinkState.error, describeError(error ?? 'Verbindung getrennt'));
    _scheduleRetry(error);
  }

  void _scheduleRetry(Object? error) {
    // Wrong credentials or a changed certificate won't fix themselves.
    if (!_wanted || error is CertificateChangedException || (error is MqttException && error.message.contains('Zugangscode'))) return;
    final delay = reconnectDelays[min(_attempt, reconnectDelays.length - 1)];
    _attempt++;
    _retry = Timer(delay, () {
      if (_wanted && _mqtt == null) _open();
    });
  }

  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    final client = _mqtt;
    _mqtt = null;
    await client?.disconnect();
    link.value = const PrinterLink(LinkState.off);
  }

  void _onMessage(MqttMessage message) {
    if (message.topic != _config.reportTopic) return;
    final Object? json;
    try {
      json = jsonDecode(message.text);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    for (final section in json.values) {
      if (section is Map && section['command'] == 'project_file' && section['result'] != null) {
        _startReplies.add(section.cast<String, Object?>());
      }
    }
    final next = status.value.merge(json.cast<String, Object?>());
    status.value = next;
    _reports.add(next);
  }

  void _publish(Map<String, Object?> command) {
    final client = _mqtt;
    if (client == null || !client.isConnected) throw const PrinterException('Drucker ist nicht verbunden');
    client.publish(_config.requestTopic, jsonEncode(command));
  }

  String _seq() => '${_sequence++}';

  void requestFullStatus() => _publish({
        'pushing': {'sequence_id': _seq(), 'command': 'pushall', 'version': 1, 'push_target': 1},
      });

  void pause() => _publish({'print': {'sequence_id': _seq(), 'command': 'pause'}});

  void resume() => _publish({'print': {'sequence_id': _seq(), 'command': 'resume'}});

  void stop() => _publish({'print': {'sequence_id': _seq(), 'command': 'stop'}});

  /// The P1S reads plate files from its SD card root.
  static Map<String, Object?> projectFileCommand(String remoteName, String subtaskName, String sequence) => {
        'print': {
          'sequence_id': sequence,
          'command': 'project_file',
          'param': 'Metadata/plate_1.gcode',
          'url': 'file:///sdcard/$remoteName',
          'subtask_name': subtaskName,
          'md5': '',
          'bed_type': 'auto',
          'timelapse': false,
          'bed_leveling': true,
          'auto_bed_leveling': 1,
          'flow_cali': false,
          'extrude_cali_flag': 0,
          'vibration_cali': true,
          'layer_inspect': false,
          'use_ams': false,
          'ams_mapping': <int>[],
          'profile_id': '0',
          'project_id': '0',
          'subtask_id': '0',
          'task_id': '0',
        },
      };

  /// Uploads [file] and starts it. [onProgress] gets 0..1 for the upload.
  Future<void> sendAndPrint(File file, String remoteName, String subtaskName, {void Function(double progress)? onProgress}) async {
    if (!online) throw const PrinterException('Drucker ist nicht verbunden');
    final current = status.value;
    if (current.state.busy) throw PrinterException('Der Drucker ist beschäftigt (${current.state.label})');
    if (!current.isEmpty && !current.hasSdCard) throw const PrinterException('Keine SD-Karte im Drucker');
    final Uint8List bytes = await file.readAsBytes();
    try {
      await _uploader(_config, _pins).upload(remoteName, bytes, onProgress: (sent, total) => onProgress?.call(total == 0 ? 1 : sent / total));
    } on SocketException catch (e) {
      throw PrinterException('Upload fehlgeschlagen: ${e.message}');
    }
    await _startPrint(remoteName, subtaskName);
  }

  // Waits until the printer accepts the start (reply or print state), so a refusal isn't silent.
  Future<void> _startPrint(String remoteName, String subtaskName) async {
    final sequence = _seq();
    final started = Completer<void>();
    final subscriptions = [
      _startReplies.stream.listen((reply) {
        final id = reply['sequence_id']?.toString();
        if (started.isCompleted || (id != null && id != sequence)) return;
        if (reply['result'].toString().toLowerCase() == 'success') {
          started.complete();
        } else {
          final reason = reply['reason'] ?? reply['err_code'] ?? reply['result'];
          started.completeError(PrinterException(
            'Der Drucker hat den Druckstart abgelehnt ($reason). $developerModeHint',
            details: jsonEncode(reply),
          ));
        }
      }),
      _reports.stream.listen((next) {
        if (!started.isCompleted && next.state.busy) started.complete();
      }),
    ];
    try {
      _publish(projectFileCommand(remoteName, subtaskName, sequence));
      requestFullStatus();
      await started.future.timeout(
        startTimeout,
        onTimeout: () => throw PrinterException(
          'Die Datei ist auf der SD-Karte, aber der Drucker hat auf den Startbefehl nicht reagiert. $developerModeHint',
          details: 'Keine Antwort auf project_file (sequence_id $sequence) nach ${startTimeout.inSeconds} s',
        ),
      );
    } finally {
      for (final s in subscriptions) {
        await s.cancel();
      }
    }
  }

  void dispose() {
    _wanted = false;
    _retry?.cancel();
    _mqtt?.disconnect();
    _reports.close();
    _startReplies.close();
  }

  static Future<ByteConnection> _realMqtt(PrinterConfig config, CertificatePins pins) =>
      connectPinned(config.ip, mqttPort, pins);

  static FtpsClient _realFtps(PrinterConfig config, CertificatePins pins) => FtpsClient(
        controlConnector: () => connectPinned(config.ip, ftpsPort, pins),
        dataConnector: (port) => connectPlain(config.ip, port),
        secureData: (raw) => securePinned(raw, config.ip, pins, '${config.ip}:$ftpsPort'),
        username: 'bblp',
        password: config.accessCode,
      );

  static String describeError(Object? error) => switch (error) {
        null => 'Verbindung getrennt',
        SocketException(:final osError) when osError?.errorCode == 111 || osError?.errorCode == 10061 =>
          'Drucker lehnt ab: LAN-Modus an?',
        SocketException() => 'Drucker nicht erreichbar (IP und WLAN prüfen)',
        TimeoutException() => 'Zeitüberschreitung: Drucker antwortet nicht',
        HandshakeException() => 'TLS-Verbindung fehlgeschlagen',
        _ => error.toString(),
      };
}
