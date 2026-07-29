import 'package:flutter/material.dart';

/// The customer's avatar: their initials on a filled circle.
///
/// Render-only. Sarthi has no profile photos yet, so initials are the
/// identity mark everywhere — the home app bar and the profile header share
/// this widget so they can never drift apart.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.radius = 20});

  final String name;
  final double radius;

  /// "Vedanshu Goyal" → "VG", "Priya" → "P". Falls back to "?" for a blank
  /// name so the circle never renders empty.
  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(
        initials(name),
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w700),
      ),
    );
  }
}
