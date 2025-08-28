// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notes_mvp/main.dart';
import 'package:notes_mvp/features/notes/notes_providers.dart';
import 'package:notes_mvp/data/repo/notes_repository.dart';
import 'package:notes_mvp/data/models/note.dart';

/// A lightweight fake that keeps tests hermetic (no Isar, no path_provider).
class FakeNotesRepository extends NotesRepository {
  @override
  Stream<List<Note>> watch({String? query, String? tag}) async* {
    yield const <Note>[];
  }
}

void main() {
  testWidgets('App boots to Home and shows "Notes" title', (
    WidgetTester tester,
  ) async {
    // Provide our fake repo so the app doesn’t hit the DB in tests.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notesRepoProvider.overrideWithValue(FakeNotesRepository())],
        child: const NotesApp(),
      ),
    );

    // Let initial frames settle (router build, first stream tick, etc.).
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // The Home app bar title should be visible.
    expect(find.text('Notes'), findsOneWidget);
  });
}
