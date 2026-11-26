import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import 'onion_route.dart';

final onionRouteRepositoryProvider = Provider<OnionRouteRepository>(
  (ref) => OnionRouteRepository(dataDir: ref.watch(dataDirProvider)),
);

class OnionRoutesNotifier extends AsyncNotifier<List<OnionRoute>> {
  OnionRouteRepository get _repo => ref.read(onionRouteRepositoryProvider);

  @override
  Future<List<OnionRoute>> build() => _repo.load();

  Future<void> save(OnionRoute route) async {
    final list = [...?state.value];
    final i = list.indexWhere((r) => r.id == route.id);
    if (i >= 0) {
      list[i] = route;
    } else {
      list.insert(
        0,
        route.copyWith(createdAt: route.createdAt ?? DateTime.now()),
      );
    }
    await _repo.save(list);
    state = AsyncData(list);
  }

  Future<void> remove(String id) async {
    final list = [...?state.value]..removeWhere((r) => r.id == id);
    await _repo.save(list);
    state = AsyncData(list);
  }
}

final onionRoutesProvider =
    AsyncNotifierProvider<OnionRoutesNotifier, List<OnionRoute>>(
      OnionRoutesNotifier.new,
    );
