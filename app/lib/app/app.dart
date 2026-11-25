import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../ui/screens/home_shell.dart';
import '../ui/theme/app_theme.dart';
import '../ui/widgets/import_flow.dart';
import 'app_services.dart';

class UnRotApp extends StatefulWidget {
  const UnRotApp({super.key, required this.services, this.initialFiles = const []});

  final AppServices services;

  /// Files passed on the command line ("Open with UnRot").
  final List<String> initialFiles;

  @override
  State<UnRotApp> createState() => _UnRotAppState();
}

class _UnRotAppState extends State<UnRotApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialFiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null) ImportFlow.importPaths(ctx, widget.initialFiles);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Persist pending writes when the app is backgrounded or closed (mobile).
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      widget.services.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: s),
        ChangeNotifierProvider.value(value: s.settings),
        ChangeNotifierProvider.value(value: s.library),
        ChangeNotifierProvider.value(value: s.reels),
        ChangeNotifierProvider.value(value: s.progress),
        ChangeNotifierProvider.value(value: s.annotations),
        ChangeNotifierProvider.value(value: s.feed),
      ],
      child: MaterialApp(
        title: 'UnRot',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) {
            // Navigator context with providers above it (used for command-line imports).
            return const HomeShell();
          },
        ),
      ),
    );
  }
}
