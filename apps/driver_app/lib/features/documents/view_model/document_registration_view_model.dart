import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/document_file_store.dart';
import '../data/driver_kyc_repository.dart';
import '../data/kyc_status_store.dart';
import '../data/lost_capture.dart';
import '../data/permission_grants.dart';
import '../domain/digilocker_session.dart';
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
///
/// The status the backend last gave is also kept on the phone
/// ([KycStatusStore], for [driverId]), so a verified driver whose first load
/// fails — a cold start in a basement car park — still gets Home and their
/// rides rather than a Document View they can't leave.
class DocumentRegistrationViewModel extends ChangeNotifier {
  DocumentRegistrationViewModel({
    required this._repository,
    DocumentFileStore? files,
    KycStatusStore? statusStore,
    String? driverId,
    this._lostCaptures,
    this._permissionGrants,
  }) : _files = files ?? DocumentFileStore(),
       _statusStore = statusStore,
       _driverId = driverId {
    if (statusStore != null && driverId != null) {
      _isRestoring = true;
      unawaited(_restoreStatus(statusStore, driverId));
    }
  }

  final DriverKycRepository _repository;
  final DocumentFileStore _files;
  final KycStatusStore? _statusStore;
  final String? _driverId;

  /// A selfie taken while Android had killed the app; asked for once.
  LostCaptureSource? _lostCaptures;

  /// The OS's current permission grants; null where they can't be read.
  final PermissionGrantsSource? _permissionGrants;

  DriverDocuments _data = const DriverDocuments();
  DriverKyc _kyc = const DriverKyc();
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  String? _errorCode;
  bool _disposed = false;

  /// Whether [kyc] is the backend's answer rather than the empty default.
  bool _hasBackendKyc = false;

  /// The status last stored on the phone, or the backend's latest.
  KycStatus? _lastKnownStatus;
  bool _isRestoring = false;
  bool _loadFailed = false;

  /// True until the stored status has been read back at startup, so the
  /// gate can wait a moment instead of flashing the Document View.
  bool get isRestoring => _isRestoring;

  /// Whether the backend couldn't be read and has never answered, so all
  /// the screen can offer is to try again (or to log out).
  bool get loadFailed => _loadFailed && !_hasBackendKyc;

  /// Whether [kyc] is the backend's answer, so a reload can refresh the
  /// screen in place instead of blanking it.
  bool get hasKyc => _hasBackendKyc;

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

  /// The backend's tag for [error] (`verification_pending`, …), so a view can
  /// react to a specific failure rather than parse its message.
  String? get errorCode => _errorCode;

  /// Loads the driver's saved progress, re-attaches any captures still on
  /// the device and re-reads the OS permission grants. Safe to call more
  /// than once.
  Future<void> load() async {
    _isLoading = true;
    _notify();
    try {
      _setKyc(await _repository.load());
      await _restoreCaptures();
      await _readPermissionGrants();
      _error = null;
      if (_lostCaptures case final source?) {
        _lostCaptures = null;
        unawaited(_recoverLostCapture(source));
      }
    } on KycException catch (e) {
      _error = e.message;
      _loadFailed = true;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  bool isComplete(DocumentStep step) => switch (step) {
    DocumentStep.vehicleType => _kyc.transmission != null,
    DocumentStep.photoAndName =>
      _kyc.fullName.isNotEmpty &&
          _kyc.dateOfBirth != null &&
          _kyc.gender != null &&
          _kyc.hasUploaded(DocumentKind.selfie),
    // The checks, not the typed numbers: a number nobody verified proves
    // nothing.
    DocumentStep.aadhar => _kyc.isAadhaarVerified,
    DocumentStep.drivingLicense => _kyc.isLicenseVerified,
    // OS grants, not backend state — the permissions step re-reads these from
    // the system every time it opens.
    DocumentStep.permissions => _data.hasAllPermissions,
    DocumentStep.bankDetails => _kyc.isBankVerified,
  };

  /// A step is reachable once the step before it is complete; the first
  /// step is always open. A step that is itself complete never looks
  /// locked — a verified bank account isn't something left to do because
  /// an earlier step lapsed — and a cleared driver may open any step to see
  /// or change it.
  bool isUnlocked(DocumentStep step) {
    if (isComplete(step) || _kyc.status == KycStatus.verified) return true;
    final index = DocumentStep.values.indexOf(step);
    if (index == 0) return true;
    return isComplete(DocumentStep.values[index - 1]);
  }

  int get completedCount => DocumentStep.values.where(isComplete).length;

  bool get isAllComplete => completedCount == DocumentStep.values.length;

  /// Whether the driver is cleared to drive — the only status that opens Home.
  /// Until the backend has answered, the status stored on the phone stands
  /// in for it.
  bool get isVerified =>
      (_hasBackendKyc ? _kyc.status : _lastKnownStatus) == KycStatus.verified;

  /// Whether a person is checking the driver's details.
  bool get isUnderReview => _kyc.status == KycStatus.submitted;

  /// Stores a freshly captured photo and uploads it straight away.
  ///
  /// [pickedPath] is what `image_picker` returned, which lives in the OS cache
  /// directory; it's copied somewhere durable first so a retry after a failed
  /// upload still has a file to send.
  ///
  /// A second capture of the same [kind] while one is still being stored or
  /// uploaded is ignored: it would overwrite the file under the in-flight
  /// request, and whichever reply landed last would win.
  Future<void> capturePhoto(DocumentKind kind, String pickedPath) async {
    if (!_capturing.add(kind)) return;
    try {
      final String path;
      try {
        path = await _files.persist(kind, pickedPath);
      } on Exception {
        _data = _data.withUploadState(kind, DocumentUploadState.failed);
        _error = "Couldn't save the photo. Please take it again.";
        _notify();
        return;
      }
      await _upload(kind, path);
    } finally {
      _capturing.remove(kind);
    }
  }

  /// Kinds with a capture being stored or uploaded right now.
  final Set<DocumentKind> _capturing = {};

  /// Retries a failed upload for [kind] using the capture already on disk.
  /// It is sent as it is: it's already in durable storage, and storing it
  /// again would copy the file onto itself.
  Future<void> retryUpload(DocumentKind kind) async {
    final path = _data.capturePathFor(kind);
    if (path == null || !_capturing.add(kind)) return;
    try {
      await _upload(kind, path);
    } finally {
      _capturing.remove(kind);
    }
  }

  /// Uploads the stored capture at [path], tracking its state for the tile.
  /// Once the backend has it the capture is deleted: an ID photo or selfie
  /// has no business staying on the phone after it's been sent.
  Future<void> _upload(DocumentKind kind, String path) async {
    _data = _data
        .withCapture(kind, path)
        .withUploadState(kind, DocumentUploadState.uploading);
    _error = null;
    _notify();

    try {
      _setKyc(await _repository.uploadDocument(kind, path));
      await _files.discard(kind);
      _data = _data
          .withoutCapture(kind)
          .withUploadState(kind, DocumentUploadState.uploaded);
    } on KycException catch (e) {
      _data = _data.withUploadState(kind, DocumentUploadState.failed);
      _error = e.message;
    }
    _notify();
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

  /// Opens a DigiLocker session; null on failure, with [error] set.
  Future<DigiLockerSession?> startDigiLocker() =>
      _run(() => _repository.startDigiLocker());

  /// Reads how the DigiLocker session went. False with [errorCode]
  /// `verification_pending` while the driver hasn't finished there.
  Future<bool> completeDigiLocker() =>
      _save(() => _repository.completeDigiLocker());

  Future<bool> verifyDrivingLicense(String number) =>
      _save(() => _repository.verifyDrivingLicense(number));

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

  /// Re-reads the OS permission grants — local, no request — so the
  /// permissions step ticks itself for a driver who turned them on in
  /// system settings, and un-ticks for one who turned one off.
  Future<void> refreshPermissionGrants() async {
    final before = _data;
    await _readPermissionGrants();
    if (!identical(before, _data)) _notify();
  }

  Future<void> _readPermissionGrants() async {
    final source = _permissionGrants;
    if (source == null) return;
    final grants = await source();
    if (grants == null || _disposed) return;
    if (grants.overlay == _data.overlayPermissionGranted &&
        grants.backgroundLocation == _data.backgroundLocationGranted &&
        grants.battery == _data.batteryUnrestricted) {
      return;
    }
    _data = _data.copyWith(
      overlayPermissionGranted: grants.overlay,
      backgroundLocationGranted: grants.backgroundLocation,
      batteryUnrestricted: grants.battery,
    );
  }

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
    _notify();
  }

  /// Submits the completed Document View. The backend clears the driver
  /// straight away when every check agrees, or queues them for a person.
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
      _notify();
    }
    return saved;
  }

  /// Runs a write, folding the returned state in and surfacing failures.
  /// Returns whether it succeeded.
  Future<bool> _save(Future<DriverKyc> Function() write) async {
    final kyc = await _run(write);
    if (kyc == null) return false;
    _setKyc(kyc);
    _notify();
    return true;
  }

  /// Takes [kyc] from the backend as the truth, and stores its status on
  /// the phone when it changed.
  void _setKyc(DriverKyc kyc) {
    _kyc = kyc;
    _hasBackendKyc = true;
    _loadFailed = false;
    if (kyc.status == _lastKnownStatus) return;
    _lastKnownStatus = kyc.status;
    final store = _statusStore;
    final driverId = _driverId;
    if (store != null && driverId != null) {
      unawaited(store.write(driverId, kyc.status).catchError((_) {}));
    }
  }

  /// Uploads a selfie the camera took while the app was dead, as if it had
  /// just been taken.
  Future<void> _recoverLostCapture(LostCaptureSource source) async {
    final path = await source();
    if (path == null || _disposed) return;
    await capturePhoto(DocumentKind.selfie, path);
  }

  Future<void> _restoreStatus(KycStatusStore store, String driverId) async {
    KycStatus? status;
    try {
      status = await store.read(driverId);
    } catch (_) {
      // Unreadable: behave as a first run and wait for the backend.
    }
    if (!_hasBackendKyc) _lastKnownStatus = status;
    _isRestoring = false;
    _notify();
  }

  /// Runs a request with [isSaving] up, returning its result, or null with
  /// [error] and [errorCode] set.
  ///
  /// Returns null without sending while another request is in flight, so a
  /// double tap can't send a check (DigiLocker, the licence lookup, the bank
  /// penny-drop) or the final submission twice.
  Future<T?> _run<T>(Future<T> Function() request) async {
    if (_isSaving) return null;
    _isSaving = true;
    _error = null;
    _errorCode = null;
    _notify();
    try {
      return await request();
    } on KycException catch (e) {
      _error = e.message;
      _errorCode = e.code;
      return null;
    } finally {
      _isSaving = false;
      _notify();
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

  /// Notifies only while alive: a sign-out replaces this view model (see
  /// `documentRegistrationViewModelProvider`) while a request may still be
  /// in flight.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
