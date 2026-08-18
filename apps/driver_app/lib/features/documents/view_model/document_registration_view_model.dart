import 'package:flutter/foundation.dart';

import '../data/document_file_store.dart';
import '../data/driver_kyc_repository.dart';
import '../domain/document_kind.dart';
import '../domain/document_step.dart';
import '../domain/driver_documents.dart';
import '../domain/driver_kyc.dart';
import '../domain/gender.dart';
import '../domain/vehicle_type.dart';

/// Drives the post-registration Document View: six KYC steps that unlock one
/// at a time, each opening only once the step before it is complete.
///
/// Every step saves to the backend as the driver finishes it, rather than
/// batching all six into one submission at the end. Two reasons: a driver who
/// loses connection on step 5 doesn't lose the first four, and a photo that
/// only exists in the phone's cache directory is one low-storage moment away
/// from being gone.
///
/// That makes the backend the source of truth for progress — [kyc] — and
/// leaves [data] holding only what can't live there: the captured files and
/// the OS permission grants.
class DocumentRegistrationViewModel extends ChangeNotifier {
  DocumentRegistrationViewModel({
    required this._repository,
    DocumentFileStore? files,
  }) : _files = files ?? DocumentFileStore();

  final DriverKycRepository _repository;
  final DocumentFileStore _files;

  DriverDocuments _data = const DriverDocuments();
  DriverKyc _kyc = const DriverKyc();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  /// On-device state: capture paths and permission grants.
  DriverDocuments get data => _data;

  /// What the backend holds — the authority on what's been completed.
  DriverKyc get kyc => _kyc;

  /// True while the initial load is in flight.
  bool get isLoading => _isLoading;

  /// True while a step is being saved, so views can disable their buttons.
  bool get isSaving => _isSaving;

  /// The last failure, safe to show to the driver. Cleared by the next write.
  String? get error => _error;

  /// Loads the driver's saved progress and re-attaches any captures still on
  /// the device. Safe to call more than once.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _kyc = await _repository.load();
      await _restoreCaptures();
      _error = null;
    } on KycException catch (e) {
      _error = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool isComplete(DocumentStep step) => switch (step) {
    DocumentStep.vehicleType => _kyc.transmission != null,
    DocumentStep.photoAndName =>
      _kyc.fullName.isNotEmpty &&
          _kyc.dateOfBirth != null &&
          _kyc.gender != null &&
          _kyc.hasUploaded(DocumentKind.selfie),
    DocumentStep.aadhar =>
      _kyc.aadhaarLast4 != null && _kyc.hasUploaded(DocumentKind.aadhaar),
    DocumentStep.drivingLicense =>
      _kyc.drivingLicenseNumber != null &&
          _kyc.hasUploaded(DocumentKind.drivingLicense),
    // OS grants, not backend state — the permissions step re-reads these from
    // the system every time it opens.
    DocumentStep.permissions => _data.hasAllPermissions,
    DocumentStep.bankDetails => _kyc.bankAccount != null,
  };

  /// A step is reachable once every step before it is complete; the first
  /// step is always open.
  bool isUnlocked(DocumentStep step) {
    final index = DocumentStep.values.indexOf(step);
    if (index == 0) return true;
    return isComplete(DocumentStep.values[index - 1]);
  }

  int get completedCount => DocumentStep.values.where(isComplete).length;

  bool get isAllComplete => completedCount == DocumentStep.values.length;

  /// Whether the driver's documents have gone in for review.
  bool get isSubmitted => _kyc.status != KycStatus.incomplete;

  /// Stores a freshly captured photo and uploads it straight away.
  ///
  /// [pickedPath] is what `image_picker` returned, which lives in the OS cache
  /// directory; it's copied somewhere durable first so a retry after a failed
  /// upload still has a file to send.
  Future<void> capturePhoto(DocumentKind kind, String pickedPath) async {
    final path = await _files.persist(kind, pickedPath);
    _data = _data
        .withCapture(kind, path)
        .withUploadState(kind, DocumentUploadState.uploading);
    _error = null;
    notifyListeners();

    try {
      _kyc = await _repository.uploadDocument(kind, path);
      _data = _data.withUploadState(kind, DocumentUploadState.uploaded);
    } on KycException catch (e) {
      _data = _data.withUploadState(kind, DocumentUploadState.failed);
      _error = e.message;
    }
    notifyListeners();
  }

  /// Retries a failed upload for [kind] using the capture already on disk.
  Future<void> retryUpload(DocumentKind kind) async {
    final path = _data.capturePathFor(kind);
    if (path == null) return;
    await capturePhoto(kind, path);
  }

  Future<void> setVehicleType(VehicleType type) =>
      _save(() => _repository.updateProfile(transmission: type));

  Future<void> setPhotoAndName({
    required String fullName,
    required DateTime dateOfBirth,
    required Gender gender,
  }) => _save(
    () => _repository.updateProfile(
      fullName: fullName,
      dateOfBirth: dateOfBirth,
      gender: gender,
    ),
  );

  Future<void> setAadhar({required String number}) =>
      _save(() => _repository.updateProfile(aadhaarNumber: number));

  Future<void> setDrivingLicense({required String number}) =>
      _save(() => _repository.updateProfile(drivingLicenseNumber: number));

  Future<void> setBankDetails({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
  }) => _save(
    () => _repository.setBankAccount(
      accountHolderName: accountHolderName,
      accountNumber: accountNumber,
      ifscCode: ifscCode,
    ),
  );

  /// Records the OS permission grants. Local only — there is nothing for the
  /// backend to verify, and the OS is asked again on every visit.
  void setPermissions({
    required bool overlayGranted,
    required bool backgroundLocationGranted,
    required bool batteryUnrestricted,
  }) {
    _data = _data.copyWith(
      overlayPermissionGranted: overlayGranted,
      backgroundLocationGranted: backgroundLocationGranted,
      batteryUnrestricted: batteryUnrestricted,
    );
    notifyListeners();
  }

  /// Submits the completed Document View for review.
  ///
  /// The backend re-checks every step, so a mismatch between what the app
  /// thinks is done and what was actually saved surfaces here as an error
  /// naming what's missing, rather than as a driver stuck on a dead end.
  /// Captures are wiped once it's accepted — an Aadhaar photo shouldn't stay
  /// on the phone after the server has it.
  Future<bool> submit() async {
    final saved = await _save(() => _repository.submit());
    if (saved) {
      await _files.discardAll();
      _data = _data.copyWith(capturePaths: const {});
      notifyListeners();
    }
    return saved;
  }

  /// Runs a write, folding the returned state in and surfacing failures.
  /// Returns whether it succeeded.
  Future<bool> _save(Future<DriverKyc> Function() write) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      _kyc = await write();
      return true;
    } on KycException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Re-attaches captures left on disk by an earlier run, so reopening a step
  /// shows the photo already taken instead of an empty tile.
  Future<void> _restoreCaptures() async {
    final paths = <DocumentKind, String>{};
    final states = <DocumentKind, DocumentUploadState>{};
    for (final kind in DocumentKind.values) {
      final path = await _files.pathFor(kind);
      if (path != null) paths[kind] = path;
      if (_kyc.hasUploaded(kind)) states[kind] = DocumentUploadState.uploaded;
    }
    _data = _data.copyWith(capturePaths: paths, uploadStates: states);
  }
}
