import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/repo/backup_repository.dart';
import '../notes/notes_providers.dart';
import '../../data/repo/notes_repository.dart';
import 'dart:async'; // ← needed for FutureOr

Future<void> showCommandPalette(BuildContext context, WidgetRef ref) async {
  final tags = ref.read(tagUniverseProvider);
  final queryCtrl = TextEditingController();

  Future<List<_Command>> buildCommands(String q) async {
    q = q.trim().toLowerCase();
    final cmds = <_Command>[
      _Command('New note', Icons.note_add_outlined, () async {
        final repo = ref.read(notesRepoProvider);
        final n = await repo.create('', '');
        if (context.mounted) {
          Navigator.of(context).pop();
          // editor route
          // ignore: use_build_context_synchronously
          Navigator.of(context).pushNamed('/edit/${n.id}');
        }
      }),
      _Command('Clear search', Icons.clear_all, () {
        ref.read(queryProvider.notifier).state = '';
        ref.read(activeTagProvider.notifier).state = null;
        Navigator.of(context).pop();
      }),
      _Command('Export JSON', Icons.upload_outlined, () async {
        try {
          final file = await BackupRepository().exportAll();
          await Share.shareXFiles([XFile(file.path)], text: 'Notes export');
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not export: $e')));
        } finally {
          Navigator.of(context).pop();
        }
      }),
      _Command('Import JSON', Icons.download_outlined, () async {
        try {
          final res = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json'],
          );
          if (res != null && res.files.single.path != null) {
            final created = await BackupRepository().importFromFile(
              File(res.files.single.path!),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Imported $created note(s)')),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        } finally {
          Navigator.of(context).pop();
        }
      }),
    ];

    // Tag commands: filter by tag
    final filteredTags = tags
        .where((t) => q.isEmpty || t.contains(q))
        .take(12)
        .map(
          (t) => _Command('Filter: #$t', Icons.tag, () {
            ref.read(activeTagProvider.notifier).state = t;
            ref.read(queryProvider.notifier).state = '';
            Navigator.of(context).pop();
          }),
        );

    return [...cmds, ...filteredTags];
  }

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Consumer(
        builder: (context, ref, _) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: queryCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Type a command or #tag…',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<List<_Command>>(
                        future: buildCommands(queryCtrl.text),
                        builder: (context, snap) {
                          final items = snap.data ?? const <_Command>[];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No matches'),
                            );
                          }
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final c = items[i];
                                return ListTile(
                                  leading: Icon(c.icon),
                                  title: Text(c.title),
                                  onTap: () => c.run(),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

class _Command {
  final String title;
  final IconData icon;
  final FutureOr<void> Function() run;
  _Command(this.title, this.icon, this.run);
}
