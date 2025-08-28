// lib/features/home/home_page.dart
import 'dart:async';
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

class OpenPaletteIntent extends Intent {
  const OpenPaletteIntent();
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesStreamProvider);
    final repo = ref.watch(notesRepoProvider);

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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Backed up: ${file.path.split('/').last}',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Backup failed: $e')),
                          );
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Restored $created note(s)'),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restore failed: $e')),
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'export', child: Text('Backup')),
                    PopupMenuItem(value: 'import', child: Text('Restore')),
                  ],
                ),
              ],
            ),
            body: Column(
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: _TokenSearchBar(), // ← tokenized search field
                ),
                TagStrip(),
                SizedBox(height: 8),
                Expanded(child: _NotesList()),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _showQuickAddSheet(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tokenized search input:
/// - Shows a #tag as a Chip with an ✕ inside the field
/// - Allows text + tag together
/// - Debounced updates to providers (queryProvider + activeTagProvider)
class _TokenSearchBar extends ConsumerStatefulWidget {
  const _TokenSearchBar();

  @override
  ConsumerState<_TokenSearchBar> createState() => _TokenSearchBarState();
}

class _TokenSearchBarState extends ConsumerState<_TokenSearchBar> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _debouncedPushProviders() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final text = _ctrl.text;
      // Remove any inline #tags from the typed query (tag is handled by chip)
      final textSansTags = text
          .replaceAll(RegExp(r'(?:^|\\s)#[A-Za-z0-9_\\-]+'), '')
          .trim();
      ref.read(queryProvider.notifier).state = textSansTags;
    });
  }

  // Promote a typed "#tag" at the end of the field into the chip
  void _promoteTrailingHashtagToChip() {
    final m = RegExp(r'(?:^|\s)#([A-Za-z0-9_\-]+)$').firstMatch(_ctrl.text);
    if (m != null) {
      final tag = m.group(1)!;
      ref.read(activeTagProvider.notifier).state = tag.toLowerCase();
      // Remove just that trailing token from the text field:
      final newText = _ctrl.text
          .replaceAll(RegExp(r'(?:^|\s)#' + RegExp.escape(tag) + r'$'), '')
          .trimRight();
      setState(() => _ctrl.text = newText);
      _debouncedPushProviders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTag = ref.watch(activeTagProvider);
    final hasAnyFilter = selectedTag != null || _ctrl.text.trim().isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Inline tokens (currently: one #tag chip)
            if (selectedTag != null) ...[
              InputChip(
                label: Text('#$selectedTag'),
                onDeleted: () {
                  ref.read(activeTagProvider.notifier).state = null;
                  _debouncedPushProviders();
                  setState(() {}); // refresh layout
                },
                tooltip: 'Remove #$selectedTag',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
            ],

            // The editable query text
            Expanded(
              child: EditableText(
                controller: _ctrl,
                focusNode: FocusNode(),
                style: Theme.of(context).textTheme.bodyLarge!,
                cursorColor: Theme.of(context).colorScheme.primary,
                backgroundCursorColor: Theme.of(
                  context,
                ).colorScheme.surfaceVariant,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                maxLines: 1,
                onChanged: (_) {
                  _debouncedPushProviders();
                  // If user finishes a trailing #tag (space/enter), promote to chip
                  // Detect space or submitting:
                  if (_ctrl.text.endsWith(' ')) {
                    _promoteTrailingHashtagToChip();
                  }
                },
                onSubmitted: (_) {
                  _promoteTrailingHashtagToChip();
                  _debouncedPushProviders();
                },
              ),
            ),

            // Hint / placeholder when empty
            if (!hasAnyFilter)
              IgnorePointer(
                ignoring: true,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Search… type #tag',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                ),
              ),

            // Clear button
            if (hasAnyFilter)
              IconButton(
                tooltip: 'Clear',
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
        final hasFilters =
            (ref.watch(queryProvider).trim().isNotEmpty) ||
            (ref.watch(activeTagProvider) != null);
        if (notes.isEmpty) {
          return _NoResults(
            hasFilters: hasFilters,
            onClear: () {
              ref.read(queryProvider.notifier).state = '';
              ref.read(activeTagProvider.notifier).state = null;
            },
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final n = notes[i];
            return Dismissible(
              key: ValueKey(n.id),
              background: _dismissBg(left: true),
              secondaryBackground: _dismissBg(left: false),
              // Keep undo-first delete (no confirm dialog)
              confirmDismiss: (_) async => true,
              onDismissed: (_) async {
                final deleted = n;
                await repo.delete(n.id);
                HapticFeedback.mediumImpact();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Note deleted'),
                      action: SnackBarAction(
                        label: 'Undo',
                        onPressed: () async {
                          await repo.recreate(deleted);
                        },
                      ),
                    ),
                  );
                }
              },
              child: OpenContainer(
                transitionType: ContainerTransitionType.fadeThrough,
                openElevation: 0,
                closedElevation: 0,
                closedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                openBuilder: (context, _) =>
                    EditorPage(idParam: n.id.toString()),
                closedBuilder: (context, open) => _NoteCard(
                  note: n,
                  onOpen: open,
                  timeAgo: _timeAgo(n.updatedAt),
                  previewBuilder: (ctx) => _tagHighlightedPreview(ctx, n.body),
                  onTogglePin: () async {
                    await repo.update(n, pinned: !n.pinned);
                    HapticFeedback.selectionClick();
                  },
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  Widget _dismissBg({required bool left}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(.12),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.only(left: left ? 16 : 0, right: left ? 0 : 16),
      child: const Icon(Icons.delete_outline),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.hasFilters, required this.onClear});
  final bool hasFilters;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters ? Icons.search_off : Icons.note_alt_outlined,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'No notes match your filter'
                  : 'Create your first note',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            if (hasFilters)
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: const Text('Clear filter'),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onOpen,
    required this.onTogglePin,
    required this.timeAgo,
    required this.previewBuilder,
  });
  final Note note;
  final VoidCallback onOpen;
  final VoidCallback onTogglePin;
  final String timeAgo;
  final WidgetBuilder previewBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.isEmpty ? 'Untitled' : note.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Updated $timeAgo',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: note.pinned ? 'Unpin' : 'Pin',
                    icon: Icon(
                      note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    onPressed: onTogglePin,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Builder(builder: previewBuilder),
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: -8,
                  children: note.tags
                      .map(
                        (t) => Chip(
                          label: Text('#$t'),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bodyCtrl,
              decoration: const InputDecoration(
                hintText: 'Write here… Use #tags anywhere',
              ),
              maxLines: 6,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await repo.create(titleCtrl.text, bodyCtrl.text);
                HapticFeedback.lightImpact();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (ctx.mounted) {
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(const SnackBar(content: Text('Note saved')));
                }
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
