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
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();

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
      setState(() {}); // update status pill / divider state
    }

    _titleCtrl.addListener(markDirty);
    _bodyCtrl.addListener(markDirty);

    // For divider animation cues
    _titleFocus.addListener(() => setState(() {}));
    _bodyFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
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
          toolbarHeight: 44, // shorter bar
          titleSpacing: 0,
          leadingWidth: 44,
          leading: _CompactIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Back',
            onPressed: () async {
              if (await _handleWillPop()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: Row(
            children: [
              Text(
                'Edit',
                style: Theme.of(context).textTheme.labelLarge, // subtler title
              ),
              const SizedBox(width: 8),
              _StatusPill(saving: _saving, dirty: _dirty),
            ],
          ),
          actions: [
            // Save (check)
            _CompactIconButton(
              icon: Icons.check_rounded,
              tooltip: 'Save now',
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
                  return;
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

            // More menu (delete moved here)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, size: 20),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
              onSelected: (value) async {
                if (value == 'delete') {
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
            final showDivider =
                _titleFocus.hasFocus ||
                _bodyFocus.hasFocus ||
                _titleCtrl.text.trim().isNotEmpty;

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Single “document” container that holds title + body
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceVariant.withOpacity(0.40),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          // Title (single line, bigger type)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                            child: TextField(
                              controller: _titleCtrl,
                              focusNode: _titleFocus,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Title',
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: Theme.of(context).textTheme.titleLarge,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _bodyFocus.requestFocus(),
                              maxLines: 1,
                            ),
                          ),

                          // Subtle divider (fades in; fixed height to avoid jitter)
                          AnimatedOpacity(
                            opacity: showDivider ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              color: cs.outlineVariant.withOpacity(0.7),
                            ),
                          ),

                          // Body (grows to fill)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                              child: TextField(
                                controller: _bodyCtrl,
                                focusNode: _bodyFocus,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Write here… Use #tags anywhere',
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                keyboardType: TextInputType.multiline,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    Key? key,
  }) : super(key: key);

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20, // smaller icon
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      onPressed: onPressed,
      icon: Icon(icon),
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
