import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

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
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return Semantics(
        label: '$stars out of 5 stars',
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
            tooltip: '$n ${n == 1 ? 'star' : 'stars'}',
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

  static const _words = ['', 'Poor', 'Not great', 'Okay', 'Good', 'Excellent'];

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: StarRow(stars: stars, onChanged: onStars, size: 36),
        ),
        SizedBox(
          height: 20,
          child: Center(
            child: Text(
              _words[stars.clamp(0, 5)],
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
          decoration: const InputDecoration(
            hintText: 'Add a note for your driver (optional)',
            counterText: '',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: Skyline.s8),
          Text(error, style: t.body(size: 13, color: t.danger)),
        ],
        const SizedBox(height: Skyline.s12),
        SarthiPrimaryButton(
          label: 'Submit rating',
          isLoading: isSubmitting,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}
