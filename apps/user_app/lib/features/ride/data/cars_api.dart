import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../domain/car.dart';
import '../domain/car_type.dart';
import '../domain/transmission.dart';

/// Raised when the saved-cars backend is unreachable or rejects a request.
/// Carries the server's message when it sent one (e.g. the car-limit error),
/// so the view can show it as-is.
class CarsRequestException implements Exception {
  const CarsRequestException(this.message);
  final String message;
  @override
  String toString() => 'CarsRequestException: $message';
}

/// Talks to the Sarthi backend's per-user saved cars
/// (`GET`/`POST /me/cars`, `DELETE /me/cars/{id}`).
///
/// The backend (PostgreSQL) is the source of truth: it normalises the
/// registration and de-duplicates, so re-adding a plate updates that car
/// instead of creating another. [CarsRepository] mirrors each response into
/// on-device storage and serves reads from there, so this API is only hit
/// when something actually changes (or the cache is empty).
class CarsApi {
  CarsApi({
    http.Client? client,
    String? baseUrl,
    String? Function()? tokenGetter,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? ApiConfig.baseUrl,
       _tokenGetter = tokenGetter ?? _noToken;

  final http.Client _client;
  final String _baseUrl;

  /// Reads the current bearer token from in-memory auth state. Returns null when
  /// unauthenticated (the backend then rejects the request).
  final String? Function() _tokenGetter;

  static const String _path = '/me/cars';

  /// Default token getter when none is injected — always unauthenticated.
  static String? _noToken() => null;

  /// The user's saved cars, newest first.
  Future<List<Car>> list() async {
    final response = await _send(
      () => _client.get(_uri(), headers: _headers()),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    return _carsFrom(decoded['cars']);
  }

  /// Saves a car and returns it as stored (normalised registration, backend
  /// id) together with the updated list.
  Future<({Car car, List<Car> cars})> add({
    required String registration,
    required CarType type,
    required Transmission transmission,
  }) async {
    final body = jsonEncode({
      'registration': registration,
      'carType': type.name,
      'transmission': transmission.name,
    });
    final response = await _send(
      () => _client.post(_uri(), headers: _headers(json: true), body: body),
    );
    final decoded = jsonDecode(response.body);
    final car = decoded is Map<String, dynamic>
        ? _carFrom(decoded['car'])
        : null;
    if (car == null) {
      throw const CarsRequestException('Unexpected response from the server.');
    }
    return (
      car: car,
      cars: decoded is Map<String, dynamic>
          ? _carsFrom(decoded['cars'])
          : const <Car>[],
    );
  }

  /// Deletes the car with the backend [id] and returns the updated list.
  Future<List<Car>> remove(String id) async {
    final response = await _send(
      () => _client.delete(_uri(id), headers: _headers()),
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    return _carsFrom(decoded['cars']);
  }

  Uri _uri([String? id]) =>
      Uri.parse(id == null ? '$_baseUrl$_path' : '$_baseUrl$_path/$id');

  Map<String, String> _headers({bool json = false}) {
    final token = _tokenGetter();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _send(Future<http.Response> Function() run) async {
    final http.Response response;
    try {
      response = await run();
    } catch (_) {
      throw const CarsRequestException("Can't reach the server.");
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CarsRequestException(
        _serverMessage(response) ??
            'Saved-cars request failed (${response.statusCode}).',
      );
    }
    return response;
  }

  /// The backend's human-readable error, when the body carries one.
  String? _serverMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }

  List<Car> _carsFrom(Object? json) {
    if (json is! List) return const [];
    return json.map(_carFrom).whereType<Car>().toList(growable: false);
  }

  Car? _carFrom(Object? json) =>
      json is Map<String, dynamic> ? Car.fromJson(json) : null;
}
