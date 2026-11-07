import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icmp_ping.dart';
import '../settings/app_settings.dart';
import '../settings/settings_providers.dart';
import 'host.dart';
import 'hosts_providers.dart';

enum ReachState { unknown, up, down }

class Reachability {
  const Reachability(this.state, {this.latency, this.checkedAt});

  static const unknown = Reachability(ReachState.unknown);

  final ReachState state;

  /// Round-trip (ping) or connect time (SSH port), when reachable.
  final Duration? latency;
  final DateTime? checkedAt;
}

/// Returns the round-trip time if [host] answered, or null if not.
abstract class ReachabilityChecker {
  Future<Duration?> check(Host host, ReachabilityMethod method);
}

/// Checks hosts with the app's own ICMP ping or a TCP connect; no
/// external programs are run.
class SystemReachabilityChecker implements ReachabilityChecker {
  static const timeout = Duration(seconds: 2);

  @override
  Future<Duration?> check(Host host, ReachabilityMethod method) =>
      switch (method) {
        ReachabilityMethod.ping => _ping(host.address),
        ReachabilityMethod.sshPort => _tcp(host.address, host.port),
      };

  /// Built-in ICMP echo; the system `ping` command is never launched.
  Future<Duration?> _ping(String address) async {
    try {
      return await icmpPing(address, timeout: timeout);
    } catch (e) {
      debugPrint('ping $address failed: $e');
      return null;
    }
  }

  Future<Duration?> _tcp(String address, int port) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(address, port, timeout: timeout);
      watch.stop();
      socket.destroy();
      return watch.elapsed;
    } catch (_) {
      return null;
    }
  }
}

final reachabilityCheckerProvider = Provider<ReachabilityChecker>(
  (ref) => SystemReachabilityChecker(),
);

/// Checks every host when the host list first loads, then on a timer
/// (interval from settings). A host that is added, or whose address or
/// port changes, is checked right away.
class ReachabilityNotifier extends Notifier<Map<String, Reachability>> {
  Timer? _timer;
  var _hosts = <Host>[];
  final _targets = <String, String>{}; // host id -> "address:port"
  final _inFlight = <String>{};

  @override
  Map<String, Reachability> build() {
    ref.onDispose(() => _timer?.cancel());

    ref.listen(hostsProvider, (_, next) {
      final hosts = next.value?.hosts;
      if (hosts != null) _onHosts(hosts);
    }, fireImmediately: true);

    ref.listen(
      settingsProvider.select((s) => (s.checkIntervalSeconds, s.checkMethod)),
      (prev, next) {
        _restartTimer(Duration(seconds: next.$1));
        final turnedOn = prev != null && prev.$1 == 0 && next.$1 > 0;
        final methodChanged = prev != null && prev.$2 != next.$2;
        if (turnedOn || methodChanged) _checkAll();
      },
      fireImmediately: true,
    );
    return const {};
  }

  bool get _enabled => ref.read(settingsProvider).checksEnabled;

  void _restartTimer(Duration interval) {
    _timer?.cancel();
    _timer = null;
    if (interval == Duration.zero) return; // checking turned off
    _timer = Timer.periodic(interval, (_) => _checkAll());
  }

  void _onHosts(List<Host> hosts) {
    _hosts = hosts;
    final ids = {for (final h in hosts) h.id};
    final toCheck = <Host>[];
    for (final h in hosts) {
      final target = '${h.address}:${h.port}';
      if (_targets[h.id] != target) toCheck.add(h);
      _targets[h.id] = target;
    }
    _targets.removeWhere((id, _) => !ids.contains(id));

    // State may not be written while build() runs, so defer.
    scheduleMicrotask(() {
      if (!ref.mounted) return;
      if (state.keys.any((id) => !ids.contains(id))) {
        state = {
          for (final e in state.entries)
            if (ids.contains(e.key)) e.key: e.value,
        };
      }
      for (final h in toCheck) {
        if (state.containsKey(h.id)) {
          state = {...state}..remove(h.id); // address changed: unknown again
        }
        _check(h);
      }
    });
  }

  void _checkAll() {
    for (final h in _hosts) {
      _check(h);
    }
  }

  /// Re-check every host now.
  void refresh() => _checkAll();

  Future<void> _check(Host host) async {
    if (!_enabled) return;
    if (!_inFlight.add(host.id)) return; // already being checked
    final target = '${host.address}:${host.port}';
    try {
      final method = ref.read(settingsProvider).checkMethod;
      final latency = await ref
          .read(reachabilityCheckerProvider)
          .check(host, method);
      // Ignore results for hosts deleted or re-pointed meanwhile.
      if (!ref.mounted || _targets[host.id] != target) return;
      state = {
        ...state,
        host.id: Reachability(
          latency != null ? ReachState.up : ReachState.down,
          latency: latency,
          checkedAt: DateTime.now(),
        ),
      };
    } finally {
      _inFlight.remove(host.id);
    }
  }
}

final reachabilityProvider =
    NotifierProvider<ReachabilityNotifier, Map<String, Reachability>>(
      ReachabilityNotifier.new,
    );
