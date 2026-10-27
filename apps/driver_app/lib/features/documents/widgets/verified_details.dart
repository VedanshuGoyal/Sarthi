import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// A green-ticked card naming who checked a detail and what they confirmed,
/// e.g. "Verified with DigiLocker" over the name and date of birth.
class VerifiedDetails extends StatelessWidget {
  const VerifiedDetails({
    super.key,
    required this.title,
    this.lines = const [],
  });

  final String title;

  /// One row each, already formatted; empty ones are skipped.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final green = Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.all(DeepSignalTokens.s14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: green.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_rounded, color: green, size: 22),
          const SizedBox(width: DeepSignalTokens.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.body(size: 14, color: green)),
                for (final line in lines)
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(line, style: t.body(size: 13)),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats a date the way the verification cards show it: `2 Mar 1995`.
String formatCardDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
