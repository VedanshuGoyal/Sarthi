import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../core/services/push_service.dart';
import '../../account/sign_out.dart';
import '../../account/view/delete_account_button.dart';
import '../../notifications/notification_providers.dart';
import '../document_providers.dart';
import '../domain/document_step.dart';
import '../domain/driver_kyc.dart';
import '../widgets/document_option_tile.dart';
import '../widgets/kyc_status_banner.dart';
import '../widgets/verified_details.dart' show formatCardDate;
import 'aadhar_step.dart';
import 'bank_details_step.dart';
import 'driving_license_step.dart';
import 'permissions_step.dart';
import 'photo_and_name_step.dart';
import 'vehicle_type_step.dart';

/// The post-registration document flow: six KYC steps the driver completes
/// one at a time before reaching Home. `_AppRoot` shows this screen for any
/// signed-in driver until they're verified (see main.dart) — including while
/// a person reviews them, or after a reviewer sent something back.
///
/// Each step saves to the backend as it's finished, so progress here is the
/// backend's answer, not the app's — reinstalling or switching phones picks up
/// exactly where the driver left off.
class DocumentViewScreen extends ConsumerStatefulWidget {
  const DocumentViewScreen({super.key});

  @override
  ConsumerState<DocumentViewScreen> createState() => _DocumentViewScreenState();
}

class _DocumentViewScreenState extends ConsumerState<DocumentViewScreen> {
  final List<StreamSubscription<void>> _push = [];
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // A reviewer's decision arrives as a push; reloading then is what moves a
    // newly verified driver on to Home (the gate watches the status).
    final push = ref.read(pushServiceProvider);
    // A bank account change reopens KYC.
    void onPush(PushEvent event) {
      if (event.kind == PushType.kycDecided ||
          event.kind == PushType.bankAccountChanged) {
        _reload();
      }
    }

    _push
      ..add(push.arrivals.listen(onPush))
      ..add(push.taps.listen(onPush));
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    // Deferred: providers can't be written to during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentRegistrationViewModelProvider).load();
      // Registered now, not only on Home, so the decision can reach drivers
      // who are still waiting on it.
      unawaited(ref.read(pushRegistrationProvider).start());
    });
  }

  @override
  void dispose() {
    for (final sub in _push) {
      sub.cancel();
    }
    _lifecycle.dispose();
    super.dispose();
  }

  void _reload() => ref.read(documentRegistrationViewModelProvider).load();

  /// Coming back to the app — often from system settings, where the
  /// permissions may just have been turned on — re-reads the OS grants. And
  /// while under review the decision may have landed without a push
  /// (notifications off).
  void _onResume() {
    final vm = ref.read(documentRegistrationViewModelProvider);
    unawaited(vm.refreshPermissionGrants());
    if (vm.kyc.status == KycStatus.submitted && !vm.isLoading) _reload();
  }

  Future<void> _submit() async {
    final vm = ref.read(documentRegistrationViewModelProvider);
    final submitted = await vm.submit();
    if (!mounted || submitted) return;

    // The backend re-checks every step and names what's missing, which is more
    // useful than the button silently doing nothing.
    final message = vm.error;
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Lets a driver who can't get past this screen — a wrong number, a
  /// revoked session — sign out; Log out otherwise lives on Home.
  Future<void> _logOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You can sign in again with your phone number. The steps you have '
          'finished stay saved.',
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
    if (confirmed != true || !mounted) return;
    await signOutDriver(ref);
  }

  void _open(DocumentStep step) {
    final screen = switch (step) {
      DocumentStep.vehicleType => const VehicleTypeStep(),
      DocumentStep.photoAndName => const PhotoAndNameStep(),
      DocumentStep.aadhar => const AadharStep(),
      DocumentStep.drivingLicense => const DrivingLicenseStep(),
      DocumentStep.permissions => const PermissionsStep(),
      DocumentStep.bankDetails => const BankDetailsStep(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);

    // Only the first answer is waited for; a reload (Check again, a push,
    // coming back to the app) refreshes what's already on screen.
    if (vm.isLoading && !vm.hasKyc) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Never heard from the backend: there is nothing to show but a way on.
    if (vm.loadFailed) {
      return SarthiFormScaffold(
        title: "Couldn't load your registration",
        subtitle: vm.error,
        fields: const [],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SarthiPrimaryButton(label: 'Try again', onPressed: _reload),
            const SizedBox(height: DeepSignalTokens.s8),
            TextButton(onPressed: _logOut, child: const Text('Log out')),
          ],
        ),
      );
    }

    final kyc = vm.kyc;
    final status = kyc.status;
    final verified = status == KycStatus.verified;
    // Waiting on someone else: nothing to submit, only to ask again.
    final waiting =
        status == KycStatus.submitted || status == KycStatus.unknown;
    final (bannerTitle, bannerLines) = _banner(kyc);

    return SarthiFormScaffold(
      title: switch (status) {
        KycStatus.verified => "You're verified",
        KycStatus.submitted => 'Under review',
        KycStatus.rejected => 'Some details need fixing',
        KycStatus.unknown => "We can't show your status",
        KycStatus.incomplete => 'Complete your registration',
      },
      subtitle: switch (status) {
        KycStatus.verified =>
          "You're cleared to take rides. Open any step to see what you "
              'sent, or to change it.',
        KycStatus.submitted =>
          "We're checking your details. You can go online once they're "
              'cleared.',
        KycStatus.rejected => 'Fix the details below and submit again.',
        KycStatus.unknown =>
          "Your account has a status this version of the app doesn't "
              "know, so you can't take rides yet.",
        KycStatus.incomplete =>
          'Finish these ${DocumentStep.values.length} steps to start '
              'accepting rides. Each one unlocks once the last is done.',
      },
      fields: [
        if (status != KycStatus.incomplete) ...[
          KycStatusBanner(
            status: status,
            title: bannerTitle,
            lines: bannerLines,
          ),
          const SizedBox(height: DeepSignalTokens.s22),
        ],
        // A to-do count means nothing to a driver who is already cleared.
        if (!verified) ...[
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
                  child: LinearProgressIndicator(
                    value: vm.completedCount / DocumentStep.values.length,
                    minHeight: 6,
                    backgroundColor: t.hairline,
                    color: t.accent,
                  ),
                ),
              ),
              const SizedBox(width: DeepSignalTokens.s8),
              Text(
                '${vm.completedCount}/${DocumentStep.values.length}',
                style: t.mono(size: 12, color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: DeepSignalTokens.s22),
        ],
        for (final step in DocumentStep.values) ...[
          DocumentOptionTile(
            step: step,
            isUnlocked: vm.isUnlocked(step),
            isCompleted: vm.isComplete(step),
            onTap: () => _open(step),
          ),
          if (step != DocumentStep.values.last)
            const SizedBox(height: DeepSignalTokens.s8),
        ],
        if (vm.error != null && !vm.isSaving) ...[
          const SizedBox(height: DeepSignalTokens.s14),
          Text(vm.error!, style: t.body(size: 13, color: Colors.red)),
        ],
        // Shown where this screen is the gate. A verified driver reaches it
        // from Account, which has its own Log out and Delete account.
        if (!vm.isVerified) ...[
          const SizedBox(height: DeepSignalTokens.s14),
          Center(
            child: TextButton.icon(
              onPressed: _logOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Log out'),
            ),
          ),
          const SizedBox(height: DeepSignalTokens.s22),
          const DeleteAccountButton(),
        ],
      ],
      // A cleared driver has nothing to submit. One waiting on a reviewer
      // (or with a status this build doesn't know) can ask again; anyone
      // else submits once all six are done, and never twice.
      footer: verified
          ? null
          : waiting
          ? SarthiPrimaryButton(
              label: vm.isLoading ? 'Checking…' : 'Check again',
              onPressed: vm.isLoading ? null : _reload,
            )
          : vm.isAllComplete
          ? SarthiPrimaryButton(
              label: vm.isSaving ? 'Submitting…' : 'Submit for verification',
              onPressed: vm.isSaving ? null : _submit,
            )
          : null,
    );
  }

  /// The status card's headline and rows: what was checked once cleared,
  /// the reviewer's note and when the details went in while waiting or
  /// sent back.
  static (String, List<String>) _banner(DriverKyc kyc) {
    final note = kyc.reviewNote;
    final sent = kyc.submittedAt;
    return switch (kyc.status) {
      KycStatus.verified => (
        'Cleared to drive',
        [
          if (kyc.isAadhaarVerified)
            kyc.aadhaarLast4 == null
                ? 'Aadhaar verified with DigiLocker'
                : 'Aadhaar XXXX XXXX ${kyc.aadhaarLast4} · verified with '
                      'DigiLocker',
          if (kyc.isLicenseVerified)
            kyc.drivingLicenseNumber == null
                ? 'Driving licence verified'
                : 'Driving licence ${kyc.drivingLicenseNumber} · verified',
          if (kyc.bankAccount case final bank? when bank.isVerified)
            'Bank account •••• ${bank.accountNumberLast4} · verified with '
                'your bank',
        ],
      ),
      KycStatus.submitted => (
        'Waiting on a reviewer',
        [?note, if (sent != null) 'Sent ${formatCardDate(sent.toLocal())}'],
      ),
      KycStatus.rejected => (
        'Sent back by a reviewer',
        [note ?? 'Open the steps below to see what to change.'],
      ),
      KycStatus.unknown => (
        'Status not recognised',
        ['Update the app, or write to team@mojud.life if this stays.'],
      ),
      KycStatus.incomplete => ('', const []),
    };
  }
}
