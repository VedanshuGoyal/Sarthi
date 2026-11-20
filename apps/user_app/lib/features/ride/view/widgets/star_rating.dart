import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/my_booking.dart';

/// Five stars, the first [stars] filled. Tappable when [onChanged] is given
/// (each star picks its count); otherwise a read-only "You rated ★★★★☆".
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.stars,
    this.onChanged,
    this.size = 20,
  });

  final int stars;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return Semantics(
        label: l10n.starsOutOfFive(stars),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var n = 1; n <= 5; n++)
              Icon(
                n <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: n <= stars ? t.signal : t.outline,
              ),
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          IconButton(
            tooltip: l10n.starsCount(n),
            onPressed: () => onChanged(n),
            isSelected: n <= stars,
            iconSize: size,
            color: t.outline,
            selectedIcon: Icon(Icons.star_rounded, color: t.signal),
            icon: const Icon(Icons.star_outline_rounded),
          ),
      ],
    );
  }
}

/// "How was your trip?": the stars, an optional note and Submit. State-free:
/// the view model owns the picks and the request.
class RatingForm extends StatelessWidget {
  const RatingForm({
    super.key,
    required this.stars,
    required this.onStars,
    required this.onNoteChanged,
    required this.onSubmit,
    this.initialNote = '',
    this.isSubmitting = false,
    this.error,
  });

  final int stars;
  final ValueChanged<int> onStars;
  final String initialNote;
  final ValueChanged<String> onNoteChanged;

  /// Null keeps Submit disabled (no stars yet).
  final VoidCallback? onSubmit;
  final bool isSubmitting;
  final String? error;

  /// The word under the stars for each count, none for 0.
  static String _word(AppLocalizations l10n, int stars) => switch (stars) {
    1 => l10n.starsWordPoor,
    2 => l10n.starsWordNotGreat,
    3 => l10n.starsWordOkay,
    4 => l10n.starsWordGood,
    5 => l10n.starsWordExcellent,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          // Five 36-px star buttons are wider than a 320-dp phone's card:
          // shrink them to fit there, full size anywhere wider.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: StarRow(stars: stars, onChanged: onStars, size: 36),
          ),
        ),
        SizedBox(
          height: 20,
          child: Center(
            child: Text(
              _word(l10n, stars.clamp(0, 5)),
              style: t.label(color: t.primaryText),
            ),
          ),
        ),
        const SizedBox(height: Skyline.s12),
        TextFormField(
          initialValue: initialNote,
          onChanged: onNoteChanged,
          maxLength: maxRatingNoteLength,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: l10n.starsNoteHint,
            counterText: '',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Skyline.s8),
          Text(error, style: t.body(size: 13, color: t.danger)),
        ],
        const SizedBox(height: Skyline.s12),
        SarthiPrimaryButton(
          label: l10n.starsSubmit,
          isLoading: isSubmitting,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}
