import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/view/widgets/driver_row.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';

import '../support/fake_booking_server.dart';

/// A 1×1 PNG, for an image that decodes.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

MyBooking _withPhoto(String? version) {
  final json = bookingJson();
  final driver = json['driver'] as Map;
  if (version != null) driver['photoVersion'] = version;
  return MyBooking.tryParse(json)!;
}

void main() {
  test('reads the driver photo version, ignoring an empty one', () {
    check(_withPhoto('3f9a0c1b2d4e').driverPhotoVersion).equals('3f9a0c1b2d4e');
    check(_withPhoto(null).driverPhotoVersion).isNull();
    check(_withPhoto('').driverPhotoVersion).isNull();
  });

  test('the photo is fetched with the session token, keyed by version', () {
    final repository = BookingRepository(
      baseUrl: 'https://api.example',
      tokenGetter: () => 'tok',
    );
    final photo = repository.driverPhoto('b 1', 'v2') as NetworkImage;
    check(
      photo.url,
    ).equals('https://api.example/me/bookings/b%201/driver-photo?v=v2');
    check(
      photo.headers,
    ).isNotNull().deepEquals({'Authorization': 'Bearer tok'});
  });

  test('no photo version, no photo', () {
    final vm = MyBookingsViewModel(repository: BookingRepository());
    addTearDown(vm.dispose);
    check(vm.driverPhoto(_withPhoto(null))).isNull();
    check(vm.driverPhoto(_withPhoto('v1'))).isNotNull();
  });

  Future<void> pumpAvatar(WidgetTester tester, ImageProvider? photo) =>
      tester.pumpWidget(
        MaterialApp(
          theme: SkylineTheme.light(),
          home: Scaffold(
            body: DriverAvatar(name: 'ravi', photo: photo),
          ),
        ),
      );

  testWidgets('without a photo the avatar is the initial', (tester) async {
    await pumpAvatar(tester, null);
    check(find.text('R').evaluate()).isNotEmpty();
    check(find.byType(Image).evaluate()).isEmpty();
  });

  testWidgets('a photo replaces the initial once it loads', (tester) async {
    final photo = MemoryImage(_pixel);
    await tester.runAsync(() async {
      await pumpAvatar(tester, photo);
      await precacheImage(photo, tester.element(find.byType(DriverAvatar)));
    });
    await tester.pump();
    check(find.byType(Image).evaluate()).isNotEmpty();
    check(find.text('R').evaluate()).isEmpty();
  });

  testWidgets('a photo that fails to load falls back to the initial', (
    tester,
  ) async {
    final broken = MemoryImage(Uint8List.fromList([1, 2, 3]));
    await tester.runAsync(() async {
      await pumpAvatar(tester, broken);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    check(find.text('R').evaluate()).isNotEmpty();
  });
}
