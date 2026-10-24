import 'package:flutter/material.dart';

import '../../domain/place_suggestion.dart';
import '../../../../core/theme/skyline/skyline_row.dart';

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
    return SkylineRow(
      icon: Icons.place_rounded,
      title: suggestion.primaryText,
      subtitle: suggestion.secondaryText,
      onTap: onTap,
    );
  }
}
