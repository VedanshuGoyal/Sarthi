import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../document_providers.dart';
import '../domain/document_validators.dart';
import '../domain/driver_kyc.dart';
import '../widgets/verified_details.dart';

/// Document step 4 — the driving licence number, looked up against the
/// transport department's records with the driver's date of birth.
class DrivingLicenseStep extends ConsumerStatefulWidget {
  const DrivingLicenseStep({super.key});

  @override
  ConsumerState<DrivingLicenseStep> createState() => _DrivingLicenseStepState();
}

class _DrivingLicenseStepState extends ConsumerState<DrivingLicenseStep> {
  final TextEditingController _number = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _number.text =
        ref
            .read(documentRegistrationViewModelProvider)
            .kyc
            .drivingLicenseNumber ??
        '';
    // The footer flips between "Verify" and "Continue" as the number changes.
    _number.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  /// Whether what's in the field is the number the backend verified.
  bool _showsVerified(DriverKyc kyc) =>
      kyc.isLicenseVerified &&
      _normalised(_number.text) == kyc.drivingLicenseNumber;

  static String _normalised(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  Future<void> _verify() async {
    final numberError = DocumentValidators.drivingLicenseNumber(_number.text);
    if (numberError != null) {
      setState(() => _error = numberError);
      return;
    }

    setState(() => _error = null);
    final vm = ref.read(documentRegistrationViewModelProvider);
    final verified = await vm.verifyDrivingLicense(_normalised(_number.text));
    if (!mounted) return;
    if (!verified) setState(() => _error = vm.error);
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final kyc = vm.kyc;
    final verified = _showsVerified(kyc);
    final validUntil = kyc.licenseValidUntil;
    final l10n = context.l10n;

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: l10n.licenseStepTitle,
      subtitle: l10n.licenseStepSubtitle,
      fields: [
        SarthiTextField(
          label: l10n.licenseStepNumberLabel,
          controller: _number,
          hintText: l10n.licenseStepNumberHint,
          textCapitalization: TextCapitalization.characters,
          prefixIcon: const Icon(Icons.motorcycle_outlined),
        ),
        if (verified) ...[
          const SizedBox(height: DeepSignalTokens.s14),
          VerifiedDetails(
            title: l10n.licenseStepVerifiedTitle,
            lines: [
              kyc.licenseName ?? '',
              if (validUntil != null)
                l10n.licenseStepValidTill(formatCardDate(validUntil, l10n)),
              if (kyc.licenseClasses.isNotEmpty)
                l10n.licenseStepCovers(kyc.licenseClasses.join(' · ')),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(_error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: verified
          ? SarthiPrimaryButton(
              label: l10n.commonContinue,
              onPressed: () => Navigator.of(context).pop(),
            )
          : SarthiPrimaryButton(
              label: vm.isSaving
                  ? l10n.licenseStepChecking
                  : l10n.licenseStepVerify,
              onPressed: vm.isSaving ? null : _verify,
            ),
    );
  }
}
