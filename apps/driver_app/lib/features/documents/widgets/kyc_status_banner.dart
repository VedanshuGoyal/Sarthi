import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/driver_kyc.dart';

/// Where the driver's verification stands, as a card at the top of the
/// Document View: a green tick once cleared, an hourglass while a person
/// reviews, red when something was sent back, a question mark for a status
/// this build doesn't know. Renders only — the screen supplies the words.
///
/// Nothing is drawn for [KycStatus.incomplete]: the steps below say what's
/// left.
class KycStatusBanner extends StatelessWidget {
  const KycStatusBanner({
    super.key,
    required this.status,
    required this.title,
    this.lines = const [],
  });

  final KycStatus status;
  final String title;

  /// One row each, already formatted — the checks that passed, the
  /// reviewer's note, when it was sent. Empty ones are skipped.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final (IconData icon, Color color)? look = switch (status) {
      KycStatus.verified => (Icons.verified_rounded, Colors.green.shade700),
      KycStatus.submitted => (Icons.hourglass_top_rounded, t.accent),
      KycStatus.rejected => (Icons.error_outline_rounded, Colors.red),
      KycStatus.unknown => (Icons.help_outline_rounded, t.muted),
      KycStatus.incomplete => null,
    };
    if (look == null) return const SizedBox.shrink();
    final (icon, color) = look;

    return Semantics(
      container: true,
      label: title,
      child: Container(
        padding: const EdgeInsets.all(DeepSignalTokens.s14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: DeepSignalTokens.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.title(15, weight: FontWeight.w600, color: color),
                  ),
                  for (final line in lines)
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: DeepSignalTokens.s4),
                      Text(line, style: t.body(size: 13, color: t.fg)),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
