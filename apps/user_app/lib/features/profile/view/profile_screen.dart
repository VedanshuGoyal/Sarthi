import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              children: [
                Center(child: UserAvatar(name: user.name, radius: 40)),
                const SizedBox(height: 16),
                Text(
                  user.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                _DetailTile(
                  icon: Icons.phone_outlined,
                  label: 'Mobile number',
                  value: _formatPhone(user.phoneE164),
                ),
                _DetailTile(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: user.email,
                ),
                _DetailTile(
                  icon: Icons.cake_outlined,
                  label: 'Date of birth',
                  value: _formatDate(user.dateOfBirth),
                ),
                const SizedBox(height: 24),
                const SavedCarsSection(),
                if (onLogout != null) ...[
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

/// One read-only profile fact: a leading icon, a muted label, and the value.
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
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(value, style: theme.textTheme.bodyLarge),
    );
  }
}
