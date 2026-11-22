import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_services.dart';
import 'engine/slicer_channel.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/printer_screen.dart';
import 'screens/trophies_screen.dart';
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
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
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

  static const _roots = <Widget>[HomeScreen(), PrinterScreen(), HistoryScreen(), TrophiesScreen()];

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
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < _roots.length; i++)
                    TickerMode(
                      enabled: i == _index,
                      child: Navigator(
                        key: _navigators[i],
                        onGenerateRoute: (settings) => PageRouteBuilder<void>(
                          settings: settings,
                          pageBuilder: (_, _, _) => _roots[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PixelTabBar(items: _tabs, index: _index, onSelected: select),
          ],
        ),
      ),
    );
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
