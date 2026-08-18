import 'package:flutter/material.dart';

/// The six items on the post-registration Document View, in the order they
/// unlock — each opens only once the one before it is complete.
enum DocumentStep {
  vehicleType(
    title: 'Type of Vehicle',
    subtitle: 'Manual, automatic, or both',
    icon: Icons.directions_car_outlined,
  ),
  photoAndName(
    title: 'Photo and Name',
    subtitle: 'Selfie, full name, date of birth, gender',
    icon: Icons.badge_outlined,
  ),
  aadhar(
    title: 'Aadhar Card',
    subtitle: 'Aadhar number and photo',
    icon: Icons.credit_card_outlined,
  ),
  drivingLicense(
    title: 'Driving License',
    subtitle: 'License number and photo',
    icon: Icons.motorcycle_outlined,
  ),
  permissions(
    title: 'Permissions',
    subtitle: 'Display over other apps, background location, battery usage',
    icon: Icons.admin_panel_settings_outlined,
  ),
  bankDetails(
    title: 'Bank Details',
    subtitle: 'Where your earnings get paid out',
    icon: Icons.account_balance_outlined,
  );

  const DocumentStep({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// 1-based position, for the tile's number badge.
  int get number => DocumentStep.values.indexOf(this) + 1;
}
