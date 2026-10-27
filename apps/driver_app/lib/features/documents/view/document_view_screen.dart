import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../core/services/push_service.dart';
import '../../notifications/notification_providers.dart';
import '../document_providers.dart';
import '../domain/document_step.dart';
import '../domain/driver_kyc.dart';
import '../widgets/document_option_tile.dart';
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
  /// The push type the backend sends when a reviewer decides.
  static const String _kycDecided = 'kyc_decided';

  final List<StreamSubscription<void>> _push = [];
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // A reviewer's decision arrives as a push; reloading then is what moves a
    // newly verified driver on to Home (the gate watches the status).
    final push = ref.read(pushServiceProvider);
    void onPush(PushEvent event) {
      if (event.type == _kycDecided) _reload();
    }

    _push
      ..add(push.arrivals.listen(onPush))
      ..add(push.taps.listen(onPush));
    _lifecycle = AppLifecycleListener(onResume: _reloadIfWaiting);
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

  /// Coming back to the app while under review: the decision may have landed
  /// without a push (notifications off).
  void _reloadIfWaiting() {
    final vm = ref.read(documentRegistrationViewModelProvider);
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

    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final status = vm.kyc.status;
    final underReview = status == KycStatus.submitted;
    final rejected = status == KycStatus.rejected;
    final note = vm.kyc.reviewNote;

    return SarthiFormScaffold(
      title: switch (status) {
        KycStatus.submitted => 'Under review',
        KycStatus.rejected => 'Some details need fixing',
        _ => 'Complete your registration',
      },
      subtitle: switch (status) {
        KycStatus.submitted =>
          "We're checking your details. You can go online once they're "
              'cleared.',
        KycStatus.rejected => 'Fix the details below and submit again.',
        _ =>
          'Finish these ${DocumentStep.values.length} steps to start '
              'accepting rides. Each one unlocks once the last is done.',
      },
      fields: [
        if (note != null && (underReview || rejected)) ...[
          _ReviewNote(note: note, attention: rejected),
          const SizedBox(height: DeepSignalTokens.s22),
        ],
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
      ],
      // Nothing to submit until all six are done, and nothing to submit twice;
      // while under review, the driver can ask again whether they're cleared.
      footer: underReview
          ? SarthiPrimaryButton(label: 'Check again', onPressed: vm.load)
          : vm.isAllComplete
          ? SarthiPrimaryButton(
              label: vm.isSaving ? 'Submitting…' : 'Submit for verification',
              onPressed: vm.isSaving ? null : _submit,
            )
          : null,
    );
  }
}

/// Why the driver is under review, or what a reviewer refused.
class _ReviewNote extends StatelessWidget {
  const _ReviewNote({required this.note, required this.attention});

  final String note;

  /// Rejected rather than waiting: drawn in red.
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    final color = attention ? Colors.red : t.muted;
    return Container(
      padding: const EdgeInsets.all(DeepSignalTokens.s14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: attention ? Colors.red : t.hairline),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            attention ? Icons.error_outline_rounded : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: DeepSignalTokens.s14),
          Expanded(
            child: Text(note, style: t.body(size: 13, color: t.fg)),
          ),
        ],
      ),
    );
  }
}
