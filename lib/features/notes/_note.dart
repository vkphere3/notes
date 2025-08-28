class Note {
  final int id; // unique id for this demo (timestamp)
  final String title;
  final String body;
  final List<String> tags; // lowercase #tags (without the #)

  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.tags = const [],
  });
}
