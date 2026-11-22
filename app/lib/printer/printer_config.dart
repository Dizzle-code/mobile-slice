import '../data/json_store.dart';

/// LAN access data of the P1S. Stored only in the app's private folder.
class PrinterConfig {
  const PrinterConfig({required this.ip, required this.serial, required this.accessCode, this.name = 'P1S', this.pins = const {}});

  factory PrinterConfig.fromJson(Map<String, Object?> json) => PrinterConfig(
        ip: json['ip'] as String? ?? '',
        serial: json['serial'] as String? ?? '',
        accessCode: json['accessCode'] as String? ?? '',
        name: json['name'] as String? ?? 'P1S',
        pins: (json['pins'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      );

  final String ip;
  final String serial;
  final String accessCode;
  final String name;

  /// Pinned certificate fingerprints, `host:port` → SHA-256.
  final Map<String, String> pins;

  Map<String, Object?> toJson() => {'ip': ip, 'serial': serial, 'accessCode': accessCode, 'name': name, 'pins': pins};

  PrinterConfig copyWith({String? ip, String? serial, String? accessCode, String? name, Map<String, String>? pins}) {
    final newIp = ip ?? this.ip;
    return PrinterConfig(
      ip: newIp,
      serial: serial ?? this.serial,
      accessCode: accessCode ?? this.accessCode,
      name: name ?? this.name,
      // A different address means a different device: never carry its pins over.
      pins: pins ?? (newIp == this.ip ? this.pins : const {}),
    );
  }

  String get reportTopic => 'device/$serial/report';
  String get requestTopic => 'device/$serial/request';

  static String? validateIp(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null || int.parse(p) < 0 || int.parse(p) > 255 || p.isEmpty)) {
      return 'Bitte eine IPv4-Adresse wie 192.168.1.50 eingeben';
    }
    return null;
  }

  static String? validateSerial(String value) =>
      RegExp(r'^[A-Za-z0-9]{8,20}$').hasMatch(value.trim()) ? null : 'Seriennummer: 8–20 Buchstaben/Ziffern';

  static String? validateAccessCode(String value) =>
      RegExp(r'^\S{4,16}$').hasMatch(value.trim()) ? null : 'Zugangscode vom Druckerdisplay (meist 8 Zeichen)';

  bool get isValid => validateIp(ip) == null && validateSerial(serial) == null && validateAccessCode(accessCode) == null;
}

class PrinterConfigStore {
  PrinterConfigStore(this.store);

  final JsonStore store;
  static const _name = 'printer';

  Future<PrinterConfig?> load() async {
    final json = await store.readMap(_name);
    return json == null ? null : PrinterConfig.fromJson(json);
  }

  Future<void> save(PrinterConfig config) => store.write(_name, config.toJson());

  Future<void> clear() => store.delete(_name);
}
