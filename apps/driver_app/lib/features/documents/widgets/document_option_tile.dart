import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../domain/document_step.dart';

/// One row on the Document View: a numbered KYC step that is locked, open, or
/// completed. Renders only — [onTap] fires for open/completed rows and is
/// null (row dimmed, untappable) while locked, matching the "open one by one"
/// flow the view model enforces.
class DocumentOptionTile extends StatelessWidget {
  const DocumentOptionTile({
    super.key,
    required this.step,
    required this.isUnlocked,
    required this.isCompleted,
    required this.onTap,
  });

  final DocumentStep step;
  final bool isUnlocked;
  final bool isCompleted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final dimmed = !isUnlocked;

    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isUnlocked ? onTap : null,
          borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          child: Container(
            padding: const EdgeInsets.all(DeepSignalTokens.s14),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(
                color: isCompleted ? t.accentBorder : t.hairline,
              ),
              borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
            ),
            child: Row(
              children: [
                _NumberBadge(step: step, isCompleted: isCompleted, t: t),
                const SizedBox(width: DeepSignalTokens.s14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: t.title(15, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.subtitle,
                        style: t.body(size: 13, color: t.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DeepSignalTokens.s8),
                Icon(
                  dimmed
                      ? Icons.lock_outline
                      : (isCompleted
                            ? Icons.check_circle
                            : Icons.chevron_right),
                  color: isCompleted ? t.accent : t.faint,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({
    required this.step,
    required this.isCompleted,
    required this.t,
  });

  final DocumentStep step;
  final bool isCompleted;
  final DeepSignalTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCompleted ? t.accentAlpha(0.12) : t.raised,
        border: Border.all(color: isCompleted ? t.accentBorder : t.hairline),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
      ),
      child: Icon(
        isCompleted ? Icons.check : step.icon,
        size: 17,
        color: isCompleted ? t.accent : t.fg,
      ),
    );
  }
}
