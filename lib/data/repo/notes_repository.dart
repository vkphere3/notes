// lib/data/repo/notes_repository.dart
import 'package:isar/isar.dart';
import '../db/isar_service.dart';
import '../models/note.dart';
import '../../core/tag_parser.dart';
import '../../core/tag_parser.dart';
import '../db/isar_service.dart';

class NotesRepository {
  Future<Note> create(String title, String body) async {
    final isar = await IsarService.instance();
    final now = DateTime.now();
    final note = Note()
      ..title = title
      ..body = body
      ..tags = {...extractTags(title), ...extractTags(body)}.toList()
      ..pinned = false
      ..createdAt = now
      ..updatedAt = now;
    await isar.writeTxn(() async => await isar.notes.put(note));
    return note;
  }

  Future<void> delete(Id id) async {
    final isar = await IsarService.instance();
    await isar.writeTxn(() async => await isar.notes.delete(id));
  }

  Future<Note?> getById(Id id) async {
    final isar = await IsarService.instance();
    return isar.notes.get(id);
  }

  Future<void> update(
    Note note, {
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    String finalTitle = title.trim();
    if (finalTitle.isEmpty) {
      final words = body.trim().split(RegExp(r'\s+'));
      finalTitle = words.take(6).join(' ');
    }

    final isar = await IsarService.instance();
    await isar.writeTxn(() async {
      note
        ..title = finalTitle
        ..body = body
        ..tags = extractTags('$finalTitle\n$body')
        ..updatedAt = now;
      await isar.notes.put(note);
    });
  }

  int _noteComparator(Note a, Note b) {
    if (a.pinned != b.pinned) return b.pinned ? 1 : -1; // pinned first
    return b.updatedAt.compareTo(a.updatedAt); // then newest first
  }

  Future<Note> recreate(Note from) async {
    final isar = await IsarService.instance();
    final n = Note()
      ..title = from.title
      ..body = from.body
      ..tags = List.of(from.tags)
      ..pinned = from.pinned
      ..createdAt = from.createdAt
      ..updatedAt = DateTime.now();
    await isar.writeTxn(() async => await isar.notes.put(n));
    return n;
  }

  // inside class NotesRepository
  Future<int> createAndReturnId(String title, String body) async {
    final now = DateTime.now();

    // If no title provided, use first few words of body
    String finalTitle = title.trim();
    if (finalTitle.isEmpty) {
      final words = body.trim().split(RegExp(r'\s+'));
      finalTitle = words.take(6).join(' '); // first ~6 words
    }

    final n = Note()
      ..title = finalTitle
      ..body = body
      ..tags = extractTags('$finalTitle\n$body')
      ..pinned = false
      ..createdAt = now
      ..updatedAt = now;

    final isar = await IsarService.instance();
    final id = await isar.writeTxn(() async => await isar.notes.put(n));
    return id;
  }

  // --- Reactive stream with stage-safe querying + in-memory sort ---
  Stream<List<Note>> watch({String? query, String? tag}) async* {
    final isar = await IsarService.instance();

    String? q = query?.trim();
    q = (q != null && q.isNotEmpty) ? q.toLowerCase() : null;
    final t = (tag != null && tag.isNotEmpty) ? tag.toLowerCase() : null;

    Future<List<Note>> fetch() async {
      final col = isar.notes;

      // No filters → use where().findAll()
      if (t == null && q == null) {
        final list = await col.where().findAll();
        list.sort(_noteComparator);
        return list;
      }

      // Build a builder that is GUARANTEED to be QAfterFilterCondition
      if (t != null && q != null) {
        final qb = col
            .filter()
            .tagsElementEqualTo(t)
            .group(
              (g) => g
                  .titleContains(q!, caseSensitive: false)
                  .or()
                  .bodyContains(q, caseSensitive: false),
            );
        final list = await qb.findAll(); // ok: QAfterFilterCondition
        list.sort(_noteComparator);
        return list;
      } else if (t != null) {
        final qb = col.filter().tagsElementEqualTo(t);
        final list = await qb.findAll(); // ok
        list.sort(_noteComparator);
        return list;
      } else {
        // q != null
        final qb = col.filter().group(
          (g) => g
              .titleContains(q!, caseSensitive: false)
              .or()
              .bodyContains(q!, caseSensitive: false),
        );
        final list = await qb.findAll(); // ok
        list.sort(_noteComparator);
        return list;
      }
    }

    // First emit
    yield await fetch();
    // Emit on any collection change
    yield* isar.notes
        .watchLazy(fireImmediately: false)
        .asyncMap((_) => fetch());
  }
}
