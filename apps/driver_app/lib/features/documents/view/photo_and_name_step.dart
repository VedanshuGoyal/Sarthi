import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../auth/domain/auth_validators.dart';
import '../../auth/driver_auth_controller.dart';
import '../document_providers.dart';
import '../domain/document_kind.dart';
import '../domain/gender.dart';
import '../widgets/local_photo.dart';

/// Document step 2 — selfie, full name, date of birth, and gender.
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
    if (photo == null) return;

    setState(() => _error = null);
    // Uploaded as soon as it's taken: a selfie sitting in the OS cache
    // directory is one low-storage moment away from being gone.
    await ref
        .read(documentRegistrationViewModelProvider)
        .capturePhoto(DocumentKind.selfie, photo.path);
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

    if (!vm.kyc.hasUploaded(DocumentKind.selfie)) {
      setState(() => _error = 'Take a selfie to continue');
      return;
    }
    final nameError = AuthValidators.name(_name.text);
    if (nameError != null) {
      setState(() => _error = nameError);
      return;
    }
    if (_dateOfBirth == null) {
      setState(() => _error = 'Select your date of birth');
      return;
    }
    if (_gender == null) {
      setState(() => _error = 'Select your gender');
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

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Photo and name',
      subtitle: 'A clear selfie and your details, as they appear on your ID.',
      fields: [
        Center(
          child: GestureDetector(
            onTap: _pickSelfie,
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
              DocumentUploadState.uploading => 'Uploading…',
              DocumentUploadState.failed => 'Upload failed — tap to retry',
              DocumentUploadState.uploaded => 'Retake selfie',
              DocumentUploadState.none =>
                selfiePath == null ? 'Take a selfie' : 'Retake selfie',
            },
            style: t.body(
              size: 13,
              color: selfieState == DocumentUploadState.failed
                  ? Colors.red
                  : t.muted,
            ),
          ),
        ),
        const SizedBox(height: DeepSignalTokens.s22),
        SarthiTextField(
          label: 'Full name',
          controller: _name,
          hintText: 'Full name',
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _pickDateOfBirth,
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
                  Text(
                    dob == null
                        ? 'Date of birth'
                        : '${dob.day}/${dob.month}/${dob.year}',
                    style: t.body(color: dob == null ? t.muted : t.fg),
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
                label: Text(g.label),
                selected: _gender == g,
                onSelected: (_) => setState(() => _gender = g),
              ),
          ],
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
