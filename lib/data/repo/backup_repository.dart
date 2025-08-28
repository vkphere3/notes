import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';
import '../models/note.dart';
import '../db/isar_service.dart';

class BackupRepository {
  Future<File> exportAll() async {
    final isar = await IsarService.instance();
    final notes = await isar.notes.where().findAll();
    final payload = notes.map((n) => _toJson(n)).toList();
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/notes_export_$ts.json');
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert(payload),
    );
    return file;
  }

  Future<int> restoreReplaceAll(File file) async {
    final isar = await IsarService.instance();
    final text = await file.readAsString();
    final List data = jsonDecode(text);
    int created = 0;
    await isar.writeTxn(() async {
      await isar.notes.clear();
      for (final raw in data) {
        final map = Map<String, dynamic>.from(raw as Map);
        final n = Note()
          ..title = map['title'] ?? ''
          ..body = map['body'] ?? ''
          ..tags =
              (map['tags'] as List?)
                  ?.map((e) => e.toString().toLowerCase())
                  .toList() ??
              <String>[]
          ..pinned = map['pinned'] == true
          ..createdAt =
              DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now()
          ..updatedAt =
              DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now();
        await isar.notes.put(n);
        created++;
      }
    });
    return created;
  }

  // Import behavior: create new notes; naive duplicate detection by (title, body, createdAt)
  Future<int> importFromFile(File file) async {
    final isar = await IsarService.instance();
    final text = await file.readAsString();
    final List data = jsonDecode(text);

    final existing = await isar.notes.where().findAll();

    int created = 0;
    await isar.writeTxn(() async {
      for (final raw in data) {
        final map = Map<String, dynamic>.from(raw as Map);
        final title = map['title'] as String? ?? '';
        final body = map['body'] as String? ?? '';
        final tags =
            (map['tags'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            <String>[];
        final pinned = map['pinned'] == true;
        final createdAt =
            DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now();
        final updatedAt =
            DateTime.tryParse(map['updatedAt'] ?? '') ?? createdAt;

        final dup = existing.firstWhere(
          (n) =>
              n.title == title &&
              n.body == body &&
              n.createdAt.toUtc() == createdAt.toUtc(),
          orElse: () => Note()..id = Isar.autoIncrement, // marker for not found
        );
        if (dup.id == Isar.autoIncrement) {
          final n = Note()
            ..title = title
            ..body = body
            ..tags = tags
            ..pinned = pinned
            ..createdAt = createdAt
            ..updatedAt = updatedAt;
          await isar.notes.put(n);
          created++;
        }
      }
    });
    return created;
  }

  Map<String, dynamic> _toJson(Note n) => {
    // We intentionally do NOT export the Isar id; it is local to the DB
    'title': n.title,
    'body': n.body,
    'tags': n.tags,
    'pinned': n.pinned,
    'createdAt': n.createdAt.toIso8601String(),
    'updatedAt': n.updatedAt.toIso8601String(),
  };
}
