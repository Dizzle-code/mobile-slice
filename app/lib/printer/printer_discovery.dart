import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredPrinter {
  const DiscoveredPrinter({required this.ip, required this.serial, required this.model, required this.name, required this.lanMode});

  final String ip;
  final String serial;

  /// Bambu model code, e.g. C12 for the P1S.
  final String model;
  final String name;

  /// True when the printer reports LAN-only mode.
  final bool lanMode;

  String get modelName => switch (model) {
        'C12' => 'P1S',
        'C11' => 'P1P',
        'BL-P001' || '3DPrinter-X1-Carbon' => 'X1 Carbon',
        'N2S' => 'A1',
        'N1' => 'A1 mini',
        _ => model.isEmpty ? 'Bambu-Drucker' : model,
      };
}

/// Parses a Bambu SSDP NOTIFY / M-SEARCH answer; null for anything else.
DiscoveredPrinter? parseSsdp(String message, {String? senderIp}) {
  final headers = <String, String>{};
  for (final line in const LineSplitter().convert(message)) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    headers[line.substring(0, colon).trim().toLowerCase()] = line.substring(colon + 1).trim();
  }
  final type = headers['nt'] ?? headers['st'] ?? '';
  if (!type.contains('bambulab-com:device:3dprinter')) return null;
  final serial = headers['usn'] ?? '';
  final location = headers['location'] ?? senderIp ?? '';
  final ip = location.replaceFirst(RegExp(r'^\w+://'), '').split(RegExp(r'[:/]')).first;
  if (serial.isEmpty || InternetAddress.tryParse(ip) == null) return null;
  return DiscoveredPrinter(
    ip: ip,
    serial: serial,
    model: headers['devmodel.bambu.com'] ?? '',
    name: headers['devname.bambu.com'] ?? '',
    lanMode: (headers['devconnect.bambu.com'] ?? '').toLowerCase() == 'lan',
  );
}

/// Listens for printer announcements on UDP 2021 (and asks for them once).
/// Some routers block these broadcasts; manual entry always works as well.
class PrinterDiscovery {
  static const port = 2021;
  static const _search = 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: 239.255.255.250:1990\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: 3\r\n'
      'ST: urn:bambulab-com:device:3dprinter:1\r\n\r\n';

  Stream<DiscoveredPrinter> search({Duration duration = const Duration(seconds: 8)}) async* {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
    socket.broadcastEnabled = true;
    try {
      socket.joinMulticast(InternetAddress('239.255.255.250'));
    } on SocketException {
      // Broadcasts alone are enough on most networks.
    }
    final found = <String>{};
    final controller = StreamController<DiscoveredPrinter>();
    final timer = Timer(duration, controller.close);
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final printer = parseSsdp(latin1.decode(datagram.data, allowInvalid: true), senderIp: datagram.address.address);
      if (printer != null && found.add(printer.serial) && !controller.isClosed) controller.add(printer);
    });
    final request = latin1.encode(_search);
    socket.send(request, InternetAddress('255.255.255.255'), port);
    socket.send(request, InternetAddress('239.255.255.250'), 1990);
    try {
      yield* controller.stream;
    } finally {
      timer.cancel();
      socket.close();
    }
  }
}
