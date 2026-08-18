import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

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
/// signed-in driver until their documents are in (see main.dart).
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
  @override
  void initState() {
    super.initState();
    // Deferred: providers can't be written to during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(documentRegistrationViewModelProvider).load();
    });
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

    final underReview = vm.kyc.status == KycStatus.submitted;

    return SarthiFormScaffold(
      title: underReview ? 'Documents submitted' : 'Complete your registration',
      subtitle: underReview
          ? "We're checking your documents. This usually takes a day — "
                "you'll be able to go online as soon as they clear."
          : "Finish these ${DocumentStep.values.length} steps to start "
                'accepting rides. Each one unlocks once the last is done.',
      fields: [
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
      // Nothing to submit until all six are done, and nothing to submit twice.
      footer: vm.isAllComplete && !underReview
          ? SarthiPrimaryButton(
              label: vm.isSaving ? 'Submitting…' : 'Submit for verification',
              onPressed: vm.isSaving ? null : _submit,
            )
          : null,
    );
  }
}
