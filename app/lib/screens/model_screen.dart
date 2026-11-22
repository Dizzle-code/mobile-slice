import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../engine/profile_catalog.dart';
import '../engine/setting_defs.dart';
import '../engine/slice_outcome.dart';
import '../engine/slice_settings.dart';
import '../engine/slicer_channel.dart';
import '../model/mesh.dart';
import '../model/overhang.dart';
import '../model/stl_reader.dart';
import '../preview/model_viewer.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_choice.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_progress.dart';
import '../ui/pixel_route.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_slider.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_theme.dart';
import '../ui/pixel_toggle.dart';
import '../util/format.dart';
import 'model_size_panel.dart';
import 'preset_widgets.dart';
import 'result_screen.dart';
import 'settings_browser_screen.dart';

/// Preview, slice settings and the slice run for one opened model.
class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key, required this.model});

  final PickedModel model;

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  late final AppServices _services = AppScope.of(context);
  Mesh? _mesh;
  double _overhang = 0;
  bool _engineFits = true;

  /// Uniform model scale; the preview and fit check apply it right away, the engine when slicing.
  double _scale = 1;
  String? _previewError;
  bool _previewing = false;

  bool _slicing = false;
  int _percent = 0;
  String _stage = '';
  String _message = '';
  StreamSubscription<EngineProgress>? _progressSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mesh == null && !_previewing && _previewError == null) _loadPreview();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      final dir = await _services.newJobDir('preview-${DateTime.now().microsecondsSinceEpoch}');
      final result = await _services.slicer.run(EngineJob(
        type: EngineJobType.preview,
        model: widget.model.path,
        label: widget.model.name,
        outputDir: dir.path,
      ));
      if (!result.ok || result.previewPath == null) throw Exception(result.failure);
      final bytes = await File(result.previewPath!).readAsBytes();
      final triangles = await readStlInBackground(bytes);
      unawaited(dir.delete(recursive: true).catchError((_) => dir));
      if (!mounted) return;
      setState(() {
        _mesh = Mesh(triangles);
        _overhang = overhangArea(_mesh!);
        _engineFits = result.fits;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _previewError = e.message ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _previewError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _slice() async {
    final services = _services;
    final settings = services.settings.value;
    final catalog = services.catalog;
    setState(() {
      _slicing = true;
      _percent = 0;
      _stage = stageLabel('start');
      _message = '';
    });
    try {
      final dir = await services.newJobDir('slice-${DateTime.now().microsecondsSinceEpoch}');
      final job = EngineJob(
        type: EngineJobType.slice,
        model: widget.model.path,
        label: widget.model.name,
        outputDir: dir.path,
        baseName: baseNameOf(widget.model.name),
        process: catalog.process(settings.processId).file,
        filament: catalog.filament(settings.filamentId).file,
        overrides: settings.overrides(services.profile),
        modelId: catalog.printer.modelId,
        scale: _scale,
      );
      _progressSub = services.slicer.progress.where((p) => p.jobId == job.id).listen((p) {
        if (!mounted) return;
        setState(() {
          if (p.isStage) {
            _stage = stageLabel(p.message);
          } else {
            _percent = p.percent;
            _message = p.message;
          }
        });
      });
      final result = await services.slicer.run(job);
      if (!mounted) return;
      if (result.ok && result.archivePath != null) {
        final outcome = SliceOutcome.from(
          modelName: widget.model.name,
          result: result,
          settings: settings,
          catalog: catalog,
          profile: services.profile,
        );
        await Navigator.of(context).push(PixelRouteFor.result(outcome));
      } else if (result.cancelled) {
        PixelToast.show(context, 'Slicen abgebrochen');
      } else {
        await _showFailure(result.failure);
      }
    } on PlatformException catch (e) {
      if (mounted) await _showFailure(e.message ?? e.code);
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      if (mounted) setState(() => _slicing = false);
    }
  }

  Future<void> _showFailure(String message) async {
    final share = await showPixelDialog<bool>(
      context,
      title: 'Slicen fehlgeschlagen',
      message: message,
      icon: PixelIcons.warning,
      actions: [
        PixelDialogAction(_services.slicer.desktop ? 'Diagnose-Log speichern' : 'Diagnose-Log teilen', true),
        PixelDialogAction('Schließen', false, style: PixelButtonStyle.primary),
      ],
    );
    if (share == true) {
      try {
        await _services.slicer.shareLog();
      } on PlatformException catch (e) {
        if (mounted) PixelToast.show(context, e.message ?? 'Log nicht verfügbar', kind: PixelToastKind.error);
      }
    }
  }

  void _update(SliceSettings Function(SliceSettings) change) {
    _services.settings.value = change(_services.settings.value);
  }

  /// Sets one engine value; the profile's own value counts as "not changed".
  void _set(String key, Object? value) => _update((s) => s.withValue(key, value, profileValue: s.profileValue(settingDef(key)!, _services.profile)));

  bool get _fits {
    final mesh = _mesh;
    if (mesh == null) return _engineFits;
    final fits = fitsBed(mesh.bounds, _scale, _services.catalog.printer);
    return _scale == 1 ? fits && _engineFits : fits;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_slicing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) PixelToast.show(context, 'Erst das Slicen abbrechen');
      },
      child: PixelScaffold(
        title: widget.model.name,
        onBack: () => Navigator.of(context).maybePop(),
        body: ValueListenableBuilder<SliceSettings>(
          valueListenable: _services.settings,
          builder: (context, settings, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const PixelText.small('PRESET WÄHLEN', color: PixelColors.muted),
              const PixelGap(1),
              PresetStrip(enabled: !_slicing),
              const PixelGap(1),
              PresetStatus(enabled: !_slicing),
              const PixelGap(4),
              _previewPanel(),
              ..._supportWarning(settings),
              const PixelGap(4),
              _settingsPanel(settings),
            ],
          ),
        ),
        bottom: _bottomBar(),
      ),
    );
  }

  Widget _previewPanel() {
    final mesh = _mesh;
    final printer = _services.catalog.printer;
    final error = _previewError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PixelPanel(
          padding: EdgeInsets.zero,
          color: PixelColors.background,
          child: SizedBox(
            height: 280,
            child: mesh != null
                ? ModelViewer(mesh: mesh, bedX: printer.bedX, bedY: printer.bedY, scale: _scale)
                : Center(
                    child: error != null
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PixelIcon(PixelIcons.warning, secondColor: PixelColors.red),
                                const PixelGap(2),
                                PixelText(error, color: PixelColors.red, align: TextAlign.center),
                                const PixelGap(3),
                                PixelButton(label: 'Nochmal versuchen', onPressed: _loadPreview),
                              ],
                            ),
                          )
                        : const Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PixelText('Modell wird geladen …'),
                                PixelGap(3),
                                PixelProgressBar(value: null, semanticLabel: 'Vorschau lädt'),
                              ],
                            ),
                          ),
                  ),
          ),
        ),
        if (mesh != null) ...[
          const PixelGap(2),
          PixelText.small(
            '${decimal(mesh.bounds.sizeX * _scale, 1)} × ${decimal(mesh.bounds.sizeY * _scale, 1)} × ${decimal(mesh.bounds.sizeZ * _scale, 1)} mm'
            '${_scale == 1 ? '' : ' · ${decimal(_scale * 100, 1)} %'}'
            '${widget.model.bytes > 0 ? ' · ${formatBytes(widget.model.bytes)}' : ''}',
            color: PixelColors.muted,
          ),
        ],
        if (mesh != null && !_fits) ...[
          const PixelGap(2),
          const PixelPanel(
            borderColor: PixelColors.red,
            child: PixelText('Das Modell passt nicht auf das Druckbett des P1S (256 × 256 × 250 mm). Unter „Größe“ verkleinern oder einpassen.',
                color: PixelColors.red),
          ),
        ],
      ],
    );
  }

  List<Widget> _supportWarning(SliceSettings settings) {
    if (_mesh == null || !needsSupport(_overhang, _scale)) return const [];
    if (settings.effectiveKey('enable_support', _services.profile) == true) return const [];
    return [
      const PixelGap(2),
      PixelPanel(
        borderColor: PixelColors.yellow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              PixelIcon(PixelIcons.warning, scale: 1, secondColor: PixelColors.yellow),
              const PixelGap(2),
              const Expanded(child: PixelText('Dein Modell braucht wahrscheinlich Stützen', color: PixelColors.yellow)),
            ]),
            const PixelGap(1),
            const PixelText.small(
              'Es hat überhängende Flächen, die ohne Stützen in der Luft gedruckt würden. Bitte aktiviere die Stützen.',
              color: PixelColors.muted,
            ),
            const PixelGap(2),
            PixelButton(
              label: 'Stützen aktivieren',
              icon: PixelIcons.support,
              expand: true,
              onPressed: _slicing ? null : () => _set('enable_support', true),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _settingsPanel(SliceSettings settings) {
    final services = _services;
    final catalog = services.catalog;
    final profile = services.profile;
    final processes = catalog.processes;
    final processIndex = processes.indexWhere((p) => p.id == settings.processId).clamp(0, processes.length - 1);
    final enabled = !_slicing;
    final supportOn = settings.effectiveKey('enable_support', profile) == true;
    final support = !supportOn ? 'off' : ('${settings.effectiveKey('support_type', profile)}'.startsWith('tree') ? 'tree' : 'normal');
    final brim = '${settings.effectiveKey('brim_type', profile)}';
    final fuzzy = settings.effectiveKey('fuzzy_skin', profile) != 'none';
    final mesh = _mesh;
    final changed = settings.changedCount;
    return PixelPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PixelIcon(PixelIcons.gear, scale: 1),
            const PixelGap(2),
            const Expanded(child: PixelText.heading('Schnelleinstellungen')),
          ]),
          const PixelGap(4),
          PixelSlider(
            label: 'Schichthöhe',
            value: processIndex.toDouble(),
            min: 0,
            max: (processes.length - 1).toDouble(),
            divisions: processes.length - 1,
            format: (v) {
              final p = processes[v.round()];
              return '${decimal(p.layerHeight, 2)} mm · ${p.label}';
            },
            unit: 'mm',
            inputDigits: 2,
            detail: (v) => processes[v.round()].label,
            toInput: (v) => processes[v.round()].layerHeight,
            fromInput: (mm) => _nearestProcess(processes, mm).toDouble(),
            onChanged: enabled ? (v) => _update((s) => s.copyWith(processId: processes[v.round()].id)) : null,
          ),
          const PixelGap(3),
          PixelSlider(
            label: 'Füllung',
            value: (settings.effectiveKey('sparse_infill_density', profile) as double).clamp(0, 100),
            min: 0,
            max: 100,
            divisions: 20,
            format: (v) => '${v.round()} %',
            unit: '%',
            onChanged: enabled ? (v) => _set('sparse_infill_density', v.roundToDouble()) : null,
          ),
          const PixelGap(3),
          PixelSlider(
            label: 'Wände',
            value: (settings.effectiveKey('wall_loops', profile) as int).clamp(1, 6).toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            onChanged: enabled ? (v) => _set('wall_loops', v.round()) : null,
          ),
          const PixelGap(3),
          SpeedSlider(settings: settings, onChanged: enabled ? (v) => _update((s) => s.copyWith(speedPercent: v)) : null),
          const PixelGap(4),
          const PixelText('Stützen'),
          const PixelGap(1),
          PixelSegmented<String>(
            options: const [PixelOption('off', 'Aus'), PixelOption('normal', 'Normal'), PixelOption('tree', 'Baum')],
            value: support,
            onChanged: enabled
                ? (m) {
                    _set('enable_support', m != 'off');
                    if (m != 'off') _set('support_type', m == 'tree' ? 'tree(auto)' : 'normal(auto)');
                  }
                : null,
          ),
          if (supportOn)
            PixelToggle(
              label: 'Nur vom Druckbett aus',
              subtitle: 'Keine Stützen, die auf dem Modell stehen',
              value: settings.effectiveKey('support_on_build_plate_only', profile) == true,
              onChanged: enabled ? (v) => _set('support_on_build_plate_only', v) : null,
            ),
          const PixelGap(4),
          const PixelText('Rand (Brim)'),
          const PixelGap(1),
          PixelSegmented<String>(
            options: const [PixelOption('auto_brim', 'Auto'), PixelOption('no_brim', 'Aus'), PixelOption('outer_only', 'Außen')],
            value: brim,
            onChanged: enabled ? (m) => _set('brim_type', m) : null,
          ),
          const PixelGap(2),
          PixelToggle(
            label: 'Fuzzy Skin',
            subtitle: 'Raue, griffige Außenwand',
            value: fuzzy,
            onChanged: enabled ? (v) => _set('fuzzy_skin', v ? 'external' : 'none') : null,
          ),
          const PixelGap(4),
          Row(children: [
            PixelIcon(PixelIcons.spool, scale: 1),
            const PixelGap(2),
            const PixelText('Filament'),
          ]),
          const PixelGap(1),
          PixelChoiceList<String>(
            options: [
              for (final f in catalog.filaments)
                PixelOption(f.id, f.label, subtitle: '${f.type} · Düse ${f.nozzleTemp} °C · Bett ${f.bedTemp} °C'),
            ],
            value: settings.filamentId,
            onChanged: enabled ? (id) => _update((s) => s.copyWith(filamentId: id)) : null,
          ),
          if (mesh != null) ...[
            const PixelGap(4),
            Row(children: [
              PixelIcon(PixelIcons.resize, scale: 1),
              const PixelGap(2),
              const PixelText('Größe'),
            ]),
            const PixelGap(2),
            ModelSizePanel(
              bounds: mesh.bounds,
              scale: _scale,
              printer: catalog.printer,
              onChanged: enabled ? (scale) => setState(() => _scale = scale) : null,
            ),
          ],
          const PixelGap(4),
          PixelButton(
            label: changed == 0 ? 'Alle Einstellungen' : 'Alle Einstellungen · $changed geändert',
            icon: PixelIcons.search,
            style: PixelButtonStyle.primary,
            expand: true,
            onPressed: enabled ? () => Navigator.of(context).push(PixelRoute<void>(builder: (_) => const SettingsBrowserScreen())) : null,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final ready = _mesh != null && _fits && !_previewing;
    return Container(
      color: PixelColors.panel,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: _slicing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: PixelText(_stage, color: PixelColors.yellow, maxLines: 1)),
                  PixelText('$_percent %', color: PixelColors.accent),
                ]),
                const PixelGap(2),
                PixelProgressBar(value: _percent / 100, semanticLabel: 'Slice-Fortschritt'),
                if (_message.isNotEmpty) ...[
                  const PixelGap(1),
                  PixelText.small(_message, color: PixelColors.muted, maxLines: 1),
                ],
                const PixelGap(3),
                PixelButton(
                  label: 'Abbrechen',
                  icon: PixelIcons.stop,
                  style: PixelButtonStyle.danger,
                  expand: true,
                  onPressed: () => _services.slicer.cancel(),
                ),
              ],
            )
          : PixelButton(
              label: 'Slicen',
              icon: PixelIcons.play,
              style: PixelButtonStyle.primary,
              expand: true,
              onPressed: ready ? _slice : null,
            ),
    );
  }
}

/// Index of the profile whose layer height is closest to [mm].
int _nearestProcess(List<ProcessProfile> processes, double mm) {
  var best = 0;
  for (var i = 1; i < processes.length; i++) {
    if ((processes[i].layerHeight - mm).abs() < (processes[best].layerHeight - mm).abs()) best = i;
  }
  return best;
}
