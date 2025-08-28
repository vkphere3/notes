Notes MVP 📒

A minimalist but powerful Flutter note-taking app with local-first storage, tagging via #hashtags, and a clean Material 3 design.

Built with:

Flutter
 + Riverpod
 for state

Isar
 for local database

GoRouter
 for navigation

Google Fonts
 + Material 3 theming

✨ Features

Create & Edit Notes

Title + body, with autosave (debounced 1.2s) and manual Save

Saved / Unsaved / Saving… status pill

Delete with confirmation

Autosaves on background/quit

#Hashtag Tagging

Just type #tag anywhere in your note

Tags auto-extracted and indexed

Tags shown as chips under each note

Search & Filter

Tokenized search bar:

#tag → becomes a chip inside the field

Combine text + tag

One-tap clear

Horizontal tag strip with counts (#tag (5))

Pick a chip to filter

“All” chip resets filter

Notes List

Pinned first, then newest-updated

Preview highlights #tags in body text

Swipe-to-delete with Undo

Tap to open with a smooth fade-through animation

Pin/unpin from card

Quick Add

Bottom-sheet editor from FAB

Title + body → Save instantly

Backup & Restore

Export → JSON file with all notes (shareable)

Restore → replace DB from JSON

Import (merge) → add notes, avoid simple duplicates

Command Palette (Cmd/Ctrl+K)

Create new note

Clear search

Export / Import

Quick “Filter by #tag” commands

🏗️ Project Structure
lib/
  app/           → routing & theme
  core/          → tag parser
  data/          → models, db, repositories
  features/
    home/        → home page (list, search, tags)
    editor/      → editor page (autosave, delete)
    notes/       → providers & widgets
    palette/     → command palette


Note model stored in Isar, with title, body, tags[], pinned, timestamps

NotesRepository handles CRUD + reactive queries

BackupRepository handles JSON import/export

🚀 Getting Started
# Get dependencies
flutter pub get

# Run build_runner for Isar models
flutter pub run build_runner build --delete-conflicting-outputs

# Run app
flutter run

📦 Dependencies

- flutter_riverpod
- go_router
- isar (+ vendored isar_flutter_libs)
- path_provider
- animations
- file_picker
- share_plus
- google_fonts
- dynamic_color
- shared_preferences

Dev:

- build_runner
- isar_generator
- flutter_lints

⚠️ Notes

test/widget_test.dart is still the Flutter template counter test and will fail. Replace with tests for NotesApp.

Platform folders (android/ios/web/etc.) are .gitignore’d. Run flutter create . if missing.

Would you like me to also replace the default widget_test.dart with a working smoke test for NotesApp in the README instructions, so new contributors don’t get confused by failing tests?