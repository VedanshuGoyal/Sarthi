import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../document_providers.dart';
import '../domain/document_kind.dart';
import '../domain/document_validators.dart';
import '../widgets/document_photo_picker.dart';

/// Document step 3 — Aadhar number and a photo of the card.
class AadharStep extends ConsumerStatefulWidget {
  const AadharStep({super.key});

  @override
  ConsumerState<AadharStep> createState() => _AadharStepState();
}

class _AadharStepState extends ConsumerState<AadharStep> {
  final TextEditingController _number = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _onPhotoTaken(String path) async {
    setState(() => _error = null);
    await ref
        .read(documentRegistrationViewModelProvider)
        .capturePhoto(DocumentKind.aadhaar, path);
  }

  Future<void> _submit() async {
    final vm = ref.read(documentRegistrationViewModelProvider);

    // The number is only re-sent when the driver typed one. Once it's saved
    // the backend keeps just the last 4 digits, so an untouched field means
    // "leave it as it is", not "clear it".
    final alreadySaved = vm.kyc.aadhaarLast4 != null;
    final typed = _number.text.trim();
    if (typed.isNotEmpty || !alreadySaved) {
      final numberError = DocumentValidators.aadharNumber(typed);
      if (numberError != null) {
        setState(() => _error = numberError);
        return;
      }
    }
    if (!vm.kyc.hasUploaded(DocumentKind.aadhaar)) {
      setState(() => _error = 'Take a photo of your Aadhar card');
      return;
    }

    if (typed.isNotEmpty) {
      await vm.setAadhar(number: typed);
      if (vm.error != null) {
        setState(() => _error = vm.error);
        return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final last4 = vm.kyc.aadhaarLast4;

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Aadhar card',
      subtitle: 'Your 12-digit Aadhar number and a clear photo of the card.',
      fields: [
        SarthiTextField(
          label: 'Aadhar number',
          controller: _number,
          hintText: last4 == null ? 'XXXX XXXX XXXX' : 'XXXX XXXX $last4',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          prefixIcon: const Icon(Icons.credit_card_outlined),
        ),
        if (last4 != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(
            'Saved. We only keep the last 4 digits — leave this blank unless '
            'you need to change it.',
            style: t.body(size: 12, color: t.muted),
          ),
        ],
        const SizedBox(height: DeepSignalTokens.s14),
        DocumentPhotoPicker(
          photoPath: vm.data.capturePathFor(DocumentKind.aadhaar),
          uploadState: vm.data.uploadStateFor(DocumentKind.aadhaar),
          onPhotoTaken: _onPhotoTaken,
          label: 'Take a photo of your Aadhar card',
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
