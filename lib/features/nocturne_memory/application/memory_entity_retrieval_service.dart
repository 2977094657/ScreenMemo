import 'package:screen_memo/features/nocturne_memory/application/memory_entity_models.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_policy.dart';
import 'package:screen_memo/features/nocturne_memory/application/memory_entity_store.dart';

class MemoryEntityRetrievalService {
  MemoryEntityRetrievalService._internal();

  static final MemoryEntityRetrievalService instance =
      MemoryEntityRetrievalService._internal();

  final MemoryEntityStore _store = MemoryEntityStore.instance;

  Future<List<MemoryEntityDossier>> retrieveShortlist({
    required MemoryEntityRootPolicy policy,
    required MemoryVisualCandidate candidate,
    int limit = 8,
  }) async {
    final String canonicalKey = _store.deriveCanonicalKey(
      policy: policy,
      preferredName: candidate.preferredName,
    );
    final List<MemoryEntitySearchCandidate> shortlist = await _store
        .shortlistCandidates(
          rootUri: policy.rootUri,
          entityType: policy.entityType,
          preferredName: candidate.preferredName,
          aliases: candidate.aliases,
          canonicalKey: canonicalKey,
          visualSignatureSummary: candidate.visualSignatureSummary,
          limit: limit,
        );

    final List<MemoryEntityDossier> dossiers = <MemoryEntityDossier>[];
    for (final MemoryEntitySearchCandidate item in shortlist) {
      dossiers.add(await _store.buildDossier(item));
    }
    return dossiers;
  }
}
