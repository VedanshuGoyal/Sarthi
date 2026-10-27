import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/digilocker_session.dart';
import '../domain/document_kind.dart';
import '../domain/driver_kyc.dart';
import '../domain/gender.dart';
import '../domain/vehicle_type.dart';

/// Raised when the backend rejects a KYC request. [message] is safe to show.
class KycException implements Exception {
  const KycException(this.message, {this.code});

  final String message;

  /// The backend's machine-readable tag (`aadhaar_taken`, `kyc_incomplete`,
  /// `verification_pending`, `aadhaar_mismatch`, `license_not_found`, …), or
  /// null for generic errors.
  final String? code;

  @override
  String toString() => 'KycException: $message';
}

/// The single entry point for driver KYC data access — view models talk only
/// to this, never to an HTTP client.
///
/// It fronts the backend's `/driver/kyc` endpoints. Every write returns the
/// whole [DriverKyc] afterwards, so the app re-renders from one authoritative
/// shape rather than patching its own copy and drifting.
class DriverKycRepository {
  DriverKycRepository({http.Client? client, String? baseUrl, this._tokenGetter})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token from in-memory session state. Null when
  /// unauthenticated, which every route here rejects.
  final String? Function()? _tokenGetter;

  /// Loads the driver's whole document state.
  Future<DriverKyc> load() async {
    final body = await _send('GET', '/driver/kyc');
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Saves whichever typed fields a step collected. Omitted arguments are left
  /// untouched server-side, so each step sends only what it owns.
  ///
  /// [aadhaarNumber] is sent once and never stored in full: the backend keeps
  /// the last four digits and a keyed fingerprint, nothing more.
  Future<DriverKyc> updateProfile({
    VehicleType? transmission,
    String? fullName,
    DateTime? dateOfBirth,
    Gender? gender,
    String? aadhaarNumber,
    String? drivingLicenseNumber,
  }) async {
    final payload = <String, dynamic>{
      if (transmission != null) 'transmission': transmission.name,
      if (fullName != null) 'fullName': fullName.trim(),
      if (dateOfBirth != null) 'dateOfBirth': _formatDate(dateOfBirth),
      if (gender != null) 'gender': gender.name,
      if (aadhaarNumber != null) 'aadhaarNumber': aadhaarNumber.trim(),
      if (drivingLicenseNumber != null)
        'drivingLicenseNumber': drivingLicenseNumber.trim(),
    };
    final body = await _send('PATCH', '/driver/kyc/profile', payload: payload);
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Opens a DigiLocker session for the Aadhaar check. The Aadhaar number must
  /// already be saved — the backend compares DigiLocker's last four digits
  /// against it.
  Future<DigiLockerSession> startDigiLocker() async {
    final body = await _send(
      'POST',
      '/driver/kyc/digilocker',
      payload: const {},
    );
    return DigiLockerSession.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Reads the DigiLocker session's result. Throws a [KycException] with code
  /// `verification_pending` while the driver hasn't finished in DigiLocker.
  Future<DriverKyc> completeDigiLocker() async {
    final body = await _send(
      'POST',
      '/driver/kyc/digilocker/complete',
      payload: const {},
    );
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Saves the licence number and has the backend look it up against the
  /// driver's date of birth.
  Future<DriverKyc> verifyDrivingLicense(String number) async {
    final body = await _send(
      'POST',
      '/driver/kyc/driving-license',
      payload: {'number': number.trim().toUpperCase()},
    );
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Saves the payout details once the backend has checked the account with
  /// the bank. The account number is encrypted server-side and never
  /// returned; the response carries only its last four digits.
  Future<DriverKyc> setBankAccount({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
  }) async {
    final body = await _send(
      'POST',
      '/driver/kyc/bank-account',
      payload: {
        'accountHolderName': accountHolderName.trim(),
        'accountNumber': accountNumber.trim(),
        'ifscCode': ifscCode.trim().toUpperCase(),
      },
    );
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Uploads the image at [path] as the driver's [kind] document.
  ///
  /// The bytes go up as the raw request body rather than a multipart form —
  /// there is one file and no other fields, so multipart would only add a
  /// temp file on both ends. The backend re-encodes what it receives, which
  /// is what strips the EXIF (and therefore the GPS) off a phone photo.
  Future<DriverKyc> uploadDocument(DocumentKind kind, String path) async {
    final bytes = await _readBytes(path);
    final body = await _send(
      'POST',
      '/driver/kyc/documents/${kind.wireName}',
      bytes: bytes,
      contentType: 'image/jpeg',
    );
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Submits the completed Document View. The backend answers `verified` when
  /// every check agrees, or `submitted` when a person needs to look. Throws a
  /// [KycException] with code `kyc_incomplete` — whose message names what is
  /// missing — when the backend finds a step outstanding.
  Future<DriverKyc> submit() async {
    final body = await _send('POST', '/driver/kyc/submit', payload: const {});
    return DriverKyc.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Reads the captured image. On web the picker's path is a `blob:` URL,
  /// which has to be fetched rather than opened as a file.
  Future<Uint8List> _readBytes(String path) async {
    if (kIsWeb) {
      final response = await _client.get(Uri.parse(path));
      return response.bodyBytes;
    }
    return File(path).readAsBytes();
  }

  /// Sends a request and returns the body on 2xx, throwing [KycException]
  /// otherwise. Exactly one of [payload] and [bytes] carries the request body.
  Future<String> _send(
    String method,
    String path, {
    Map<String, dynamic>? payload,
    Uint8List? bytes,
    String contentType = 'application/json',
  }) async {
    final token = _tokenGetter?.call();
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll({
        'Content-Type': contentType,
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (payload != null) {
      request.body = jsonEncode(payload);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (_) {
      throw const KycException(
        "Can't reach the server. Check your connection and try again.",
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw _exceptionFor(response);
  }

  /// Maps an error response onto a [KycException], preferring the backend's
  /// own message — it names the offending field, or what is still missing.
  KycException _exceptionFor(http.Response response) {
    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Not JSON — fall back to the generic message below.
    }

    final message = switch (body['error']) {
      final String m when m.isNotEmpty => m,
      _ => 'Something went wrong. Please try again.',
    };
    return KycException(message, code: body['code'] as String?);
  }

  /// Formats a date the way the API expects it: a plain calendar date, with no
  /// timezone for either side to shift it by.
  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
