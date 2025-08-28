// lib/features/notes/widgets/empty_state.dart
import 'package:flutter/material.dart';
import '../../../app/ui.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
  });
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.note_alt_outlined, size: 72, color: cs.outline),
              Gaps.h16,
              Text(
                title,
                style: text.titleLarge?.copyWith(letterSpacing: -0.2),
              ),
              Gaps.h8,
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              Gaps.h16,
              action,
            ],
          ),
        ),
      ),
    );
  }
}
