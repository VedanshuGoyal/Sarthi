import 'package:flutter/material.dart';

/// The six items on the post-registration Document View, in the order they
/// unlock — each opens only once the one before it is complete. Their titles
/// for the driver: `DocumentStep.titleIn` / `subtitleIn` in
/// `view/document_labels.dart`.
enum DocumentStep {
  vehicleType(icon: Icons.directions_car_outlined),
  photoAndName(icon: Icons.badge_outlined),
  aadhar(icon: Icons.credit_card_outlined),
  drivingLicense(icon: Icons.motorcycle_outlined),
  permissions(icon: Icons.admin_panel_settings_outlined),
  bankDetails(icon: Icons.account_balance_outlined);

  const DocumentStep({required this.icon});

  final IconData icon;

  /// 1-based position, for the tile's number badge.
  int get number => DocumentStep.values.indexOf(this) + 1;
}
