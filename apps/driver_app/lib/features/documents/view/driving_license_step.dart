import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../document_providers.dart';
import '../domain/document_kind.dart';
import '../domain/document_validators.dart';
import '../widgets/document_photo_picker.dart';

/// Document step 4 — driving license number and a photo of the card.
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
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _onPhotoTaken(String path) async {
    setState(() => _error = null);
    await ref
        .read(documentRegistrationViewModelProvider)
        .capturePhoto(DocumentKind.drivingLicense, path);
  }

  Future<void> _submit() async {
    final vm = ref.read(documentRegistrationViewModelProvider);

    final numberError = DocumentValidators.drivingLicenseNumber(_number.text);
    if (numberError != null) {
      setState(() => _error = numberError);
      return;
    }
    if (!vm.kyc.hasUploaded(DocumentKind.drivingLicense)) {
      setState(() => _error = 'Take a photo of your driving license');
      return;
    }

    await vm.setDrivingLicense(number: _number.text);
    if (vm.error != null) {
      setState(() => _error = vm.error);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Driving license',
      subtitle: 'Your license number and a clear photo of the card.',
      fields: [
        SarthiTextField(
          label: 'License number',
          controller: _number,
          hintText: 'License number',
          textCapitalization: TextCapitalization.characters,
          prefixIcon: const Icon(Icons.motorcycle_outlined),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        DocumentPhotoPicker(
          photoPath: vm.data.capturePathFor(DocumentKind.drivingLicense),
          uploadState: vm.data.uploadStateFor(DocumentKind.drivingLicense),
          onPhotoTaken: _onPhotoTaken,
          label: 'Take a photo of your driving license',
        ),
        if (_error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(_error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: SarthiPrimaryButton(
        label: vm.isSaving ? 'Saving…' : 'Continue',
        onPressed: vm.isSaving ? null : _submit,
      ),
    );
  }
}
