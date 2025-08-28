// lib/features/editor/editor_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/note.dart';
import '../../data/repo/notes_repository.dart';
import '../notes/notes_providers.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, required this.idParam});
  final String idParam;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage>
    with WidgetsBindingObserver {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  Note? _loaded;

  // Autosave
  Timer? _saveDebounce;
  bool _saving = false;
  bool _dirty = false;
  DateTime? _lastEditAt;

  int? get _noteId => int.tryParse(widget.idParam);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    void markDirty() {
      _dirty = true;
      _lastEditAt = DateTime.now();
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 1200), _flushSave);
      setState(() {}); // update status pill
    }

    _titleCtrl.addListener(markDirty);
    _bodyCtrl.addListener(markDirty);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _flushSave();
    }
  }

  Future<void> _flushSave() async {
    if (!_dirty || _loaded == null) return;

    // If empty, don't write an "empty edit" over an existing note.
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty && body.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(notesRepoProvider);
    final n = _loaded!;
    try {
      await repo.update(n, title: _titleCtrl.text, body: _bodyCtrl.text);
      _dirty = false;
      HapticFeedback.lightImpact();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _handleWillPop() async {
    final now = DateTime.now();
    final msSinceEdit = _lastEditAt == null
        ? 9999
        : now.difference(_lastEditAt!).inMilliseconds;

    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    // If completely empty, delete the note instead of keeping a blank one.
    if ((title.isEmpty && body.isEmpty) && _loaded != null) {
      final repo = ref.read(notesRepoProvider);
      await repo.delete(_loaded!.id);
      return true; // pop after delete
    }

    if (_dirty || msSinceEdit < 500) {
      await _flushSave(); // quiet flush
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final id = _noteId;
    if (id == null) {
      return const Scaffold(body: Center(child: Text('Invalid note id.')));
    }

    final noteAsync = ref.watch(noteByIdProvider(id));

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () async {
              if (await _handleWillPop()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: Row(
            children: [
              const Text('Edit'),
              const SizedBox(width: 12),
              _StatusPill(saving: _saving, dirty: _dirty),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Save now',
              icon: const Icon(Icons.save_outlined),
              onPressed: () async {
                final title = _titleCtrl.text.trim();
                final body = _bodyCtrl.text.trim();

                if (title.isEmpty && body.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nothing to save'),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  return; // 🚫 don’t save empties
                }

                await _flushSave();
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saved'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.fromLTRB(12, 0, 12, 12),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final repo = ref.read(notesRepoProvider);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete this note?'),
                    content: const Text('This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final n = _loaded;
                  if (n != null) {
                    await repo.delete(n.id);
                    if (mounted) Navigator.of(context).pop();
                  }
                }
              },
            ),
          ],
        ),
        body: noteAsync.when(
          data: (note) {
            if (note == null) {
              return const Center(child: Text('Note not found.'));
            }
            // Seed once
            if (_loaded?.id != note.id) {
              _loaded = note;
              _titleCtrl.text = note.title;
              _bodyCtrl.text = note.body;
              _dirty = false;
              _saving = false;
            }

            final cs = Theme.of(context).colorScheme;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(hintText: 'Title'),
                    style: Theme.of(context).textTheme.titleLarge,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _bodyCtrl,
                      decoration: InputDecoration(
                        hintText: 'Write here… Use #tags anywhere',
                        filled: true,
                        fillColor: cs.surfaceVariant.withOpacity(0.55),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.saving, required this.dirty});
  final bool saving;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color color;

    if (saving) {
      icon = Icons.sync;
      label = 'Saving…';
      color = Colors.orange;
    } else if (dirty) {
      icon = Icons.circle;
      label = 'Unsaved';
      color = Colors.amber;
    } else {
      icon = Icons.check_circle;
      label = 'Saved';
      color = Colors.green;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withOpacity(0.12),
        shape: StadiumBorder(side: BorderSide(color: color.withOpacity(0.4))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
