import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../printer/bambu_printer.dart';
import '../printer/printer_config.dart';
import '../printer/printer_discovery.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_progress.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_text_field.dart';
import '../ui/pixel_theme.dart';

/// Enter or find the P1S; checks the connection before saving.
class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key, this.discovery});

  /// Replaced in tests.
  final Stream<DiscoveredPrinter> Function()? discovery;

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  late final AppServices _services = AppScope.of(context);
  final _ip = TextEditingController();
  final _serial = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _ipError, _serialError, _codeError;
  bool _searching = false;
  bool _testing = false;
  String? _testError;
  final _found = <DiscoveredPrinter>[];
  StreamSubscription<DiscoveredPrinter>? _search;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final config = _services.printer.value?.config;
    if (config != null) {
      _ip.text = config.ip;
      _serial.text = config.serial;
      _code.text = config.accessCode;
      _name.text = config.name;
    }
  }

  @override
  void dispose() {
    _stopSearch();
    for (final c in [_ip, _serial, _code, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _stopSearch() {
    _search?.cancel();
    _search = null;
    if (_searching) _services.slicer.setMulticast(false).catchError((_) {});
    _searching = false;
  }

  Future<void> _startSearch() async {
    setState(() {
      _found.clear();
      _searching = true;
    });
    try {
      await _services.slicer.setMulticast(true);
    } on PlatformException {
      // Without the lock, broadcasts usually still arrive.
    }
    final stream = widget.discovery?.call() ?? PrinterDiscovery().search();
    _search = stream.listen(
      (printer) => setState(() => _found.add(printer)),
      onError: (Object e) {
        if (!mounted) return;
        PixelToast.show(context, 'Suche fehlgeschlagen: $e', kind: PixelToastKind.error);
        setState(_stopSearch);
      },
      onDone: () {
        if (!mounted) return;
        setState(_stopSearch);
        if (_found.isEmpty) PixelToast.show(context, 'Kein Drucker gefunden. Bitte IP und Seriennummer eintippen.');
      },
    );
  }

  void _use(DiscoveredPrinter printer) {
    setState(() {
      _ip.text = printer.ip;
      _serial.text = printer.serial;
      if (_name.text.isEmpty && printer.name.isNotEmpty) _name.text = printer.name;
    });
    if (!printer.lanMode) {
      PixelToast.show(context, 'Achtung: Der Drucker meldet keinen LAN-Only-Modus.', kind: PixelToastKind.error);
    }
  }

  Future<void> _save() async {
    setState(() {
      _ipError = PrinterConfig.validateIp(_ip.text);
      _serialError = PrinterConfig.validateSerial(_serial.text);
      _codeError = PrinterConfig.validateAccessCode(_code.text);
      _testError = null;
    });
    if (_ipError != null || _serialError != null || _codeError != null) return;
    final previous = _services.printer.value?.config;
    final ip = _ip.text.trim();
    var config = PrinterConfig(
      ip: ip,
      serial: _serial.text.trim().toUpperCase(),
      accessCode: _code.text.trim(),
      name: _name.text.trim().isEmpty ? 'P1S' : _name.text.trim(),
      // Keep the pinned certificate only for the same address.
      pins: previous != null && previous.ip == ip ? previous.pins : const {},
    );
    setState(() => _testing = true);
    final probe = _services.makePrinter(config, (c) => config = c);
    try {
      await _services.printer.value?.disconnect();
      await probe.connect();
      final link = probe.link.value;
      if (link.state != LinkState.online) throw PrinterException(link.message ?? 'Verbindung fehlgeschlagen');
      await probe.disconnect();
      await _services.setPrinter(config);
      if (!mounted) return;
      PixelToast.show(context, 'Drucker verbunden und gespeichert', kind: PixelToastKind.success);
      Navigator.of(context).pop();
    } catch (e) {
      await probe.disconnect();
      unawaited(_services.printer.value?.connect());
      if (mounted) setState(() => _testError = e.toString());
    } finally {
      probe.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _remove() async {
    final yes = await showPixelDialog<bool>(
      context,
      title: 'Drucker entfernen?',
      message: 'IP, Seriennummer, Zugangscode und das gemerkte Zertifikat werden gelöscht.',
      actions: const [
        PixelDialogAction('Abbrechen', false),
        PixelDialogAction('Entfernen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (yes != true) return;
    await _services.setPrinter(null);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _forgetCertificate() async {
    final printer = _services.printer.value;
    if (printer == null) return;
    final yes = await showPixelDialog<bool>(
      context,
      title: 'Zertifikat zurücksetzen?',
      message: 'Nur nötig, wenn der Drucker zurückgesetzt oder getauscht wurde. Beim nächsten Verbinden wird das '
          'dann gezeigte Zertifikat neu gemerkt.',
      actions: const [
        PixelDialogAction('Abbrechen', false),
        PixelDialogAction('Zurücksetzen', true, style: PixelButtonStyle.danger),
      ],
    );
    if (yes != true) return;
    printer.forgetCertificate();
    await printer.disconnect();
    unawaited(printer.connect());
    if (mounted) PixelToast.show(context, 'Zertifikat vergessen');
  }

  @override
  Widget build(BuildContext context) {
    final configured = _services.printer.value != null;
    return PixelScaffold(
      title: 'Drucker einrichten',
      onBack: () => Navigator.of(context).maybePop(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Requirements(),
          const PixelGap(4),
          PixelButton(
            label: _searching ? 'Suche läuft …' : 'Drucker im WLAN suchen',
            icon: PixelIcons.wifi,
            expand: true,
            onPressed: _searching || _testing ? null : _startSearch,
          ),
          if (_searching) ...[
            const PixelGap(2),
            const PixelProgressBar(value: null, height: 16, semanticLabel: 'Suche'),
          ],
          for (final printer in _found) ...[
            const PixelGap(2),
            PixelButton(
              label: '${printer.name.isEmpty ? printer.modelName : printer.name} · ${printer.ip}',
              icon: PixelIcons.printer,
              expand: true,
              onPressed: () => _use(printer),
            ),
          ],
          const PixelGap(4),
          PixelPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PixelTextField(
                  controller: _ip,
                  label: 'IP-Adresse',
                  hint: '192.168.1.50',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  textInputAction: TextInputAction.next,
                  errorText: _ipError,
                ),
                const PixelGap(3),
                PixelTextField(
                  controller: _serial,
                  label: 'Seriennummer',
                  hint: '01P00A…',
                  textInputAction: TextInputAction.next,
                  errorText: _serialError,
                ),
                const PixelGap(3),
                PixelTextField(
                  controller: _code,
                  label: 'Zugangscode (Display: Einstellungen › WLAN)',
                  hint: '8 Zeichen',
                  obscure: true,
                  textInputAction: TextInputAction.next,
                  errorText: _codeError,
                ),
                const PixelGap(3),
                PixelTextField(controller: _name, label: 'Name (optional)', hint: 'P1S', onSubmitted: (_) => _save()),
              ],
            ),
          ),
          if (_testError != null) ...[
            const PixelGap(3),
            PixelPanel(borderColor: PixelColors.red, child: PixelText(_testError!, color: PixelColors.red)),
          ],
          const PixelGap(4),
          if (_testing) ...[
            const PixelText('Verbinde mit dem Drucker …', color: PixelColors.yellow),
            const PixelGap(2),
            const PixelProgressBar(value: null, semanticLabel: 'Verbindungstest'),
          ] else
            PixelButton(
              label: 'Verbinden und speichern',
              icon: PixelIcons.check,
              style: PixelButtonStyle.primary,
              expand: true,
              onPressed: _save,
            ),
          if (configured && !_testing) ...[
            const PixelGap(4),
            PixelButton(label: 'Zertifikat zurücksetzen', icon: PixelIcons.lock, expand: true, onPressed: _forgetCertificate),
            const PixelGap(2),
            PixelButton(
              label: 'Drucker entfernen',
              icon: PixelIcons.cross,
              style: PixelButtonStyle.danger,
              expand: true,
              onPressed: _remove,
            ),
          ],
        ],
      ),
    );
  }
}

class _Requirements extends StatelessWidget {
  const _Requirements();

  @override
  Widget build(BuildContext context) {
    Widget item(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PixelText('▪ ', color: PixelColors.accent),
              Expanded(child: PixelText.small(text)),
            ],
          ),
        );
    return PixelPanel(
      borderColor: PixelColors.yellow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PixelIcon(PixelIcons.info, scale: 1, secondColor: PixelColors.yellow),
            const PixelGap(2),
            const Expanded(child: PixelText('Vorher am P1S einstellen', color: PixelColors.yellow)),
          ]),
          const PixelGap(1),
          item('LAN-Only-Modus einschalten (Display: Einstellungen › WLAN).'),
          item('Developer-Mode einschalten, sonst lehnt der Drucker Befehle von dieser App ab.'),
          item('Eine SD-Karte muss im Drucker stecken: Druckdateien landen dort.'),
          item('Handy und Drucker müssen im selben WLAN sein.'),
          const PixelGap(2),
          const PixelText.small(
            'Im LAN-Only-Modus funktioniert die Bambu-Handy-App (Cloud) nicht mehr. Bambu Studio im LAN geht weiterhin.',
            color: PixelColors.muted,
          ),
        ],
      ),
    );
  }
}
