import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/domain/driver.dart';
import '../../auth/driver_auth_controller.dart';
import '../../auth/driver_auth_providers.dart';
import '../../documents/document_providers.dart';
import '../../documents/domain/driver_kyc.dart';
import '../../documents/view/document_view_screen.dart';
import '../../rides/rides_providers.dart';
import '../../rides/view/ride_format.dart';
import '../../rides/view/widgets/ride_widgets.dart';

/// The Account tab: who the driver is, where their verification stands,
/// what they drive, where they're paid, and logging out.
///
/// Everything shown comes from the KYC record the driver filled in during
/// onboarding — this panel reads it, and links back to the documents screen
/// to view or redo a step.
class AccountPanel extends ConsumerStatefulWidget {
  const AccountPanel({super.key, required this.driver});

  final Driver driver;

  @override
  ConsumerState<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends ConsumerState<AccountPanel> {
  bool _loggingOut = false;

  /// Goes off duty, revokes the session server-side (best-effort), then
  /// clears it locally — which returns the app to the start screen.
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          "You'll go off duty and stop getting ride requests on this phone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loggingOut = true);
    await ref.read(dutyViewModelProvider).setOnline(false);
    final auth = ref.read(driverAuthControllerProvider.notifier);
    final token = auth.token;
    if (token != null) {
      try {
        await ref.read(driverAuthRepositoryProvider).logout(token);
      } catch (_) {
        // Clearing locally regardless; a failed revoke mustn't trap the driver.
      }
    }
    await auth.signOut();
  }

  Future<void> _contactSupport() async {
    final ok = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: 'team@mojud.life',
        queryParameters: {'subject': 'Driver app help'},
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write to us at team@mojud.life')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final kyc = ref.watch(documentRegistrationViewModelProvider).kyc;
    final t = SkylineTokens.of(context);
    final driver = widget.driver;
    final name = kyc.fullName.isNotEmpty ? kyc.fullName : driver.name;
    final bank = kyc.bankAccount;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Skyline.s20,
          Skyline.s8,
          Skyline.s20,
          Skyline.s32,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkylineCard(
                    padding: const EdgeInsets.all(Skyline.s20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: t.primary,
                          child: Text(
                            name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: t.heading(24, color: t.onPrimary),
                          ),
                        ),
                        const SizedBox(width: Skyline.s16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: t.title(18)),
                              const SizedBox(height: 2),
                              Text(
                                RideFormat.phone(driver.phoneE164),
                                style: t.body(size: 13.5),
                              ),
                              const SizedBox(height: Skyline.s8),
                              _KycBadge(status: kyc.status),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Skyline.s24),
                  const SectionHeader(title: 'Driving'),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.settings_rounded,
                        title: 'Cars you drive',
                        subtitle: kyc.transmission?.label ?? 'Not set',
                      ),
                      SkylineRow(
                        icon: Icons.badge_rounded,
                        title: 'Driving licence',
                        subtitle: kyc.drivingLicenseNumber ?? 'Not added',
                      ),
                      SkylineRow(
                        icon: Icons.fingerprint_rounded,
                        title: 'Aadhaar',
                        subtitle: kyc.aadhaarLast4 != null
                            ? 'XXXX XXXX ${kyc.aadhaarLast4}'
                            : 'Not added',
                      ),
                      SkylineRow(
                        icon: Icons.folder_open_rounded,
                        title: 'Documents',
                        subtitle: 'View or update what you submitted',
                        accent: true,
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: t.inkFaint,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DocumentViewScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Skyline.s24),
                  const SectionHeader(title: 'Payouts'),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.account_balance_rounded,
                        title: bank == null
                            ? 'No bank account added'
                            : '${bank.accountHolderName} · '
                                  '•••• ${bank.accountNumberLast4}',
                        subtitle: bank?.ifscCode,
                      ),
                    ],
                  ),
                  const SizedBox(height: Skyline.s24),
                  const SectionHeader(title: 'Help'),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.support_agent_rounded,
                        title: 'Contact support',
                        subtitle: 'team@mojud.life',
                        accent: true,
                        onTap: _contactSupport,
                      ),
                    ],
                  ),
                  const SizedBox(height: Skyline.s32),
                  OutlinedButton.icon(
                    onPressed: _loggingOut ? null : _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.danger,
                      side: BorderSide(color: t.danger.withValues(alpha: 0.4)),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A white card holding rows separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s4),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              const Divider(indent: Skyline.s16, endIndent: Skyline.s16),
            row,
          ],
        ],
      ),
    );
  }
}

class _KycBadge extends StatelessWidget {
  const _KycBadge({required this.status});

  final KycStatus status;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final (label, icon, color) = switch (status) {
      KycStatus.verified => (
        'Verified driver',
        Icons.verified_rounded,
        t.success,
      ),
      KycStatus.submitted => (
        'Documents under review',
        Icons.hourglass_top_rounded,
        t.primaryText,
      ),
      KycStatus.rejected => (
        'Documents need attention',
        Icons.error_outline_rounded,
        t.danger,
      ),
      KycStatus.incomplete => (
        'Documents incomplete',
        Icons.pending_outlined,
        t.inkMuted,
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: t.label(size: 12.5, color: color)),
        ),
      ],
    );
  }
}
