// lib/features/home/home_page.dart
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../notes/notes_providers.dart';
import '../notes/widgets/tag_strip.dart';
import '../palette/command_palette.dart';
import '../../data/models/note.dart';
import '../../data/repo/backup_repository.dart';
import '../../data/repo/notes_repository.dart';
import '../editor/editor_page.dart';

/// Floating snackbar helper (prevents stacking, avoids FAB)
void showAppSnack(BuildContext context, String text, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      action: action,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 80),
      duration: const Duration(seconds: 3),
    ),
  );
}

class OpenPaletteIntent extends Intent {
  const OpenPaletteIntent();
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
            const OpenPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const OpenPaletteIntent(),
      },
      child: Actions(
        actions: {
          OpenPaletteIntent: CallbackAction<OpenPaletteIntent>(
            onInvoke: (_) {
              showCommandPalette(context, ref);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Notes'),
              actions: [
                IconButton(
                  tooltip: 'Command palette (Cmd/Ctrl+K)',
                  icon: const Icon(Icons.search),
                  onPressed: () => showCommandPalette(context, ref),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'export') {
                      try {
                        final file = await BackupRepository().exportAll();
                        await Share.shareXFiles([
                          XFile(file.path),
                        ], text: 'Notes backup');
                        if (context.mounted) {
                          showAppSnack(
                            context,
                            'Backed up: ${file.path.split('/').last}',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showAppSnack(context, 'Backup failed: $e');
                        }
                      }
                    }
                    if (value == 'import') {
                      try {
                        final res = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        if (res != null && res.files.single.path != null) {
                          final created = await BackupRepository()
                              .importFromFile(File(res.files.single.path!));
                          if (context.mounted) {
                            showAppSnack(context, 'Imported $created note(s)');
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showAppSnack(context, 'Import failed: $e');
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'export', child: Text('Backup')),
                    PopupMenuItem(
                      value: 'import',
                      child: Text('Restore / Import'),
                    ),
                  ],
                ),
              ],
            ),
            body: Column(
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: _TokenSearchBar(), // tokenized search field
                ),
                TagStrip(),
                SizedBox(height: 8),
                Expanded(child: _NotesList()),
              ],
            ),
            // 🔁 FAB → create note, then open full-screen EditorPage
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _createAndOpenEditor(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tokenized search box styled like chips (filled + stadium),
/// promoting a trailing "#tag " into an active tag chip.
class _TokenSearchBar extends ConsumerStatefulWidget {
  const _TokenSearchBar();

  @override
  ConsumerState<_TokenSearchBar> createState() => _TokenSearchBarState();
}

class _TokenSearchBarState extends ConsumerState<_TokenSearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pushQuery() {
    ref.read(queryProvider.notifier).state = _ctrl.text;
  }

  void _promoteTrailingHashtagToChip() {
    final t = _ctrl.text.trimRight();
    if (!t.endsWith(' ')) return;
    final parts = t.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final last = parts.last;
    if (last.startsWith('#') && last.length > 1) {
      ref.read(activeTagProvider.notifier).state = last
          .substring(1)
          .toLowerCase();
      parts.removeLast();
      _ctrl.text = parts.join(' ');
      _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _ctrl.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedTag = ref.watch(activeTagProvider);
    final hasAny = selectedTag != null || _ctrl.text.trim().isNotEmpty;

    return Material(
      color: cs.surfaceVariant.withOpacity(0.55),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (selectedTag != null) ...[
              InputChip(
                label: Text('#$selectedTag'),
                onDeleted: () {
                  ref.read(activeTagProvider.notifier).state = null;
                  _pushQuery();
                  setState(() {});
                },
                tooltip: 'Remove #$selectedTag',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search… type #tag',
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  _pushQuery();
                  if (_ctrl.text.endsWith(' ')) _promoteTrailingHashtagToChip();
                },
                onSubmitted: (_) {
                  _promoteTrailingHashtagToChip();
                  _pushQuery();
                },
              ),
            ),
            if (hasAny)
              IconButton(
                tooltip: 'Clear',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () {
                  _ctrl.clear();
                  ref.read(queryProvider.notifier).state = '';
                  ref.read(activeTagProvider.notifier).state = null;
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Widget _tagHighlightedPreview(BuildContext context, String body) {
    final style = DefaultTextStyle.of(context).style;
    final primary = Theme.of(context).colorScheme.primary;
    final re = RegExp(r'(#[A-Za-z0-9_\-]+)');
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in re.allMatches(body)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0)!,
          style: style.copyWith(color: primary, fontWeight: FontWeight.w600),
        ),
      );
      cursor = m.end;
    }
    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }
    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesStreamProvider);
    final repo = ref.watch(notesRepoProvider);

    return notesAsync.when(
      data: (notes) {
        if (notes.isEmpty) {
          return const Center(
            child: Text('No notes yet. Tap “New” to add one!'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final n = notes[i];
            return Dismissible(
              key: ValueKey('note-${n.id}'),
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 16),
                color: Colors.red.withOpacity(0.15),
                child: const Icon(Icons.delete_outline),
              ),
              secondaryBackground: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: Colors.red.withOpacity(0.15),
                child: const Icon(Icons.delete_outline),
              ),
              confirmDismiss: (_) async {
                await repo.delete(n.id);
                if (context.mounted) {
                  showAppSnack(
                    context,
                    'Note deleted',
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () async {
                        await repo.recreate(n);
                      },
                    ),
                  );
                }
                return true;
              },
              child: _NoteCard(note: n),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final Note note;

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    List<Widget> _buildTagPills(List<String> tags, {int maxTags = 1}) {
      if (tags.isEmpty) return [];
      final pills = <Widget>[];
      final shown = tags.take(maxTags).toList();
      for (final t in shown) {
        pills.add(
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '#$t',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        );
      }
      final extra = tags.length - maxTags;
      if (extra > 0) {
        pills.add(
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$extra',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        );
      }
      return pills;
    }

    return OpenContainer(
      closedElevation: 1,
      openElevation: 0,
      closedColor: Theme.of(context).colorScheme.surface,
      openBuilder: (context, _) => EditorPage(idParam: note.id.toString()),
      closedBuilder: (context, open) {
        return InkWell(
          onTap: open,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Title left, tags + pin right
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title.isEmpty ? '(Untitled)' : note.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._buildTagPills(note.tags, maxTags: 1),
                      if (note.pinned) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.push_pin,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Row 2: Description preview
                  Text(
                    note.body.isEmpty ? ' ' : note.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Row 3: Updated ago
                  Text(
                    'Updated ${_timeAgo(note.updatedAt)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Create a new note in the DB and open full-screen editor.
Future<void> _createAndOpenEditor(
  BuildContext context,
  WidgetRef ref, {
  String title = '',
  String body = '',
}) async {
  final repo = ref.read(notesRepoProvider);
  final id = await repo.createAndReturnId(title, body); // must exist in repo
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => EditorPage(idParam: id.toString())));
}

// (Optional) Quick add sheet kept here for reference; currently unused.
Future<void> _showQuickAddSheet(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(notesRepoProvider);
  final titleCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(hintText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyCtrl,
              decoration: const InputDecoration(
                hintText: 'Write here… Use #tags anywhere',
              ),
              maxLines: 6,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final body = bodyCtrl.text.trim();

                if (title.isEmpty && body.isEmpty) {
                  if (ctx.mounted) {
                    final m = ScaffoldMessenger.of(ctx);
                    m.hideCurrentSnackBar();
                    m.showSnackBar(
                      const SnackBar(
                        content: Text('Nothing to save'),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.fromLTRB(12, 0, 12, 80),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  return;
                }

                await repo.create(titleCtrl.text, bodyCtrl.text);
                HapticFeedback.lightImpact();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (ctx.mounted) showAppSnack(ctx, 'Note saved');
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}
