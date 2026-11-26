import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/proxy_settings.dart';
import '../../core/proxy_transport.dart';
import '../../l10n/l10n.dart';
import '../hosts/host.dart';
import '../hosts/hosts_providers.dart';
import '../keys/keys_providers.dart';
import '../settings/settings_providers.dart';
import '../terminal/sessions_providers.dart';
import '../terminal/terminal_session.dart';
import 'port_forward.dart';
import 'tunnel_engine.dart';

final portForwardRepositoryProvider = Provider<PortForwardRepository>(
  (ref) => PortForwardRepository(dataDir: ref.watch(dataDirProvider)),
);

/// Creates a [ForwardTransport] for a [Host]. Overridden in tests to run real
/// local/remote/SOCKS5 tunnels over loopback sockets without an SSH server.
final forwardTransportConnectorProvider = Provider<ForwardTransportConnector>(
  (ref) =>
      (Host host, {required bool Function() isCancelled}) =>
          SshForwardTransport.connect(
            host: host,
            repository: ref.read(hostRepositoryProvider),
            knownHosts: ref.read(knownHostsProvider),
            prompts: ref.read(sessionPromptsProvider),
            keys: ref.read(keyRepositoryProvider),
            connectSocket: (targetHost, targetPort, timeout) {
              final proxy = ref.read(settingsProvider).sshProxy;
              String? password;
              try {
                password = ref.read(vaultProvider).read(sshProxyPasswordKey);
              } catch (_) {}
              return connectSshSocketWithProxy(
                targetHost: targetHost,
                targetPort: targetPort,
                proxy: proxy,
                password: password,
                timeout: timeout,
              );
            },
            isCancelled: isCancelled,
          ),
);

class PortForwardsNotifier extends AsyncNotifier<List<PortForwardRule>> {
  PortForwardRepository get _repo => ref.read(portForwardRepositoryProvider);

  @override
  Future<List<PortForwardRule>> build() => _repo.load();

  Future<void> save(PortForwardRule rule) async {
    final list = [...?state.value];
    final i = list.indexWhere((r) => r.id == rule.id);
    PortForwardRule? previous;
    if (i >= 0) {
      previous = list[i];
      list[i] = rule;
    } else {
      list.insert(
        0,
        rule.copyWith(createdAt: rule.createdAt ?? DateTime.now()),
      );
    }
    await _repo.save(list);
    state = AsyncData(list);

    // If connection parameters changed while this tunnel was running, stop it
    // so the user does not stay unknowingly bound to the old ports/host.
    if (previous != null && _networkConfigChanged(previous, rule)) {
      await ref.read(forwardingRuntimeProvider.notifier).stop(rule.id);
    }
  }

  Future<void> remove(String id) async {
    await ref.read(forwardingRuntimeProvider.notifier).stop(id);
    final list = [...?state.value]..removeWhere((r) => r.id == id);
    await _repo.save(list);
    state = AsyncData(list);
  }

  static bool _networkConfigChanged(PortForwardRule a, PortForwardRule b) =>
      a.type != b.type ||
      a.hostId != b.hostId ||
      a.effectiveBindHost != b.effectiveBindHost ||
      a.bindPort != b.bindPort ||
      a.effectiveTargetHost != b.effectiveTargetHost ||
      a.targetPort != b.targetPort;
}

final portForwardsProvider =
    AsyncNotifierProvider<PortForwardsNotifier, List<PortForwardRule>>(
      PortForwardsNotifier.new,
    );

/// Manages active [ForwardTunnel] instances and publishes live runtime state
/// (status, bound port, connections, traffic counters) per rule id.
class ForwardingRuntimeNotifier
    extends Notifier<Map<String, ForwardRuntimeState>> {
  // Kept outside `state` so onDispose can tear down sockets without reading state.
  final _tunnels = <String, ForwardTunnel>{};
  final _sessionWatchers = <TerminalSession, VoidCallback>{};

  @override
  Map<String, ForwardRuntimeState> build() {
    ref.listen<SessionsState>(sessionsProvider, (_, next) {
      _syncSessionWatchers(next.sessions);
    });
    _syncSessionWatchers(ref.read(sessionsProvider).sessions);

    ref.onDispose(() {
      for (final entry in _sessionWatchers.entries) {
        entry.key.removeListener(entry.value);
      }
      _sessionWatchers.clear();
      for (final tunnel in _tunnels.values.toList()) {
        unawaited(tunnel.stop());
      }
      _tunnels.clear();
    });
    return const {};
  }

  void _syncSessionWatchers(List<TerminalSession> sessions) {
    final activeSet = sessions.toSet();
    for (final s in _sessionWatchers.keys.toList()) {
      if (!activeSet.contains(s)) {
        s.removeListener(_sessionWatchers.remove(s)!);
      }
    }
    for (final s in sessions) {
      if (s.isLocal || _sessionWatchers.containsKey(s)) continue;
      var wasConnected = s.status == SessionStatus.connected;
      void listener() {
        final nowConnected = s.status == SessionStatus.connected;
        if (nowConnected && !wasConnected && ref.mounted) {
          unawaited(_autoStartForHost(s.host.id));
        }
        wasConnected = nowConnected;
      }

      s.addListener(listener);
      _sessionWatchers[s] = listener;
    }
  }

  Future<void> _autoStartForHost(String hostId) async {
    final List<PortForwardRule> rules;
    try {
      rules = await ref.read(portForwardsProvider.future);
    } catch (_) {
      return;
    }
    if (!ref.mounted) return;
    for (final rule in rules) {
      if (!rule.autoStart || rule.hostId != hostId) continue;
      final current = state[rule.id];
      if (current != null && current.isActive) continue;
      unawaited(start(rule));
    }
  }

  ForwardRuntimeState statusOf(String ruleId) =>
      state[ruleId] ?? const ForwardRuntimeState();

  /// Starts [rule], resolving its target [Host] from [hostsProvider].
  Future<void> start(PortForwardRule rule) async {
    final hosts = ref.read(hostsProvider).value?.hosts ?? const <Host>[];
    Host? host;
    for (final h in hosts) {
      if (h.id == rule.hostId) {
        host = h;
        break;
      }
    }
    if (host == null) {
      _setRuleState(
        rule.id,
        ForwardRuntimeState(
          status: ForwardStatus.error,
          error: currentL10n.forwardHostMissing,
        ),
      );
      return;
    }

    final existing = _tunnels.remove(rule.id);
    if (existing != null) {
      await existing.stop();
    }

    final connector = ref.read(forwardTransportConnectorProvider);
    late final ForwardTunnel tunnel;
    tunnel = ForwardTunnel(
      rule: rule,
      host: host,
      connectTransport: connector,
      onStateChanged: (next) {
        if (!ref.mounted) return;
        if (!identical(_tunnels[rule.id], tunnel)) return;
        _setRuleState(rule.id, next);
      },
    );
    _tunnels[rule.id] = tunnel;
    await tunnel.start();
  }

  Future<void> stop(String ruleId) async {
    final tunnel = _tunnels.remove(ruleId);
    if (tunnel != null) {
      await tunnel.stop();
    }
    if (!ref.mounted) return;
    if (state.containsKey(ruleId)) {
      _setRuleState(ruleId, const ForwardRuntimeState());
    }
  }

  Future<void> toggle(PortForwardRule rule) async {
    final current = statusOf(rule.id);
    if (current.isActive) {
      await stop(rule.id);
    } else {
      await start(rule);
    }
  }

  Future<void> stopAll() async {
    final ids = _tunnels.keys.toList();
    await Future.wait([for (final id in ids) stop(id)]);
  }

  void _setRuleState(String ruleId, ForwardRuntimeState next) {
    state = {...state, ruleId: next};
  }
}

final forwardingRuntimeProvider =
    NotifierProvider<
      ForwardingRuntimeNotifier,
      Map<String, ForwardRuntimeState>
    >(ForwardingRuntimeNotifier.new);

/// Number of currently running or starting tunnels (shown as a badge on the
/// Forwarding sidebar item).
final activeForwardsCountProvider = Provider<int>((ref) {
  final states = ref.watch(forwardingRuntimeProvider);
  var count = 0;
  for (final s in states.values) {
    if (s.isRunning) count++;
  }
  return count;
});
