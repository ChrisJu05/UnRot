import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/app_services.dart';

import 'feed_screen.dart';
import 'library_screen.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

/// Top-level navigation: bottom bar on phones, side rail on wide screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.play_circle_outline, Icons.play_circle, 'Feed'),
    (Icons.library_books_outlined, Icons.library_books, 'Library'),
    (Icons.insights_outlined, Icons.insights, 'Progress'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  void _select(int i) {
    // Leaving the feed stops reading aloud.
    if (i != 0) context.read<AppServices>().speech.stop();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedScreen(onOpenLibrary: () => _select(1), onOpenSettings: () => _select(3)),
      const LibraryScreen(),
      const ProgressScreen(),
      const SettingsScreen(),
    ];
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < pages.length; i++)
          // Keep the feed alive; build other tabs lazily.
          TickerMode(enabled: i == _index, child: i == 0 || i == _index ? pages[i] : const SizedBox.shrink()),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('UnRot', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        );
      },
    );
  }
}
