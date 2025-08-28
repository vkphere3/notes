// lib/data/models/note.dart
import 'package:isar/isar.dart';
part 'note.g.dart';

@collection
class Note {
  Id id = Isar.autoIncrement;
  late String title;
  late String body;
  @Index(type: IndexType.hashElements)
  List<String> tags = [];
  bool pinned = false;
  late DateTime createdAt;
  late DateTime updatedAt;
}
