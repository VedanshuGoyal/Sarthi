import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../auth/domain/auth_validators.dart';
import '../../../l10n/l10n.dart';
import '../../auth/driver_auth_controller.dart';
import '../document_providers.dart';
import '../domain/document_kind.dart';
import '../domain/gender.dart';
import '../widgets/local_photo.dart';
import 'document_labels.dart';

/// Document step 2 — selfie, full name, date of birth, and gender.
///
/// Once the Aadhaar is verified the name, date of birth and gender are the
/// Aadhaar's: shown read-only, and never re-sent.
class PhotoAndNameStep extends ConsumerStatefulWidget {
  const PhotoAndNameStep({super.key});

  @override
  ConsumerState<PhotoAndNameStep> createState() => _PhotoAndNameStepState();
}

class _PhotoAndNameStepState extends ConsumerState<PhotoAndNameStep> {
  final TextEditingController _name = TextEditingController();
  DateTime? _dateOfBirth;
  Gender? _gender;
  String? _error;

  @override
  void initState() {
    super.initState();
    final kyc = ref.read(documentRegistrationViewModelProvider).kyc;
    final driver = ref.read(driverAuthControllerProvider).valueOrNull?.driver;
    _name.text = kyc.fullName.isNotEmpty ? kyc.fullName : driver?.name ?? '';
    _dateOfBirth = kyc.dateOfBirth;
    _gender = kyc.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickSelfie() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;

    setState(() => _error = null);
    // Uploaded as soon as it's taken: a selfie sitting in the OS cache
    // directory is one low-storage moment away from being gone.
    await ref
        .read(documentRegistrationViewModelProvider)
        .capturePhoto(DocumentKind.selfie, photo.path);
  }

  Future<void> _retrySelfie() async {
    setState(() => _error = null);
    await ref
        .read(documentRegistrationViewModelProvider)
        .retryUpload(DocumentKind.selfie);
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      // At least 18 years old to drive commercially.
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _submit() async {
    final vm = ref.read(documentRegistrationViewModelProvider);
    final l10n = context.l10n;

    if (!vm.kyc.hasUploaded(DocumentKind.selfie)) {
      setState(() => _error = l10n.photoStepSelfieRequired);
      return;
    }
    if (vm.kyc.isAadhaarVerified) {
      Navigator.of(context).pop();
      return;
    }
    final nameError = AuthValidators.name(_name.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    if (_dateOfBirth == null) {
      setState(() => _error = l10n.photoStepDobRequired);
      return;
    }
    if (_gender == null) {
      setState(() => _error = l10n.photoStepGenderRequired);
      return;
    }

    await vm.setPhotoAndName(
      fullName: _name.text,
      dateOfBirth: _dateOfBirth!,
      gender: _gender!,
    );
    if (!mounted) return;
    if (vm.error != null) {
      setState(() => _error = vm.error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final dob = _dateOfBirth;
    final selfiePath = vm.data.capturePathFor(DocumentKind.selfie);
    final selfieState = vm.data.uploadStateFor(DocumentKind.selfie);
    final locked = vm.kyc.isAadhaarVerified;
    final l10n = context.l10n;

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: l10n.photoStepTitle,
      subtitle: l10n.photoStepSubtitle,
      fields: [
        Center(
          child: GestureDetector(
            // Blocked mid-upload, like the document tiles: a retake would
            // replace the file under the in-flight request. A failed upload
            // is sent again from the copy already on the phone.
            onTap: switch (selfieState) {
              DocumentUploadState.uploading => null,
              DocumentUploadState.failed when selfiePath != null =>
                _retrySelfie,
              _ => _pickSelfie,
            },
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: t.raised,
                border: Border.all(color: t.hairlineStrong),
                borderRadius: BorderRadius.circular(48),
              ),
              clipBehavior: Clip.antiAlias,
              child: switch (selfiePath) {
                final String path => LocalPhoto(path: path),
                _ when selfieState == DocumentUploadState.uploaded => Icon(
                  Icons.check_circle_outline,
                  color: t.accent,
                  size: 28,
                ),
                _ => Icon(Icons.camera_alt_outlined, color: t.muted, size: 28),
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            switch (selfieState) {
              DocumentUploadState.uploading => l10n.photoStepSelfieUploading,
              DocumentUploadState.failed => l10n.photoStepSelfieUploadFailed,
              DocumentUploadState.uploaded => l10n.photoStepRetakeSelfie,
              DocumentUploadState.none =>
                selfiePath == null
                    ? l10n.photoStepTakeSelfie
                    : l10n.photoStepRetakeSelfie,
            },
            textAlign: TextAlign.center,
            style: t.body(
              size: 13,
              color: selfieState == DocumentUploadState.failed
                  ? Colors.red
                  : t.muted,
            ),
          ),
        ),
        if (selfieState == DocumentUploadState.failed && selfiePath != null)
          Center(
            child: TextButton(
              onPressed: _pickSelfie,
              child: Text(l10n.photoStepTakeNewSelfie),
            ),
          ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            l10n.photoStepSelfieShownToCustomers,
            textAlign: TextAlign.center,
            style: t.body(size: 12, color: t.muted),
          ),
        ),
        const SizedBox(height: DeepSignalTokens.s22),
        if (locked) ...[
          Text(
            l10n.photoStepFromAadhaar,
            style: t.body(size: 12, color: t.muted),
          ),
          const SizedBox(height: DeepSignalTokens.s8),
        ],
        SarthiTextField(
          label: l10n.photoStepFullName,
          controller: _name,
          readOnly: locked,
          hintText: l10n.photoStepFullName,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: locked ? null : _pickDateOfBirth,
            borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
            child: Container(
              padding: const EdgeInsets.all(DeepSignalTokens.s14),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.hairline),
                borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
              ),
              child: Row(
                children: [
                  Icon(Icons.cake_outlined, color: t.muted, size: 20),
                  const SizedBox(width: DeepSignalTokens.s14),
                  Expanded(
                    child: Text(
                      dob == null
                          ? l10n.photoStepDateOfBirth
                          : '${dob.day}/${dob.month}/${dob.year}',
                      style: t.body(color: dob == null ? t.muted : t.fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        Wrap(
          spacing: DeepSignalTokens.s8,
          children: [
            for (final g in Gender.values)
              ChoiceChip(
                label: Text(g.labelIn(l10n)),
                selected: _gender == g,
                onSelected: locked ? null : (_) => setState(() => _gender = g),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(_error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: SarthiPrimaryButton(
        label: vm.isSaving ? l10n.photoStepSaving : l10n.commonContinue,
        onPressed: vm.isSaving ? null : _submit,
      ),
    );
  }
}
