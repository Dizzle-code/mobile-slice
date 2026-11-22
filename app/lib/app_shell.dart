import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_services.dart';
import 'engine/slicer_channel.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/printer_screen.dart';
import 'screens/trophies_screen.dart';
import 'screens/workspace_screen.dart';
import 'ui/pixel_button.dart';
import 'ui/pixel_icon.dart';
import 'trophies/trophy_catalog.dart';
import 'ui/pixel_icons.dart';
import 'ui/pixel_overlay.dart';
import 'ui/pixel_progress.dart';
import 'ui/pixel_tab_bar.dart';
import 'ui/pixel_text.dart';
import 'ui/pixel_theme.dart';

/// Loads the services, then shows the four main areas behind a bottom tab bar.
/// Each tab keeps its own navigator so pushed pages stay inside their tab.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});

  final AppServices services;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;
  final _navigators = List.generate(5, (_) => GlobalKey<NavigatorState>());
  final _workspace = GlobalKey<WorkspaceScreenState>();

  /// Index of the workspace area; only the desktop layout shows it as its own area.
  static const workspaceTab = 4;
  bool _desktop = false;

  bool get hasWorkspaceTab => _desktop;

  /// Desktop: switches to the workspace and adds [model] to the current plate.
  Future<void> openWorkspace(PickedModel model) async {
    setState(() => _index = workspaceTab);
    await WidgetsBinding.instance.endOfFrame;
    final workspace = _workspace.currentState;
    if (workspace != null) {
      await workspace.addModel(model);
    } else {
      _pendingModels.add(model);
      if (mounted) setState(() {});
    }
  }

  final _pendingModels = <PickedModel>[];
  late Future<void> _ready = widget.services.init();
  StreamSubscription<void>? _launchSub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _launchSub = widget.services.slicer.launches.listen((_) => _takeLaunch());
    _whenReady();
  }

  @override
  void dispose() {
    _launchSub?.cancel();
    super.dispose();
  }

  void _whenReady() {
    _ready.then((_) {
      _started = true;
      if (mounted) _takeLaunch();
    }, onError: (Object _) {});
  }

  /// Follows a shortcut, widget tap or shared model file once the services are up.
  Future<void> _takeLaunch() async {
    if (!_started) return;
    final LaunchRequest? launch;
    try {
      launch = await widget.services.slicer.takeLaunch();
    } on PlatformException {
      return;
    }
    if (launch == null || !mounted) return;
    final tab = switch (launch.action) {
      'printer' => 1,
      'history' => 2,
      'trophies' => 3,
      _ => 0,
    };
    setState(() => _index = tab);
    await WidgetsBinding.instance.endOfFrame;
    final context = _navigators[tab].currentContext;
    if (context == null || !context.mounted) return;
    final model = launch.model;
    if (launch.error != null) {
      PixelToast.show(context, launch.error!, kind: PixelToastKind.error);
    } else if (model != null) {
      await HomeScreen.open(context, model);
    } else if (launch.action == 'open_model') {
      await HomeScreen.openModel(context);
    }
  }

  static final _tabs = [
    PixelTabItem(PixelIcons.hammer, 'Werkstatt'),
    PixelTabItem(PixelIcons.printer, 'Drucker'),
    PixelTabItem(PixelIcons.clock, 'Verlauf'),
    PixelTabItem(PixelIcons.trophy, 'Trophäen'),
  ];

  /// Desktop sidebar order: start, workspace, printer, history, trophies (values are area indices).
  static final _sideTabs = [
    (0, PixelTabItem(PixelIcons.hammer, 'Start')),
    (workspaceTab, PixelTabItem(PixelIcons.cube, 'Vorbereiten')),
    (1, PixelTabItem(PixelIcons.printer, 'Drucker')),
    (2, PixelTabItem(PixelIcons.clock, 'Verlauf')),
    (3, PixelTabItem(PixelIcons.trophy, 'Trophäen')),
  ];

  Widget _root(int i) => switch (i) {
        0 => const HomeScreen(),
        1 => const PrinterScreen(),
        2 => const HistoryScreen(),
        3 => const TrophiesScreen(),
        _ => WorkspaceScreen(key: _workspace, initial: _takePending()),
      };

  List<PickedModel> _takePending() {
    final models = List.of(_pendingModels);
    _pendingModels.clear();
    return models;
  }

  int get index => _index;

  void select(int index) {
    if (index == _index) {
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = index);
    }
  }

  static AppShellState? maybeOf(BuildContext context) => context.findAncestorStateOfType<AppShellState>();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _failed(snapshot.error!);
        if (snapshot.connectionState != ConnectionState.done) return const _Splash();
        return AppScope(services: widget.services, child: _TrophyListener(services: widget.services, child: _tabsView()));
      },
    );
  }

  Widget _tabsView() {
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= desktopBreakpoint;
      if (desktop != _desktop) {
        _desktop = desktop;
        // Leaving the desktop layout: the workspace area is not reachable from the tab bar.
        if (!desktop && _index == workspaceTab) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _index = 0);
          });
        }
      }
      final areas = IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _navigators.length; i++)
            TickerMode(
              enabled: i == _index,
              child: i == workspaceTab && !desktop
                  ? const SizedBox.shrink()
                  : Navigator(
                      key: _navigators[i],
                      onGenerateRoute: (settings) => PageRouteBuilder<void>(
                        settings: settings,
                        pageBuilder: (_, _, _) => _root(i),
                      ),
                    ),
            ),
        ],
      );
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final navigator = _navigators[_index].currentState;
          if (navigator != null && navigator.canPop()) {
            navigator.maybePop();
          } else if (_index != 0) {
            setState(() => _index = 0);
          } else {
            SystemNavigator.pop();
          }
        },
        child: ColoredBox(
          color: PixelColors.background,
          child: desktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PixelSideBar(
                      items: [for (final (_, item) in _sideTabs) item],
                      index: _sideTabs.indexWhere((t) => t.$1 == _index),
                      onSelected: (i) => select(_sideTabs[i].$1),
                    ),
                    Expanded(child: areas),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: areas),
                    PixelTabBar(items: _tabs, index: _index.clamp(0, _tabs.length - 1), onSelected: select),
                  ],
                ),
        ),
      );
    });
  }

  Widget _failed(Object error) => ColoredBox(
        color: PixelColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelIcon(PixelIcons.warning, scale: 3, secondColor: PixelColors.red),
                const PixelGap(4),
                const PixelText.heading('Start fehlgeschlagen'),
                const PixelGap(2),
                PixelText(error.toString(), color: PixelColors.muted, align: TextAlign.center),
                const PixelGap(4),
                PixelButton(
                  label: 'Nochmal',
                  onPressed: () => setState(() {
                    _ready = widget.services.retryInit();
                    _whenReady();
                  }),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PixelColors.background,
        child: Center(
          child: SizedBox(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelIcon(PixelIcons.cube, scale: 4),
                const PixelGap(4),
                const PixelText.title('Mobile Slice'),
                const PixelGap(4),
                const PixelProgressBar(value: null, semanticLabel: 'App lädt'),
              ],
            ),
          ),
        ),
      );
}

/// Shows the pop-up for every trophy the services report.
class _TrophyListener extends StatefulWidget {
  const _TrophyListener({required this.services, required this.child});

  final AppServices services;
  final Widget child;

  @override
  State<_TrophyListener> createState() => _TrophyListenerState();
}

class _TrophyListenerState extends State<_TrophyListener> {
  StreamSubscription<Trophy>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.services.newTrophies.stream.listen((trophy) {
      if (!mounted) return;
      TrophyPopup.show(context, TrophyPopupData(glyph: trophy.glyph, name: trophy.name, description: trophy.description));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
