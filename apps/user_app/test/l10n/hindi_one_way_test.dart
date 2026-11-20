// The One-Way steps, the place picker and the map picker in Hindi on narrow
// phones: fails on any layout exception (see test/support/hindi.dart).

import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/ride/data/booking_repository.dart';
import 'package:user_app/features/ride/data/cars_repository.dart';
import 'package:user_app/features/ride/data/location_repository.dart';
import 'package:user_app/features/ride/domain/car.dart';
import 'package:user_app/features/ride/domain/car_type.dart';
import 'package:user_app/features/ride/domain/geo_point.dart';
import 'package:user_app/features/ride/domain/my_booking.dart';
import 'package:user_app/features/ride/domain/pickup_location.dart';
import 'package:user_app/features/ride/domain/place_suggestion.dart';
import 'package:user_app/features/ride/domain/transmission.dart';
import 'package:user_app/features/ride/ride_providers.dart';
import 'package:user_app/features/ride/view/map_pickup_screen.dart';
import 'package:user_app/features/ride/view/one_way_details_screen.dart';
import 'package:user_app/features/ride/view/one_way_review_screen.dart';
import 'package:user_app/features/ride/view/one_way_route_screen.dart';
import 'package:user_app/features/ride/view/pickup_location_screen.dart';
import 'package:user_app/features/ride/view/widgets/map_pin_card.dart';
import 'package:user_app/features/ride/view_model/my_bookings_view_model.dart';
import 'package:user_app/features/ride/view_model/one_way_details_view_model.dart';
import 'package:user_app/features/ride/view_model/one_way_review_view_model.dart';
import 'package:user_app/features/ride/view_model/pickup_selection_view_model.dart';
import 'package:user_app/features/ride/view_model/saved_cars_view_model.dart';
import 'package:user_app/l10n/l10n.dart';

import '../support/fake_booking_server.dart';
import '../support/fake_location_repository.dart';
import '../support/hindi.dart';

const _start = PickupLocation(
  address:
      'Tower B, DLF Cyber City, DLF Phase 2, Sector 24, Gurugram, Haryana '
      '122002',
  point: GeoPoint(latitude: 28.4950, longitude: 77.0895),
);

const _destination = PickupLocation(
  address:
      'Indira Gandhi International Airport Terminal 3, New Delhi, Delhi '
      '110037',
  point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
);

/// Outside Delhi NCR: picking it is refused with the out-of-area note.
const _mumbai = PickupLocation(
  address: 'Chhatrapati Shivaji Maharaj Terminus, Fort, Mumbai, Maharashtra',
  point: GeoPoint(latitude: 18.9398, longitude: 72.8355),
);

const _suggestions = [
  PlaceSuggestion(
    placeId: 'p1',
    primaryText: 'Indira Gandhi International Airport Terminal 3',
    secondaryText: 'New Delhi, Delhi 110037, India',
    address: 'Indira Gandhi International Airport Terminal 3, New Delhi',
    point: GeoPoint(latitude: 28.5562, longitude: 77.1000),
  ),
  PlaceSuggestion(
    placeId: 'p2',
    primaryText: 'Ambience Mall, Ambience Island',
    secondaryText: 'National Highway 48, DLF Phase 3, Gurugram, Haryana',
    address: 'Ambience Mall, Ambience Island, Gurugram',
    point: GeoPoint(latitude: 28.5052, longitude: 77.0970),
  ),
];

const _car = Car(
  id: 'c1',
  registration: 'HR26DQ5551',
  type: CarType.luxury,
  transmission: Transmission.automatic,
);

final _draft = (
  start: _start,
  destination: _destination,
  scheduledAt: DateTime(2030, 9, 18, 21, 45),
  car: _car,
);

/// Drive-time requests that never answer, or ([fail]) fail.
class _Routes extends FakeLocationRepository {
  _Routes({this.fail = false});

  final bool fail;

  @override
  Future<Duration> travelTime({
    required GeoPoint start,
    required GeoPoint destination,
    DateTime? departureAt,
  }) => fail
      ? Future.error(LocationException(L10n.current.locationServiceUnavailable))
      : Completer<Duration>().future;
}

/// [pumpHindi] on a fresh provider scope, so each state starts from its own
/// overrides rather than the view models of the screen pumped before it.
Future<void> _pumpFresh(
  WidgetTester tester,
  Widget home, {
  required double width,
  double height = 720,
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpHindi(
    tester,
    home,
    width: width,
    height: height,
    overrides: overrides,
    settle: settle,
  );
}

/// The customer's rides: one unpaid finished ride and an unpaid
/// cancellation fee, so booking notes what will be added.
MyBookingsViewModel _owing() => MyBookingsViewModel(
  repository: BookingRepository(),
  initialBookings: [
    MyBooking.tryParse(bookingJson(status: 'completed', paymentStatus: 'due'))!,
    MyBooking.tryParse(
      bookingJson(
        id: 'fee',
        status: 'cancelled',
        cancellationFeePaise: 5000,
        paymentStatus: 'due',
      ),
    )!,
  ],
);

List<Override> _oneWay({
  List<Car> cars = const [_car],
  DateTime? scheduledAt,
  Car? car,
  LocationRepository? routes,
  Duration? travelTime,
  bool owing = false,
}) => [
  locationRepositoryProvider.overrideWithValue(
    routes ?? FakeLocationRepository(),
  ),
  savedCarsViewModelProvider.overrideWith(
    (ref) =>
        SavedCarsViewModel(repository: CarsRepository(), initialCars: cars),
  ),
  myBookingsViewModelProvider.overrideWith(
    (ref) =>
        owing ? _owing() : MyBookingsViewModel(repository: BookingRepository()),
  ),
  oneWayDetailsViewModelProvider.overrideWith(
    (ref, route) => OneWayDetailsViewModel(
      route: route,
      initialScheduledAt: scheduledAt,
      initialCar: car,
    ),
  ),
  oneWayReviewViewModelProvider.overrideWith(
    (ref, draft) => OneWayReviewViewModel(
      draft: draft,
      repository: routes,
      initialTravelTime: travelTime,
    ),
  ),
];

/// The place picker over [repo], its search seeded with [query] and
/// [suggestions].
List<Override> _places(
  FakeLocationRepository repo, {
  String query = '',
  List<PlaceSuggestion> suggestions = const [],
}) => [
  locationRepositoryProvider.overrideWithValue(repo),
  pickupSelectionViewModelProvider.overrideWith(
    (ref) => PickupSelectionViewModel(
      repository: ref.watch(locationRepositoryProvider),
      initialQuery: query,
      initialSuggestions: suggestions,
    ),
  ),
];

/// The card [build] makes, in the screen's language, docked at the bottom
/// of an empty screen as over the map.
Widget _docked(MapPinCard Function(AppLocalizations l10n) build) => Scaffold(
  body: Builder(
    builder: (context) =>
        Align(alignment: Alignment.bottomCenter, child: build(context.l10n)),
  ),
);

/// The state really rendered: [text] (in the screen's language) is on it.
void _shows(String text) => check(find.text(text).evaluate()).isNotEmpty();

void main() {
  tearDown(L10n.reset);

  for (final width in hindiWidths) {
    group('Hindi at ${width.toInt()} dp wide:', () {
      testWidgets('the One-Way route step, located or not', (tester) async {
        for (final repo in [
          FakeLocationRepository(current: _start),
          FakeLocationRepository(
            currentError: const LocationPermissionException('declined'),
          ),
        ]) {
          await _pumpFresh(
            tester,
            const OneWayRouteScreen(),
            width: width,
            overrides: _places(
              repo,
              query: 'Airport',
              suggestions: _suggestions,
            ),
          );
          checkHindiFits(tester);
          _shows(L10n.current.oneWayRouteTitle);
          _shows(_suggestions.first.primaryText);
        }
      });

      testWidgets('the One-Way details step: no car, too soon, ready', (
        tester,
      ) async {
        final soon = DateTime.now().add(const Duration(minutes: 20));
        for (final (overrides, shown) in [
          (
            _oneWay(cars: const []),
            (AppLocalizations l) => l.oneWayDetailsChooseCar,
          ),
          (_oneWay(), (AppLocalizations l) => l.oneWayDetailsChooseCar),
          (
            _oneWay(scheduledAt: soon, car: _car),
            (AppLocalizations l) => l.scheduleTooSoon,
          ),
          (_oneWay(car: _car), (AppLocalizations l) => l.oneWayDetailsCarTitle),
        ]) {
          // Tall enough that the sheet builds its car section too.
          await _pumpFresh(
            tester,
            const OneWayDetailsScreen(start: _start, destination: _destination),
            width: width,
            height: 1400,
            overrides: overrides,
          );
          checkHindiFits(tester);
          _shows(shown(L10n.current));
          _shows(L10n.current.oneWayDetailsCarSubtitle);
        }
        // A phone-height screen: the sheet's peek and the Continue bar.
        await _pumpFresh(
          tester,
          const OneWayDetailsScreen(start: _start, destination: _destination),
          width: width,
          overrides: _oneWay(cars: const []),
        );
        checkHindiFits(tester);
      });

      testWidgets('the One-Way review step: estimated, with dues to add', (
        tester,
      ) async {
        await _pumpFresh(
          tester,
          OneWayReviewScreen(draft: _draft),
          width: width,
          overrides: _oneWay(
            travelTime: const Duration(hours: 2, minutes: 45),
            owing: true,
          ),
        );
        checkHindiFits(tester);
        final l10n = L10n.current;
        _shows(l10n.oneWayReviewAbout(l10n.fmtHoursMinutes(2, 45)));
        _shows(l10n.fmtCarriedNote('₹690', 'other'));
      });

      testWidgets('the One-Way review step: estimating, and failed', (
        tester,
      ) async {
        await _pumpFresh(
          tester,
          OneWayReviewScreen(draft: _draft),
          width: width,
          overrides: _oneWay(routes: _Routes()),
          settle: false,
        );
        checkHindiFits(tester);
        _shows(L10n.current.oneWayReviewCheckingDriveTime);

        await _pumpFresh(
          tester,
          OneWayReviewScreen(draft: _draft),
          width: width,
          overrides: _oneWay(routes: _Routes(fail: true)),
        );
        checkHindiFits(tester);
        _shows(L10n.current.oneWayReviewTripTimeFailed);
        _shows(L10n.current.oneWayReviewRetry);
      });

      testWidgets('the place picker: empty, recents, results', (tester) async {
        for (final (repo, query, suggestions, shown) in [
          (
            FakeLocationRepository(),
            '',
            const <PlaceSuggestion>[],
            (AppLocalizations l) => l.pickupEmptyWithLocation,
          ),
          (
            FakeLocationRepository(recents: const [_start, _destination]),
            '',
            const <PlaceSuggestion>[],
            (AppLocalizations l) => l.pickupRecent,
          ),
          (
            FakeLocationRepository(),
            'Airport',
            _suggestions,
            (AppLocalizations l) => _suggestions.last.primaryText,
          ),
        ]) {
          await _pumpFresh(
            tester,
            const PickupLocationScreen(),
            width: width,
            overrides: _places(repo, query: query, suggestions: suggestions),
          );
          checkHindiFits(tester);
          _shows(L10n.current.pickupTitle);
          _shows(shown(L10n.current));
        }
      });

      testWidgets('the place picker with a search error and an '
          'out-of-area pick', (tester) async {
        final repo = FakeLocationRepository(recents: const [_mumbai]);
        await _pumpFresh(
          tester,
          const PickupLocationScreen(),
          width: width,
          overrides: _places(repo),
        );

        // Out of the served area: refused with the long note.
        await tester.tap(find.text(_mumbai.address));
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        _shows(L10n.current.serviceAreaOutside);

        // The maps service failing while searching.
        repo.autocompleteError = LocationException(
          L10n.current.locationServiceUnavailable,
        );
        await tester.enterText(find.byType(TextField), 'Connaught Place');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        checkHindiFits(tester);
        _shows(L10n.current.locationServiceUnavailable);
      });

      testWidgets('the map picker without a map', (tester) async {
        await _pumpFresh(
          tester,
          const MapPickupScreen(),
          width: width,
          overrides: [
            locationRepositoryProvider.overrideWithValue(
              FakeLocationRepository(),
            ),
          ],
        );
        checkHindiFits(tester);
        _shows(L10n.current.mapPickerNotSetUp);
      });

      testWidgets('the map pin card in each state', (tester) async {
        for (final (card, settles, shown)
            in <
              (
                MapPinCard Function(AppLocalizations),
                bool,
                String Function(AppLocalizations),
              )
            >[
              (
                (_) => MapPinCard(
                  label: _start.address,
                  isMoving: false,
                  isResolving: false,
                  canConfirm: true,
                ),
                true,
                (l) => l.mapPickerCaption,
              ),
              (
                (l) => MapPinCard(
                  caption: l.pickupStartField,
                  label: '',
                  isMoving: true,
                  isResolving: false,
                  canConfirm: false,
                ),
                true,
                (l) => l.mapPickerMoveHint,
              ),
              (
                (_) => const MapPinCard(
                  label: '28.4950, 77.0895',
                  isMoving: false,
                  isResolving: true,
                  canConfirm: false,
                ),
                false,
                (l) => l.mapPickerConfirm,
              ),
              (
                (l) => MapPinCard(
                  label: _mumbai.address,
                  isMoving: false,
                  isResolving: false,
                  error: l.serviceAreaOutside,
                  canConfirm: false,
                ),
                true,
                (l) => l.serviceAreaOutside,
              ),
            ]) {
          await _pumpFresh(
            tester,
            _docked(card),
            width: width,
            settle: settles,
          );
          checkHindiFits(tester);
          _shows(shown(L10n.current));
        }
      });
    });
  }
}
