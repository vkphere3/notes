import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../notes/notes_providers.dart';

class TagStrip extends ConsumerWidget {
  const TagStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagCountsProvider);
    final active = ref.watch(activeTagProvider);

    if (tags.isEmpty) {
      return const SizedBox(height: 0);
    }

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: tags.length + 1, // +1 for the All chip
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            final isAll = active == null;
            return ChoiceChip(
              label: const Text('All'),
              selected: isAll,
              onSelected: (_) {
                ref.read(activeTagProvider.notifier).state = null;
                ref.read(queryProvider.notifier).state = '';
              },
            );
          }
          final t = tags[i - 1];
          final selected = active == t.tag;
          return ChoiceChip(
            label: Text('#${t.tag} (${t.count})'),
            selected: selected,
            onSelected: (_) {
              // toggle behavior
              final next = selected ? null : t.tag;
              ref.read(activeTagProvider.notifier).state = next;
              // clear text query when picking a chip, to avoid mixed filters
              ref.read(queryProvider.notifier).state = '';
            },
          );
        },
      ),
    );
  }
}
