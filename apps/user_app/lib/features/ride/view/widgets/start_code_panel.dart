import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

/// The start code, big and spaced out so it can be read aloud.
class StartCodePanel extends StatelessWidget {
  const StartCodePanel({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Semantics(
      label: 'Start code ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Skyline.s16,
          vertical: Skyline.s12,
        ),
        decoration: BoxDecoration(
          color: t.primary,
          borderRadius: BorderRadius.circular(Skyline.radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start code',
                    style: t.label(size: 13, color: t.onPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share it with your driver when you meet.',
                    style: t.body(
                      size: 12.5,
                      color: t.onPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Skyline.s12),
            Text(
              code.split('').join(' '),
              style: t.figure(28, color: t.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
