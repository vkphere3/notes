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

  // Autosave machinery
  Timer? _saveDebounce;
  bool _saving = false;
  bool _dirty = false;
  DateTime? _lastEditAt;

  int? get _noteId => int.tryParse(widget.idParam);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Mark dirty and (debounced) queue save on edits
    void markDirty() {
      _dirty = true;
      _lastEditAt = DateTime.now();
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 1200), _flushSave);
      setState(() {}); // refresh status chip
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

  // Save immediately if app is backgrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _flushSave();
    }
  }

  Future<void> _flushSave() async {
    if (!_dirty || _loaded == null) return;
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

  // If user backs out right after typing, save first (quietly)
  Future<bool> _handleWillPop() async {
    final now = DateTime.now();
    final msSinceEdit = _lastEditAt == null
        ? 9999
        : now.difference(_lastEditAt!).inMilliseconds;

    if (_dirty || msSinceEdit < 500) {
      // optional tiny hint; not a blocking dialog
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 600),
            content: Text('Saving…'),
          ),
        );
      }
      await _flushSave();
    }
    return true; // allow pop
  }

  @override
  Widget build(BuildContext context) {
    final id = _noteId;
    if (id == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit note')),
        body: const Center(child: Text('Invalid note id.')),
      );
    }

    final noteAsync = ref.watch(noteByIdProvider(id));

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit note'),
          actions: [
            // Status pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: _StatusPill(saving: _saving, dirty: _dirty),
            ),
            IconButton(
              tooltip: 'Save now',
              icon: const Icon(Icons.save_outlined),
              onPressed: () async {
                await _flushSave();
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Saved')));
                }
              },
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final n = _loaded;
                if (n == null) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete note?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final repo = ref.read(notesRepoProvider);
                  await repo.delete(n.id);
                  HapticFeedback.mediumImpact();
                  if (mounted) Navigator.of(context).pop();
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
            // Seed controllers once
            if (_loaded?.id != note.id) {
              _loaded = note;
              _titleCtrl.text = note.title;
              _bodyCtrl.text = note.body;
              _dirty = false;
              _saving = false;
            }

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
                      decoration: const InputDecoration(
                        hintText: 'Write here… Use #tags anywhere',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(
                          12,
                        ), // makes top alignment obvious
                        alignLabelWithHint: true,
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
