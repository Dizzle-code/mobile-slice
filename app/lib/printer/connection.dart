import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../util/sha256.dart';

/// A byte pipe; real sockets in the app, in-memory pairs in tests.
abstract class ByteConnection {
  Stream<Uint8List> get input;
  void add(List<int> bytes);
  Future<void> flush();
  Future<void> close();
  void destroy();
}

class SocketConnection implements ByteConnection {
  SocketConnection(this.socket) : input = socket.asBroadcastStream();

  final Socket socket;

  @override
  final Stream<Uint8List> input;

  @override
  void add(List<int> bytes) => socket.add(bytes);

  @override
  Future<void> flush() => socket.flush();

  @override
  Future<void> close() async {
    await socket.flush().catchError((_) {});
    await socket.close().catchError((_) => socket);
  }

  @override
  void destroy() => socket.destroy();
}

class CertificateChangedException implements Exception {
  const CertificateChangedException(this.host);

  final String host;

  @override
  String toString() =>
      'Das Zertifikat des Druckers ($host) hat sich geändert. Wenn du den Drucker zurückgesetzt hast, '
      'setze in den Einstellungen das gespeicherte Zertifikat zurück.';
}

/// Trust on first use: the first certificate seen for `host:port` is remembered,
/// afterwards only that exact certificate is accepted.
class CertificatePins {
  CertificatePins([Map<String, String>? pins, this.onChanged]) : _pins = {...?pins};

  final Map<String, String> _pins;
  final void Function(Map<String, String> pins)? onChanged;

  Map<String, String> get pins => Map.unmodifiable(_pins);

  static String fingerprint(X509Certificate cert) => hex(sha256(cert.der));

  /// Whether [fingerprint] may be used for [key]; records it when no pin exists yet.
  bool check(String key, String fingerprint) {
    final pinned = _pins[key];
    if (pinned == null) {
      _pins[key] = fingerprint;
      onChanged?.call(pins);
      return true;
    }
    return pinned == fingerprint;
  }

  bool accepts(String key, String fingerprint) {
    final pinned = _pins[key];
    return pinned == null || pinned == fingerprint;
  }

  void clear() {
    _pins.clear();
    onChanged?.call(pins);
  }
}

/// Opens a TLS connection that is trusted only through [pins] (the printer's certificate is self-signed).
Future<ByteConnection> connectPinned(String host, int port, CertificatePins pins,
    {String? pinKey, Duration timeout = const Duration(seconds: 8)}) async {
  // FTPS data channels use random ports but the control channel's certificate.
  final key = pinKey ?? '$host:$port';
  final socket = await SecureSocket.connect(
    host,
    port,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (cert) => pins.accepts(key, CertificatePins.fingerprint(cert)),
    timeout: timeout,
  );
  final cert = socket.peerCertificate;
  if (cert == null || !pins.check(key, CertificatePins.fingerprint(cert))) {
    socket.destroy();
    throw CertificateChangedException(host);
  }
  return SocketConnection(socket);
}

Future<ByteConnection> connectPlain(String host, int port, {Duration timeout = const Duration(seconds: 8)}) async =>
    SocketConnection(await Socket.connect(host, port, timeout: timeout));

/// Upgrades an open plain connection to TLS, checked against the pin stored under [pinKey].
Future<ByteConnection> securePinned(ByteConnection raw, String host, CertificatePins pins, String pinKey) async {
  if (raw is! SocketConnection) throw ArgumentError('Nur echte Sockets können verschlüsselt werden');
  final socket = await SecureSocket.secure(
    raw.socket,
    host: host,
    context: SecurityContext(withTrustedRoots: false),
    onBadCertificate: (cert) => pins.accepts(pinKey, CertificatePins.fingerprint(cert)),
  );
  final cert = socket.peerCertificate;
  if (cert == null || !pins.check(pinKey, CertificatePins.fingerprint(cert))) {
    socket.destroy();
    throw CertificateChangedException(host);
  }
  return SocketConnection(socket);
}
