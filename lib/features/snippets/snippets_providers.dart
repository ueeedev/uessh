import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import 'snippet.dart';

final snippetRepositoryProvider = Provider<SnippetRepository>(
  (ref) => SnippetRepository(dataDir: ref.watch(dataDirProvider)),
);

class SnippetsNotifier extends AsyncNotifier<List<Snippet>> {
  SnippetRepository get _repo => ref.read(snippetRepositoryProvider);

  @override
  Future<List<Snippet>> build() => _repo.load();

  Future<void> save(Snippet snippet) async {
    final list = [...?state.value];
    final i = list.indexWhere((s) => s.id == snippet.id);
    final updated = snippet.copyWith(updatedAt: DateTime.now());
    if (i >= 0) {
      list[i] = updated;
    } else {
      list.insert(0, updated);
    }
    await _repo.save(list);
    state = AsyncData(list);
  }

  Future<void> remove(String id) async {
    final list = [...?state.value]..removeWhere((s) => s.id == id);
    await _repo.save(list);
    state = AsyncData(list);
  }
}

final snippetsProvider = AsyncNotifierProvider<SnippetsNotifier, List<Snippet>>(
  SnippetsNotifier.new,
);
