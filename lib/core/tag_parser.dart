final tagRegex = RegExp(r'(?:^|\s)#([A-Za-z0-9_\-]+)');
List<String> extractTags(String text) {
  final s = <String>{};
  for (final m in tagRegex.allMatches(text)) {
    s.add(m.group(1)!.toLowerCase());
  }
  final list = s.toList();
  list.sort();
  return list;
}
