// lib/features/notes/notes_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repo/notes_repository.dart';
import '../../data/models/note.dart';
import 'package:isar/isar.dart';

/// Raw text from the search box.
final queryProvider = StateProvider<String>((ref) => '');

/// If the query starts with '#', treat it as a tag filter.
final _activeTagProvider = Provider<String?>((ref) {
  final q = ref.watch(queryProvider).trim();
  if (q.startsWith('#') && q.length > 1) {
    return q.substring(1).toLowerCase();
  }
  return null;
});

// Explicit active tag chosen from the chip strip (null = no explicit tag)
final activeTagProvider = StateProvider<String?>((ref) => null);

/// Repository provider (simple singleton for now).
final notesRepoProvider = Provider<NotesRepository>((ref) => NotesRepository());

/// Reactive stream of notes from Isar (filters by text or #tag).
// final notesStreamProvider = StreamProvider<List<Note>>((ref) {
//   final repo = ref.watch(notesRepoProvider);
//   final q = ref.watch(queryProvider);
//   final tag = ref.watch(_activeTagProvider);

//   // If user typed a #tag, prefer tag filter; otherwise use text query.
//   return repo.watch(query: tag == null ? q : null, tag: tag);
// });

final noteByIdProvider = FutureProvider.family<Note?, int>((ref, id) async {
  final repo = ref.watch(notesRepoProvider);
  return repo.getById(id);
});

// All notes stream (uncurated) for computing tag counts
final allNotesStreamProvider = StreamProvider<List<Note>>((ref) {
  final repo = ref.watch(notesRepoProvider);
  return repo.watch(); // no filters
});

// Tag counts derived from all notes
class TagCount {
  final String tag;
  final int count;
  const TagCount(this.tag, this.count);
}

final tagCountsProvider = Provider<List<TagCount>>((ref) {
  final asyncAll = ref.watch(allNotesStreamProvider);
  return asyncAll.maybeWhen(
    data: (notes) {
      final map = <String, int>{};
      for (final n in notes) {
        for (final t in n.tags) {
          map[t] = (map[t] ?? 0) + 1;
        }
      }
      final list = map.entries.map((e) => TagCount(e.key, e.value)).toList();
      // Sort by count desc, then alphabetically
      list.sort(
        (a, b) => b.count.compareTo(a.count) != 0
            ? b.count.compareTo(a.count)
            : a.tag.compareTo(b.tag),
      );
      return list;
    },
    orElse: () => const <TagCount>[],
  );
});

// Notes stream that respects: activeTag > #tag in query > plain text query
final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  final repo = ref.watch(notesRepoProvider);
  final rawQ = ref.watch(queryProvider);
  final chosen = ref.watch(activeTagProvider);

  String? tag = chosen;
  String? query;

  if (tag == null) {
    final q = rawQ.trim();
    if (q.startsWith('#') && q.length > 1) {
      tag = q.substring(1).toLowerCase();
    } else if (q.isNotEmpty) {
      query = q;
    }
  }

  return repo.watch(query: query, tag: tag);
});

// Distinct, sorted list of all tags in the DB
final tagUniverseProvider = Provider<List<String>>((ref) {
  final asyncAll = ref.watch(allNotesStreamProvider);
  return asyncAll.maybeWhen(
    data: (notes) {
      final set = <String>{};
      for (final n in notes) {
        set.addAll(n.tags.map((t) => t.toLowerCase()));
      }
      final list = set.toList()..sort();
      return list;
    },
    orElse: () => const <String>[],
  );
});
