import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class IsarService {
  static Isar? _isar;
  static Future<Isar> instance() async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open([NoteSchema], directory: dir.path);
    return _isar!;
  }
}
