import 'package:flutter/material.dart';

import '../../domain/place_suggestion.dart';

/// One tappable search result in the pickup list.
///
/// Render-only per the reusable-widget guideline: it shows a [suggestion] and
/// reports taps through [onTap] — it holds no state and makes no calls.
class PickupSuggestionTile extends StatelessWidget {
  const PickupSuggestionTile({
    super.key,
    required this.suggestion,
    required this.onTap,
  });

  final PlaceSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.location_on_outlined),
      title: Text(
        suggestion.primaryText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: suggestion.secondaryText.isEmpty
          ? null
          : Text(
              suggestion.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}
