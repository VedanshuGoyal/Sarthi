import 'dart:convert';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:user_app/features/ride/data/cars_api.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/transmission.dart';

const _carJson =
    '{"id":"c1","registration":"DL01AB1234","carType":"sedan",'
    '"transmission":"manual","createdAt":"2026-07-20T09:15:00Z"}';

CarsApi _api(
  http.Response Function(http.Request request) responder, {
  List<http.Request>? captured,
}) {
  final client = MockClient((request) async {
    captured?.add(request);
    return responder(request);
  });
  return CarsApi(
    client: client,
    baseUrl: 'https://api.test',
    tokenGetter: () => 'tok-1',
  );
}

void main() {
  test('lists the saved cars with the bearer token', () async {
    final captured = <http.Request>[];
    final api = _api(
      (_) => http.Response('{"cars":[$_carJson]}', 200),
      captured: captured,
    );

    final cars = await api.list();

    final request = captured.single;
    check(request.method).equals('GET');
    check(request.url.toString()).equals('https://api.test/me/cars');
    check(request.headers['Authorization']).equals('Bearer tok-1');

    check(cars.length).equals(1);
    check(cars.single.id).equals('c1');
    check(cars.single.registration).equals('DL01AB1234');
    check(cars.single.type).equals(CarType.sedan);
    check(cars.single.transmission).equals(Transmission.manual);
  });

  test(
    'skips malformed or unknown-enum rows instead of failing the list',
    () async {
      final api = _api(
        (_) => http.Response(
          '{"cars":['
          '$_carJson,'
          '{"id":"c2","registration":"DL02XX0002","carType":"rocket",'
          '"transmission":"manual"},'
          '{"registration":"no-id"}'
          ']}',
          200,
        ),
      );

      final cars = await api.list();
      check(cars.length).equals(1);
      check(cars.single.id).equals('c1');
    },
  );

  test('posts a new car and returns the stored car plus the list', () async {
    final captured = <http.Request>[];
    final api = _api(
      (_) => http.Response('{"car":$_carJson,"cars":[$_carJson]}', 200),
      captured: captured,
    );

    final result = await api.add(
      registration: 'DL01AB1234',
      type: CarType.sedan,
      transmission: Transmission.manual,
    );

    final request = captured.single;
    check(request.method).equals('POST');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    check(body['registration']).equals('DL01AB1234');
    check(body['carType']).equals('sedan');
    check(body['transmission']).equals('manual');

    check(result.car.id).equals('c1');
    check(result.cars.length).equals(1);
  });

  test('deletes a car by id and returns the remaining list', () async {
    final captured = <http.Request>[];
    final api = _api(
      (_) => http.Response('{"cars":[]}', 200),
      captured: captured,
    );

    final cars = await api.remove('c1');

    final request = captured.single;
    check(request.method).equals('DELETE');
    check(request.url.toString()).equals('https://api.test/me/cars/c1');
    check(request.headers['Authorization']).equals('Bearer tok-1');
    check(cars).isEmpty();
  });

  test('surfaces the server error message on a non-2xx response', () async {
    final api = _api(
      (_) => http.Response(
        '{"error":"car limit reached; remove a car before adding another"}',
        409,
      ),
    );

    String? message;
    try {
      await api.list();
    } on CarsRequestException catch (e) {
      message = e.message;
    }
    check(
      message,
    ).equals('car limit reached; remove a car before adding another');
  });

  test('throws when the server is unreachable', () async {
    final api = _api((_) => throw Exception('down'));
    await check(api.list()).throws<CarsRequestException>();
  });
}
