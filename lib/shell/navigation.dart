import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/terminal/sessions_providers.dart';

/// Pages of the workbench (the first, pinned tab).
enum AppDestination { hosts, keys, snippets, forwarding, settings }

class NavigationNotifier extends Notifier<AppDestination> {
  @override
  AppDestination build() => AppDestination.hosts;

  /// Shows page [d] of the workbench, switching to the workbench tab.
  void go(AppDestination d) {
    state = d;
    ref.read(sessionsProvider.notifier).showHome();
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppDestination>(
  NavigationNotifier.new,
);
