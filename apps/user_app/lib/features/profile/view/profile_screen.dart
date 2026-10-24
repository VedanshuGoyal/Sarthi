import 'package:flutter/material.dart';

import '../../../core/theme/skyline/skyline_row.dart';
import '../../../core/theme/skyline/skyline_tokens.dart';
import '../../auth/domain/auth_user.dart';
import 'widgets/saved_cars_section.dart';
import 'widgets/user_avatar.dart';

/// The customer's account page: who Sarthi thinks they are, their saved cars,
/// plus the way out.
///
/// It displays the [AuthUser] it is given and emits [onLogout] — the owner
/// handles session teardown and navigation. The saved-cars block manages
/// itself through the shared saved-cars view model. Editing profile details is
/// a later feature; today those fields are read-only. Body is width-capped and
/// centred on large screens per the responsive guide.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.user, this.onLogout});

  final AuthUser user;

  /// Invoked when the customer taps "Log out". When null the button hides —
  /// e.g. in previews, where there is no session to end.
  final VoidCallback? onLogout;

  /// Formats a date as `12 Jan 2000` without pulling in `intl` (same style the
  /// registration flow shows for the date of birth).
  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Spaces an Indian number as `+91 98765 43210`; anything else (short test
  /// fixtures, foreign formats) is shown untouched.
  static String _formatPhone(String e164) {
    if (e164.startsWith('+91') && e164.length == 13) {
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = SkylineTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Skyline.s20,
                Skyline.s8,
                Skyline.s20,
                Skyline.s32,
              ),
              children: [
                // Identity header: avatar and name on a soft blue band.
                Container(
                  padding: const EdgeInsets.symmetric(vertical: Skyline.s24),
                  decoration: BoxDecoration(
                    color: t.isDark ? t.surface : t.primarySoft,
                    borderRadius: BorderRadius.circular(Skyline.radiusLg),
                  ),
                  child: Column(
                    children: [
                      UserAvatar(name: user.name, radius: 40),
                      const SizedBox(height: Skyline.s12),
                      Text(
                        user.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Skyline.s16),
                SkylineCard(
                  child: Column(
                    children: [
                      _DetailTile(
                        icon: Icons.phone_rounded,
                        label: 'Mobile number',
                        value: _formatPhone(user.phoneE164),
                      ),
                      _DetailTile(
                        icon: Icons.mail_rounded,
                        label: 'Email',
                        value: user.email,
                      ),
                      _DetailTile(
                        icon: Icons.cake_rounded,
                        label: 'Date of birth',
                        value: _formatDate(user.dateOfBirth),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Skyline.s16),
                const SkylineCard(
                  padding: EdgeInsets.all(Skyline.s16),
                  child: SavedCarsSection(),
                ),
                if (onLogout != null) ...[
                  const SizedBox(height: Skyline.s24),
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.danger,
                      side: BorderSide(color: t.danger.withValues(alpha: 0.35)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(Skyline.s8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.primarySoft,
              borderRadius: BorderRadius.circular(Skyline.radiusSm),
            ),
            child: Icon(icon, size: 20, color: t.primaryText),
          ),
          const SizedBox(width: Skyline.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.label(size: 12)),
                const SizedBox(height: 2),
                Text(value, style: t.title(15, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
