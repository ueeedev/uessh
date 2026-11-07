import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestination { hosts, terminal, keys, snippets, forwarding, settings }

class NavigationNotifier extends Notifier<AppDestination> {
  @override
  AppDestination build() => AppDestination.hosts;

  void go(AppDestination d) => state = d;
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppDestination>(
  NavigationNotifier.new,
);
