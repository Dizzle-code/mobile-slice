import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'connection.dart';

class FtpException implements Exception {
  const FtpException(this.message, [this.code]);

  final String message;
  final int? code;

  @override
  String toString() => message;
}

class FtpReply {
  const FtpReply(this.code, this.text);

  final int code;
  final String text;

  bool get ok => code >= 100 && code < 400;
}

/// Reads complete FTP replies (including multi-line "123-" blocks) from a byte stream.
class FtpReplyReader {
  FtpReplyReader(Stream<Uint8List> input) {
    _sub = input.listen(_onData, onError: _onError, onDone: () => _onError(const FtpException('Verbindung zum Drucker getrennt')));
  }

  late final StreamSubscription<Uint8List> _sub;
  final _text = StringBuffer();
  final _lines = <String>[];
  final _replies = <FtpReply>[];
  final _waiting = <Completer<FtpReply>>[];
  Object? _error;
  String? _multiCode;
  final _multiText = <String>[];

  void _onData(Uint8List chunk) {
    _text.write(latin1.decode(chunk));
    var all = _text.toString();
    var newline = all.indexOf('\n');
    while (newline >= 0) {
      _lines.add(all.substring(0, newline).replaceAll('\r', ''));
      all = all.substring(newline + 1);
      newline = all.indexOf('\n');
    }
    _text
      ..clear()
      ..write(all);
    for (final line in _lines) {
      _parse(line);
    }
    _lines.clear();
  }

  void _parse(String line) {
    final code = line.length >= 3 ? line.substring(0, 3) : '';
    final isCode = int.tryParse(code) != null;
    if (_multiCode != null) {
      _multiText.add(line);
      if (line.startsWith('$_multiCode ')) {
        _emit(FtpReply(int.parse(_multiCode!), _multiText.join('\n')));
        _multiCode = null;
        _multiText.clear();
      }
      return;
    }
    if (!isCode) return;
    if (line.length > 3 && line[3] == '-') {
      _multiCode = code;
      _multiText
        ..clear()
        ..add(line);
      return;
    }
    _emit(FtpReply(int.parse(code), line.length > 4 ? line.substring(4) : ''));
  }

  void _emit(FtpReply reply) {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(reply);
    } else {
      _replies.add(reply);
    }
  }

  void _onError(Object error) {
    _error ??= error;
    for (final w in _waiting) {
      w.completeError(error);
    }
    _waiting.clear();
  }

  Future<FtpReply> next({Duration timeout = const Duration(seconds: 15)}) {
    if (_replies.isNotEmpty) return Future.value(_replies.removeAt(0));
    final error = _error;
    if (error != null) return Future.error(error);
    final completer = Completer<FtpReply>();
    _waiting.add(completer);
    return completer.future.timeout(timeout, onTimeout: () {
      _waiting.remove(completer);
      throw const FtpException('Drucker antwortet nicht (FTP)');
    });
  }

  Future<void> cancel() => _sub.cancel();
}

/// Upload over implicit FTPS (TLS from the first byte, port 990), as the Bambu printers expect.
class FtpsClient {
  FtpsClient({
    required this.controlConnector,
    required this.dataConnector,
    required this.secureData,
    required this.username,
    required this.password,
  });

  final Future<ByteConnection> Function() controlConnector;

  /// Opens the plain TCP data connection to the passive port.
  final Future<ByteConnection> Function(int port) dataConnector;

  /// Starts TLS on an open data connection (after the server answered STOR).
  final Future<ByteConnection> Function(ByteConnection raw) secureData;
  final String username;
  final String password;

  /// Uploads [data] as [remoteName] into the SD card root. [onProgress] gets bytes sent so far.
  Future<void> upload(String remoteName, Uint8List data, {void Function(int sent, int total)? onProgress}) async {
    if (remoteName.contains('/') || remoteName.contains('\n') || remoteName.contains('\r')) {
      throw const FtpException('Ungültiger Dateiname');
    }
    final control = await controlConnector();
    final replies = FtpReplyReader(control.input);
    Future<FtpReply> command(String line, Set<int> expected, String failure) async {
      control.add(latin1.encode('$line\r\n'));
      final reply = await replies.next();
      if (!expected.contains(reply.code)) throw FtpException('$failure (${reply.code} ${reply.text})', reply.code);
      return reply;
    }

    try {
      final hello = await replies.next();
      if (hello.code != 220) throw FtpException('Unerwartete Begrüßung (${hello.code})', hello.code);
      final user = await command('USER $username', {230, 331}, 'Benutzer abgelehnt');
      if (user.code == 331) {
        final pass = await _sendPassword(control, replies);
        if (pass.code != 230) throw FtpException('Zugangscode falsch (${pass.code})', pass.code);
      }
      await command('TYPE I', {200}, 'Binärmodus abgelehnt');
      await command('PBSZ 0', {200}, 'PBSZ abgelehnt');
      var tls = true;
      await command('PROT P', {200}, 'Verschlüsselter Datenkanal abgelehnt');
      try {
        await _store(command, replies, remoteName, data, tls, onProgress);
      } on FtpException catch (e) {
        // 522: the server wants TLS session reuse on the data channel, which dart:io cannot offer.
        if (e.code != 522) rethrow;
        tls = false;
        await command('PROT C', {200}, 'Unverschlüsselter Datenkanal abgelehnt');
        await _store(command, replies, remoteName, data, tls, onProgress);
      }
      control.add(latin1.encode('QUIT\r\n'));
      await replies.next(timeout: const Duration(seconds: 3)).catchError((_) => const FtpReply(221, ''));
    } finally {
      await replies.cancel();
      control.destroy();
    }
  }

  Future<FtpReply> _sendPassword(ByteConnection control, FtpReplyReader replies) {
    control.add(latin1.encode('PASS $password\r\n'));
    return replies.next();
  }

  Future<void> _store(
    Future<FtpReply> Function(String, Set<int>, String) command,
    FtpReplyReader replies,
    String remoteName,
    Uint8List data,
    bool tls,
    void Function(int sent, int total)? onProgress,
  ) async {
    final pasv = await command('PASV', {227}, 'Passiver Modus abgelehnt');
    final port = parsePasvPort(pasv.text);
    var dataConnection = await dataConnector(port);
    var dataOpen = true;
    try {
      await command('STOR $remoteName', {125, 150}, 'Upload abgelehnt');
      if (tls) {
        try {
          dataConnection = await secureData(dataConnection);
        } catch (_) {
          // The server explains a failed data handshake in its next reply (522 = session reuse required).
          final reply = await replies.next(timeout: const Duration(seconds: 5)).catchError((_) => const FtpReply(0, ''));
          throw FtpException('Datenkanal-Verschlüsselung fehlgeschlagen (${reply.code} ${reply.text})', reply.code == 522 ? 522 : null);
        }
      }
      const chunk = 64 * 1024;
      for (var offset = 0; offset < data.length; offset += chunk) {
        final end = offset + chunk < data.length ? offset + chunk : data.length;
        dataConnection.add(Uint8List.sublistView(data, offset, end));
        await dataConnection.flush();
        onProgress?.call(end, data.length);
      }
      await dataConnection.close();
      dataOpen = false;
      final done = await replies.next(timeout: const Duration(seconds: 60));
      if (done.code != 226 && done.code != 250) throw FtpException('Upload nicht bestätigt (${done.code} ${done.text})', done.code);
    } finally {
      if (dataOpen) dataConnection.destroy();
    }
  }

  /// Port from "Entering Passive Mode (h1,h2,h3,h4,p1,p2)". The address is ignored:
  /// the data connection always goes to the printer's own IP.
  static int parsePasvPort(String text) {
    final match = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(text);
    if (match == null) throw FtpException('PASV-Antwort unverständlich: $text');
    final port = int.parse(match.group(5)!) * 256 + int.parse(match.group(6)!);
    if (port <= 0 || port > 65535) throw FtpException('Ungültiger Datenport: $port');
    return port;
  }
}
