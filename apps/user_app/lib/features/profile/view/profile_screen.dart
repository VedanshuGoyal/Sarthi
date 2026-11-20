import 'package:flutter/material.dart';

import 'package:sarthi_shared/sarthi_shared.dart';
import '../../../l10n/l10n.dart';
import '../../auth/domain/auth_user.dart';
import '../../language/view/language_switch.dart';
import 'widgets/delete_account_button.dart';
import 'widgets/saved_cars_section.dart';
import 'widgets/user_avatar.dart';

/// The customer's account page: who Sarthi thinks they are, their saved cars,
/// the app's language (English / हिंदी), plus the way out.
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
  /// e.g. in previews, where there is no session to end — and so does
  /// "Delete account", which manages itself through its view model.
  final VoidCallback? onLogout;

  /// Formats a date as `12 Jan 2000` (`12 जनवरी 2000`) without pulling in
  /// `intl` (same style the registration flow shows for the date of birth).
  static String _formatDate(AppLocalizations l10n, DateTime d) =>
      l10n.fmtDateWithYear(d.day, l10n.monthShort(d.month), d.year);

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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountYourProfile)),
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
                        label: l10n.authMobileNumberLabel,
                        value: _formatPhone(user.phoneE164),
                      ),
                      _DetailTile(
                        icon: Icons.mail_rounded,
                        label: l10n.authEmail,
                        value: user.email,
                      ),
                      _DetailTile(
                        icon: Icons.cake_rounded,
                        label: l10n.authDateOfBirth,
                        value: _formatDate(l10n, user.dateOfBirth),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Skyline.s16),
                const SkylineCard(
                  padding: EdgeInsets.all(Skyline.s16),
                  child: SavedCarsSection(),
                ),
                const SizedBox(height: Skyline.s16),
                // English / हिंदी, saved on this phone.
                const LanguageSwitch(),
                if (onLogout != null) ...[
                  const SizedBox(height: Skyline.s24),
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(l10n.accountLogOut),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.danger,
                      side: BorderSide(color: t.danger.withValues(alpha: 0.35)),
                    ),
                  ),
                  const SizedBox(height: Skyline.s8),
                  const DeleteAccountButton(),
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
