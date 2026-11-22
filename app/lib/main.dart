import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_services.dart';
import 'app_shell.dart';
import 'engine/desktop_slicer.dart';
import 'engine/slicer_channel.dart';
import 'ui/pixel_route.dart';
import 'ui/pixel_theme.dart';

MobileSliceApp createApp([List<String> args = const []]) {
  // The platform channel needs the binding; without it release builds die silently on the splash screen.
  WidgetsFlutterBinding.ensureInitialized();
  final SlicerChannel slicer = Platform.isWindows || Platform.isMacOS ? DesktopSlicer(args) : SlicerChannel();
  return MobileSliceApp(services: AppServices(slicer: slicer));
}

void main(List<String> args) {
  runApp(createApp(args));
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: PixelColors.background,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: PixelColors.panel,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
}

class MobileSliceApp extends StatefulWidget {
  const MobileSliceApp({super.key, required this.services});

  final AppServices services;

  @override
  State<MobileSliceApp> createState() => _MobileSliceAppState();
}

class _MobileSliceAppState extends State<MobileSliceApp> {
  @override
  void initState() {
    super.initState();
    PixelTheme.font.addListener(_fontChanged);
  }

  @override
  void dispose() {
    PixelTheme.font.removeListener(_fontChanged);
    super.dispose();
  }

  // Text styles are read from PixelTheme during build, so every element has to build again.
  void _fontChanged() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    if (mounted) rebuild(context as Element);
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return WidgetsApp(
      title: 'Mobile Slice',
      color: PixelColors.accent,
      textStyle: PixelTheme.body,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(settings, builder) => PixelRoute<T>(settings: settings, builder: builder),
      home: AppShell(services: services),
    );
  }
}
