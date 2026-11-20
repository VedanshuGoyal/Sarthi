import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/l10n.dart';
import '../../auth/domain/driver.dart';
import '../../documents/document_providers.dart';
import '../../documents/domain/driver_kyc.dart';
import '../../documents/view/document_labels.dart';
import '../../documents/view/document_view_screen.dart';
import '../../language/view/language_switch.dart';
import '../sign_out.dart';
import '../../rides/rides_providers.dart';
import '../../rides/view/ride_format.dart';
import '../../rides/view/widgets/ride_widgets.dart';
import 'delete_account_button.dart';

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

  /// Goes off duty, stops this phone's ride notifications and revokes the
  /// session server-side (both best-effort), then clears it locally — which
  /// returns the app to the start screen.
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.accountLogOutConfirmTitle),
        content: Text(context.l10n.accountLogOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.accountLogOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loggingOut = true);
    await ref.read(dutyViewModelProvider).setOnline(false);
    await signOutDriver(ref);
  }

  static const String _supportEmail = 'team@mojud.life';

  Future<void> _contactSupport() async {
    final l10n = context.l10n;
    final ok = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: _supportEmail,
        queryParameters: {'subject': l10n.accountSupportEmailSubject},
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountWriteToUs(_supportEmail))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final kyc = ref.watch(documentRegistrationViewModelProvider).kyc;
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final driver = widget.driver;
    final name = kyc.fullName.isNotEmpty ? kyc.fullName : driver.name;
    final bank = kyc.bankAccount;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
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
                  SectionHeader(title: l10n.accountSectionDriving),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.settings_rounded,
                        title: l10n.accountCarsYouDrive,
                        subtitle:
                            kyc.transmission?.labelIn(l10n) ??
                            l10n.commonNotSet,
                      ),
                      SkylineRow(
                        icon: Icons.badge_rounded,
                        title: l10n.accountDrivingLicence,
                        subtitle:
                            kyc.drivingLicenseNumber ?? l10n.commonNotAdded,
                      ),
                      SkylineRow(
                        icon: Icons.fingerprint_rounded,
                        title: l10n.accountAadhaar,
                        subtitle: switch (kyc.aadhaarLast4) {
                          final last4? => l10n.accountAadhaarMasked(last4),
                          null => l10n.commonNotAdded,
                        },
                      ),
                      SkylineRow(
                        icon: Icons.folder_open_rounded,
                        title: l10n.accountDocuments,
                        subtitle: l10n.accountDocumentsSubtitle,
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
                  SectionHeader(title: l10n.accountSectionPayouts),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.account_balance_rounded,
                        title: bank == null
                            ? l10n.accountNoBankAccount
                            : l10n.accountBankAccount(
                                bank.accountHolderName,
                                bank.accountNumberLast4,
                              ),
                        subtitle: bank?.ifscCode,
                      ),
                    ],
                  ),
                  const SizedBox(height: Skyline.s24),
                  SectionHeader(title: l10n.languageTitle),
                  const LanguageSwitch(),
                  const SizedBox(height: Skyline.s24),
                  SectionHeader(title: l10n.accountSectionHelp),
                  _Group(
                    rows: [
                      SkylineRow(
                        icon: Icons.support_agent_rounded,
                        title: l10n.accountContactSupport,
                        subtitle: _supportEmail,
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
                    label: Text(l10n.accountLogOut),
                  ),
                  const SizedBox(height: Skyline.s8),
                  const DeleteAccountButton(),
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
    final l10n = context.l10n;
    final (label, icon, color) = switch (status) {
      KycStatus.verified => (
        l10n.accountKycVerified,
        Icons.verified_rounded,
        t.success,
      ),
      KycStatus.submitted => (
        l10n.accountKycSubmitted,
        Icons.hourglass_top_rounded,
        t.primaryText,
      ),
      KycStatus.rejected => (
        l10n.accountKycRejected,
        Icons.error_outline_rounded,
        t.danger,
      ),
      KycStatus.incomplete => (
        l10n.accountKycIncomplete,
        Icons.pending_outlined,
        t.inkMuted,
      ),
      KycStatus.unknown => (
        l10n.accountKycUnknown,
        Icons.help_outline_rounded,
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
