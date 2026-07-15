import 'package:flutter/material.dart';

import '../../domain/pickup_location.dart';

/// A tappable past pickup shown when the search field is empty.
///
/// Render-only: shows a saved [location] and reports taps through [onTap].
/// Selecting one reuses its stored coordinates, so it costs no Ola request.
class RecentLocationTile extends StatelessWidget {
  const RecentLocationTile({
    super.key,
    required this.location,
    required this.onTap,
  });

  final PickupLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.history),
      title: Text(
        location.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
