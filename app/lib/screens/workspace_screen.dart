import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_services.dart';
import '../engine/setting_defs.dart';
import '../engine/slice_outcome.dart';
import '../engine/slicer_channel.dart';
import '../model/mesh.dart';
import '../model/overhang.dart';
import '../model/plate_project.dart';
import '../preview/plate_viewer.dart';
import '../ui/pixel_button.dart';
import '../ui/pixel_frame.dart';
import '../ui/pixel_icon.dart';
import '../ui/pixel_icons.dart';
import '../ui/pixel_overlay.dart';
import '../ui/pixel_progress.dart';
import '../ui/pixel_scaffold.dart';
import '../ui/pixel_stepper.dart';
import '../ui/pixel_text.dart';
import '../ui/pixel_text_field.dart';
import '../ui/pixel_theme.dart';
import '../util/format.dart';
import 'model_size_panel.dart' show minModelScale, maxModelScale;
import 'quick_settings_panel.dart';
import 'result_screen.dart';

/// Window width from which the workspace shows plates, view and settings side by side.
const desktopBreakpoint = 1000.0;

/// The slicer workspace: several plates, objects on them, the 3D plate view, settings and slicing.
/// One project lives as long as the app; opening a model adds it to the current plate.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, this.initial = const []});

  /// Models added once the workspace is up.
  final List<PickedModel> initial;

  @override
  State<WorkspaceScreen> createState() => WorkspaceScreenState();
}

class WorkspaceScreenState extends State<WorkspaceScreen> {
  late final AppServices _services = AppScope.of(context);
  late final PlateProject _project = _services.project;
  bool _started = false;

  int _loading = 0;
  bool _slicing = false;
  int _percent = 0;
  String _stage = '';
  String _message = '';
  StreamSubscription<EngineProgress>? _progressSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    for (final model in widget.initial) {
      unawaited(addModel(model));
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Loads [model] through the engine (same placement as slicing) and adds it to the current plate.
  Future<void> addModel(PickedModel model) async {
    setState(() => _loading++);
    try {
      final source = await _services.loadSource(model);
      if (!mounted) return;
      _project.add(source);
      final added = _project.selected;
      if (added != null && !added.fits(_project.bed)) {
        PixelToast.show(context, '${model.name} ist größer als das Druckbett. Unter „Objekt“ verkleinern.', kind: PixelToastKind.error);
      }
    } on PlatformException catch (e) {
      if (mounted) PixelToast.show(context, e.message ?? e.code, kind: PixelToastKind.error);
    } catch (e) {
      if (mounted) PixelToast.show(context, e.toString().replaceFirst('Exception: ', ''), kind: PixelToastKind.error);
    } finally {
      if (mounted) setState(() => _loading--);
    }
  }

  Future<void> _pickAndAdd() async {
    try {
      final picked = await _services.slicer.pickModel();
      if (picked == null || !mounted) return;
      if (picked.path.startsWith(_services.recent.modelsDir.path)) await _services.recent.add(picked);
      await addModel(picked);
    } on PlatformException catch (e) {
      if (mounted) PixelToast.show(context, e.message ?? e.code, kind: PixelToastKind.error);
    }
  }

  Future<void> _slice() async {
    final services = _services;
    final index = _project.plateIndex;
    final plate = _project.plate;
    if (plate.isEmpty) return;
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
      final plateFile = File('${dir.path}${Platform.pathSeparator}plate.json');
      await plateFile.writeAsString(jsonEncode(_project.engineJson(index)));
      final name = _plateName(plate, index);
      final job = EngineJob(
        type: EngineJobType.slice,
        model: plate.objects.first.source.path,
        plate: plateFile.path,
        label: name,
        outputDir: dir.path,
        baseName: baseNameOf(name),
        process: catalog.process(settings.processId).file,
        filament: catalog.filament(settings.filamentId).file,
        overrides: settings.overrides(services.profile),
        modelId: catalog.printer.modelId,
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
          modelName: name,
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

  /// "3DBenchy" for one object, "3DBenchy + 2" for more, numbered by plate when there are several.
  String _plateName(Plate plate, int index) {
    final first = baseNameOf(plate.objects.first.name);
    final base = plate.objects.length == 1 ? first : '$first + ${plate.objects.length - 1}';
    return _project.plates.length > 1 ? '$base (Platte ${index + 1})' : base;
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _slicing) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final control = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;
    if (control && key == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? _project.redo() : _project.undo();
    } else if (control && key == LogicalKeyboardKey.keyY) {
      _project.redo();
    } else if (control && key == LogicalKeyboardKey.keyD) {
      _project.duplicateSelected();
    } else if (control && key == LogicalKeyboardKey.keyO) {
      unawaited(_pickAndAdd());
    } else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      _project.removeSelected();
    } else if (key == LogicalKeyboardKey.keyA && !control) {
      _project.arrange();
    } else if (key == LogicalKeyboardKey.escape) {
      _project.select(null);
    } else if (_project.selected != null &&
        {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown}.contains(key)) {
      final step = keys.isShiftPressed ? 10.0 : 1.0;
      _project.updateSelected((o) => switch (key) {
            LogicalKeyboardKey.arrowLeft => o.copyWith(x: o.x - step),
            LogicalKeyboardKey.arrowRight => o.copyWith(x: o.x + step),
            LogicalKeyboardKey.arrowUp => o.copyWith(y: o.y + step),
            _ => o.copyWith(y: o.y - step),
          });
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_slicing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) PixelToast.show(context, 'Erst das Slicen abbrechen');
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        // A click anywhere into the workspace gives it the keyboard back (text fields take it while typing).
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            final context = FocusManager.instance.primaryFocus?.context;
            final typing = context != null && context.findAncestorStateOfType<EditableTextState>() != null;
            if (!typing) _focus.requestFocus();
          },
          child: ListenableBuilder(
          // Settings matter too: the support hint depends on them.
          listenable: Listenable.merge([_project, _services.settings]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= desktopBreakpoint ? _desktop(context) : _phone(context),
          ),
        ),
        ),
      ),
    );
  }

  final _focus = FocusNode(debugLabel: 'Arbeitsplatz');

  // ---------- Layouts ----------

  Widget _desktop(BuildContext context) {
    return ColoredBox(
      color: PixelColors.background,
      child: Column(
        children: [
          _toolbar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 280,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                    children: [
                      _platesPanel(),
                      const PixelGap(4),
                      _objectsPanel(),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _viewPanel()),
                        const PixelGap(2),
                        _statusLine(),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
                    children: [
                      if (_project.selected != null) ...[_objectPanel(_project.selected!), const PixelGap(4)],
                      QuickSettingsPanel(enabled: !_slicing),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _sliceBar(),
        ],
      ),
    );
  }

  Widget _phone(BuildContext context) {
    final selected = _project.selected;
    return PixelScaffold(
      title: 'Arbeitsplatz',
      onBack: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
      actions: [
        PixelIconButton(icon: PixelIcons.plus, label: 'Modell hinzufügen', onPressed: _slicing ? null : _pickAndAdd),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _plateTabs(),
          const PixelGap(2),
          PixelPanel(
            padding: EdgeInsets.zero,
            color: PixelColors.background,
            child: SizedBox(height: 320, child: _viewer()),
          ),
          const PixelGap(2),
          _statusLine(),
          const PixelGap(2),
          _toolButtons(wrap: true),
          const PixelGap(4),
          if (selected != null) ...[_objectPanel(selected), const PixelGap(4)],
          _objectsPanel(),
          const PixelGap(4),
          QuickSettingsPanel(enabled: !_slicing),
        ],
      ),
      bottom: _sliceBar(),
    );
  }

  // ---------- Parts ----------

  Widget _toolbar() => Container(
        decoration: const BoxDecoration(
          color: PixelColors.panel,
          border: Border(bottom: BorderSide(color: PixelColors.shadow, width: PixelTheme.unit)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            PixelIcon(PixelIcons.cube, scale: 2),
            const PixelGap(3),
            const PixelText.heading('Arbeitsplatz'),
            const PixelGap(6),
            Expanded(child: _toolButtons()),
          ],
        ),
      );

  Widget _toolButtons({bool wrap = false}) {
    final enabled = !_slicing;
    final hasSelection = _project.selected != null && enabled;
    final buttons = <Widget>[
      if (!wrap) PixelButton(label: 'Modell hinzufügen', icon: PixelIcons.plus, style: PixelButtonStyle.primary, onPressed: enabled ? _pickAndAdd : null),
      PixelButton(label: 'Anordnen', icon: PixelIcons.layers, onPressed: enabled && !_project.plate.isEmpty ? _project.arrange : null),
      PixelButton(label: 'Kopie', icon: PixelIcons.plus, onPressed: hasSelection ? () => _project.duplicateSelected() : null),
      PixelButton(label: 'Flach legen', icon: PixelIcons.bed, onPressed: hasSelection ? _project.layFlatSelected : null),
      PixelButton(label: 'Löschen', icon: PixelIcons.trash, onPressed: hasSelection ? _project.removeSelected : null),
      PixelIconButton(icon: PixelIcons.back, label: 'Rückgängig', onPressed: enabled && _project.canUndo ? _project.undo : null),
    ];
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: buttons);
  }

  Widget _viewPanel() => PixelPanel(padding: EdgeInsets.zero, color: PixelColors.background, child: _viewer());

  Widget _viewer() {
    final plate = _project.plate;
    return Stack(
      children: [
        Positioned.fill(
          child: PlateViewer(
            key: ValueKey('plate-${plate.id}'),
            objects: plate.objects,
            bed: _project.bed,
            selected: _project.selectedId,
            onSelect: _slicing ? null : _project.select,
            onMoveStart: _slicing ? null : _project.beginEdit,
            onMove: _slicing ? null : _project.moveSelected,
          ),
        ),
        if (plate.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PixelPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PixelText('Diese Platte ist leer'),
                    const PixelGap(2),
                    PixelButton(label: 'Modell hinzufügen', icon: PixelIcons.folder, style: PixelButtonStyle.primary, onPressed: _slicing ? null : _pickAndAdd),
                    const PixelGap(2),
                    PixelButton(label: 'Testwürfel', icon: PixelIcons.cube, onPressed: _slicing ? null : () => addModel(_services.sampleModel)),
                  ],
                ),
              ),
            ),
          ),
        if (_loading > 0)
          const Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: PixelPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PixelText.small('Modell wird geladen …'),
                  PixelGap(1),
                  PixelProgressBar(value: null, height: 12, semanticLabel: 'Modell lädt'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusLine() {
    final plate = _project.plate;
    final fits = _project.plateFits(_project.plateIndex);
    final text = plate.isEmpty
        ? 'Ziehen: Ansicht drehen · Mausrad: Zoom · Rechte Maustaste: verschieben'
        : '${plate.objects.length} ${plate.objects.length == 1 ? 'Objekt' : 'Objekte'} · Objekt ziehen: verschieben · '
            'Pfeiltasten: 1 mm (Umschalt: 10 mm) · Entf: löschen · Strg+D: Kopie · A: anordnen';
    return PixelText.small(
      fits ? text : 'Rot markierte Objekte liegen nicht vollständig auf dem Druckbett.',
      color: fits ? PixelColors.muted : PixelColors.red,
    );
  }

  Widget _platesPanel() {
    final plates = _project.plates;
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PixelIcon(PixelIcons.bed, scale: 1),
            const PixelGap(2),
            const Expanded(child: PixelText.heading('Platten')),
            PixelIconButton(icon: PixelIcons.plus, label: 'Platte hinzufügen', onPressed: _slicing ? null : _project.addPlate),
          ]),
          const PixelGap(2),
          for (var i = 0; i < plates.length; i++) ...[
            if (i > 0) const PixelGap(1),
            _plateRow(i),
          ],
        ],
      ),
    );
  }

  Widget _plateRow(int i) {
    final plate = _project.plates[i];
    final current = i == _project.plateIndex;
    final fits = _project.plateFits(i);
    final count = plate.objects.length;
    return Semantics(
      button: true,
      selected: current,
      label: 'Platte ${i + 1}, $count Objekte',
      child: GestureDetector(
        onTap: _slicing ? null : () => _project.selectPlate(i),
        child: PixelPanel(
          shadow: false,
          color: current ? PixelColors.background : PixelColors.panel,
          borderColor: current ? PixelColors.accent : (fits ? PixelColors.shadow : PixelColors.red),
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PixelText('Platte ${i + 1}', color: current ? PixelColors.accent : PixelColors.text, maxLines: 1),
                    PixelText.small(
                      count == 0 ? 'leer' : '$count ${count == 1 ? 'Objekt' : 'Objekte'}${fits ? '' : ' · passt nicht'}',
                      color: fits ? PixelColors.muted : PixelColors.red,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (current && !_slicing)
                PixelIconButton(
                  icon: PixelIcons.trash,
                  label: 'Platte ${i + 1} entfernen',
                  onPressed: () => _project.removePlate(i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Phone: plates as a row of chips.
  Widget _plateTabs() {
    final plates = _project.plates;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < plates.length; i++) ...[
            GestureDetector(
              onTap: _slicing ? null : () => _project.selectPlate(i),
              child: PixelPanel(
                shadow: false,
                color: i == _project.plateIndex ? PixelColors.accent : PixelColors.panel,
                borderColor: _project.plateFits(i) ? PixelColors.shadow : PixelColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: PixelText(
                  'Platte ${i + 1} · ${plates[i].objects.length}',
                  color: i == _project.plateIndex ? PixelColors.background : PixelColors.text,
                ),
              ),
            ),
            const PixelGap(2),
          ],
          PixelIconButton(icon: PixelIcons.plus, label: 'Platte hinzufügen', onPressed: _slicing ? null : _project.addPlate),
          if (plates.length > 1) ...[
            const PixelGap(2),
            PixelIconButton(
              icon: PixelIcons.trash,
              label: 'Platte ${_project.plateIndex + 1} entfernen',
              onPressed: _slicing ? null : () => _project.removePlate(_project.plateIndex),
            ),
          ],
        ],
      ),
    );
  }

  Widget _objectsPanel() {
    final objects = _project.plate.objects;
    return PixelPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PixelIcon(PixelIcons.cube, scale: 1),
            const PixelGap(2),
            Expanded(child: PixelText.heading('Objekte · Platte ${_project.plateIndex + 1}')),
          ]),
          const PixelGap(2),
          if (objects.isEmpty) const PixelText.small('Noch nichts auf dieser Platte.', color: PixelColors.muted),
          for (final o in objects) ...[
            const PixelGap(1),
            GestureDetector(
              onTap: _slicing ? null : () => _project.select(o.id == _project.selectedId ? null : o.id),
              child: PixelPanel(
                shadow: false,
                color: o.id == _project.selectedId ? PixelColors.background : PixelColors.panel,
                borderColor: o.id == _project.selectedId ? PixelColors.yellow : (o.fits(_project.bed) ? PixelColors.shadow : PixelColors.red),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: PixelText(o.name, maxLines: 1)),
                    PixelText.small(_sizeText(o), color: PixelColors.muted, maxLines: 1),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sizeText(PlateObject o) {
    final f = o.footprint;
    return '${decimal(f.sizeX, 0)}×${decimal(f.sizeY, 0)}×${decimal(f.sizeZ, 0)}';
  }

  Widget _objectPanel(PlateObject o) => ObjectPanel(
        key: ValueKey('object-${o.id}'),
        object: o,
        project: _project,
        plateCount: _project.plates.length,
        plateIndex: _project.plateIndex,
        enabled: !_slicing,
        supportOn: _services.settings.value.effectiveKey('enable_support', _services.profile) == true,
        onEnableSupport: () {
          final settings = _services.settings.value;
          _services.settings.value = settings.withValue('enable_support', true,
              profileValue: settings.profileValue(settingDef('enable_support')!, _services.profile));
        },
      );

  Widget _sliceBar() {
    final plate = _project.plate;
    final ready = !plate.isEmpty && _project.plateFits(_project.plateIndex) && _loading == 0;
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panel,
        border: Border(top: BorderSide(color: PixelColors.shadow, width: PixelTheme.unit)),
      ),
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
              label: _project.plates.length > 1 ? 'Platte ${_project.plateIndex + 1} slicen' : 'Slicen',
              icon: PixelIcons.play,
              style: PixelButtonStyle.primary,
              expand: true,
              onPressed: ready ? _slice : null,
            ),
    );
  }
}

/// Position, rotation and size of the selected object, plus moving it to another plate.
class ObjectPanel extends StatefulWidget {
  const ObjectPanel({
    super.key,
    required this.object,
    required this.project,
    required this.plateCount,
    required this.plateIndex,
    required this.enabled,
    required this.supportOn,
    required this.onEnableSupport,
  });

  final PlateObject object;
  final PlateProject project;
  final int plateCount;
  final int plateIndex;
  final bool enabled;
  final bool supportOn;
  final VoidCallback onEnableSupport;

  @override
  State<ObjectPanel> createState() => _ObjectPanelState();
}

class _ObjectPanelState extends State<ObjectPanel> {
  late final _x = TextEditingController();
  late final _y = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ObjectPanel old) {
    super.didUpdateWidget(old);
    if (old.object.x != widget.object.x || old.object.y != widget.object.y) _sync();
  }

  void _sync() {
    _x.text = decimal(widget.object.x, 1);
    _y.text = decimal(widget.object.y, 1);
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _change(PlateObject Function(PlateObject) change) {
    if (!widget.enabled) return;
    widget.project.updateSelected(change);
  }

  void _position(String text, bool isX) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null) {
      setState(_sync);
      return;
    }
    _change((o) => isX ? o.copyWith(x: value) : o.copyWith(y: value));
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.object;
    final f = o.footprint;
    final enabled = widget.enabled;
    final bed = widget.project.bed;
    final overhang = o.source.overhangCache.putIfAbsent(
      (o.rotX, o.rotY, o.rotZ),
      () => overhangArea(Mesh(o.placedTriangles(o.source.previewMesh.triangles))),
    );
    final needsSupport = !widget.supportOn && overhang * o.scale * o.scale >= 25;
    return PixelPanel(
      borderColor: PixelColors.yellow,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            PixelIcon(PixelIcons.cube, scale: 1, secondColor: PixelColors.yellow),
            const PixelGap(2),
            Expanded(child: PixelText.heading(o.name, maxLines: 1)),
          ]),
          PixelText.small(
            '${decimal(f.sizeX, 1)} × ${decimal(f.sizeY, 1)} × ${decimal(f.sizeZ, 1)} mm'
            '${o.source.bytes > 0 ? ' · ${formatBytes(o.source.bytes)}' : ''}',
            color: o.fits(bed) ? PixelColors.muted : PixelColors.red,
          ),
          if (needsSupport) ...[
            const PixelGap(2),
            PixelPanel(
              shadow: false,
              borderColor: PixelColors.yellow,
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PixelText.small('Überhänge: braucht wahrscheinlich Stützen.', color: PixelColors.yellow),
                  const PixelGap(1),
                  PixelButton(label: 'Stützen aktivieren', icon: PixelIcons.support, onPressed: enabled ? widget.onEnableSupport : null),
                ],
              ),
            ),
          ],
          const PixelGap(3),
          const PixelText('Position'),
          const PixelGap(1),
          Row(children: [
            Expanded(child: _field(_x, 'X in mm', (t) => _position(t, true))),
            const PixelGap(2),
            Expanded(child: _field(_y, 'Y in mm', (t) => _position(t, false))),
          ]),
          const PixelGap(3),
          const PixelText('Drehen'),
          const PixelGap(1),
          for (final (axis, value, apply) in <(String, double, PlateObject Function(PlateObject, double))>[
            ('Z', o.rotZ, (p, v) => p.copyWith(rotZ: v)),
            ('X', o.rotX, (p, v) => p.copyWith(rotX: v)),
            ('Y', o.rotY, (p, v) => p.copyWith(rotY: v)),
          ]) ...[
            Row(children: [
              SizedBox(width: 28, child: PixelText(axis, color: PixelColors.muted)),
              Expanded(
                child: PixelStepper(
                  label: 'Um $axis',
                  value: value,
                  min: -180,
                  max: 180,
                  step: 15,
                  format: (v) => '${decimal(v, v == v.roundToDouble() ? 0 : 1)}°',
                  onChanged: enabled ? (v) => _change((p) => apply(p, v)) : null,
                ),
              ),
            ]),
            const PixelGap(1),
          ],
          Row(children: [
            Expanded(child: PixelButton(label: 'Umdrehen', icon: PixelIcons.resize, onPressed: enabled ? () => _change((p) => p.copyWith(rotX: p.rotX + 180)) : null)),
            const PixelGap(2),
            Expanded(
              child: PixelButton(
                label: 'Zurücksetzen',
                onPressed: enabled && (o.rotX != 0 || o.rotY != 0 || o.rotZ != 0) ? () => _change((p) => p.copyWith(rotX: 0, rotY: 0, rotZ: 0)) : null,
              ),
            ),
          ]),
          const PixelGap(3),
          const PixelText('Größe'),
          const PixelGap(1),
          PixelStepper(
            label: 'Größe',
            value: double.parse((o.scale * 100).toStringAsFixed(1)),
            min: minModelScale * 100,
            max: maxModelScale * 100,
            step: 5,
            format: (v) => '${decimal(v, v == v.roundToDouble() ? 0 : 1)} %',
            onChanged: enabled ? (v) => _change((p) => p.copyWith(scale: v / 100)) : null,
          ),
          const PixelGap(1),
          Row(children: [
            Expanded(
              child: PixelButton(
                label: 'Auf Bett einpassen',
                icon: PixelIcons.resize,
                onPressed: enabled ? () => _change((p) => p.copyWith(scale: p.scale * _fitFactor(p, bed))) : null,
              ),
            ),
            const PixelGap(2),
            PixelButton(label: '100 %', onPressed: enabled && o.scale != 1 ? () => _change((p) => p.copyWith(scale: 1)) : null),
          ]),
          if (widget.plateCount > 1 || !widget.project.plate.isEmpty) ...[
            const PixelGap(3),
            const PixelText('Auf Platte verschieben'),
            const PixelGap(1),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.plateCount; i++)
                  if (i != widget.plateIndex)
                    PixelButton(label: 'Platte ${i + 1}', onPressed: enabled ? () => widget.project.moveSelectedToPlate(i) : null),
                PixelButton(label: 'Neue Platte', icon: PixelIcons.plus, onPressed: enabled ? () => widget.project.moveSelectedToPlate(widget.plateCount) : null),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Factor that makes the object as large as the build volume allows (rounded down to 0.1 %).
  double _fitFactor(PlateObject o, PlateSize bed) {
    final f = o.footprint;
    final limits = [
      if (f.sizeX > 0) bed.x / f.sizeX,
      if (f.sizeY > 0) bed.y / f.sizeY,
      if (f.sizeZ > 0) bed.height / f.sizeZ,
    ];
    if (limits.isEmpty) return 1;
    final target = (limits.reduce(math.min) * o.scale * 1000).floor() / 1000;
    return target.clamp(minModelScale, maxModelScale) / o.scale;
  }

  Widget _field(TextEditingController controller, String label, ValueChanged<String> onSubmitted) => PixelTextField(
        controller: controller,
        label: label,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
        onSubmitted: widget.enabled ? onSubmitted : null,
      );
}
