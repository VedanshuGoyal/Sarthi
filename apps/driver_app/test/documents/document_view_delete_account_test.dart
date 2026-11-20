import 'package:checks/checks.dart';
import 'package:driver_app/core/location_providers.dart';
import 'package:driver_app/features/account/account_providers.dart';
import 'package:driver_app/core/services/push_service.dart';
import 'package:driver_app/features/auth/data/driver_auth_repository.dart';
import 'package:driver_app/features/auth/data/driver_session_storage.dart';
import 'package:driver_app/features/auth/domain/driver.dart';
import 'package:driver_app/features/auth/domain/driver_auth_session.dart';
import 'package:driver_app/features/auth/driver_auth_controller.dart';
import 'package:driver_app/features/auth/driver_auth_providers.dart';
import 'package:driver_app/features/documents/data/document_file_store.dart';
import 'package:driver_app/features/documents/data/driver_kyc_repository.dart';
import 'package:driver_app/features/documents/document_providers.dart';
import 'package:driver_app/features/documents/domain/document_kind.dart';
import 'package:driver_app/features/documents/domain/driver_kyc.dart';
import 'package:driver_app/features/documents/view/document_view_screen.dart';
import 'package:driver_app/features/documents/view_model/document_registration_view_model.dart';
import 'package:driver_app/features/notifications/notification_providers.dart';
import 'package:driver_app/features/rides/rides_providers.dart';
import 'package:driver_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../rides/fakes.dart';

const _driver = Driver(id: 'd1', phoneE164: '+919800000001', name: 'Ravi');

void main() {
  late _SessionStorage sessions;
  late List<http.Request> requests;
  late _NoCaptures captures;

  setUp(() {
    sessions = _SessionStorage();
    requests = [];
    captures = _NoCaptures();
  });

  Future<void> pump(WidgetTester tester, KycStatus status) async {
    tester.view.physicalSize = const Size(1080, 4400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushServiceProvider.overrideWithValue(PushService.off()),
          kycCaptureStoreProvider.overrideWithValue(captures),
          ridesRepositoryProvider.overrideWithValue(FakeRidesRepository()),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          driverSessionStorageProvider.overrideWithValue(sessions),
          driverAuthRepositoryProvider.overrideWithValue(
            DriverAuthRepository(
              tokenGetter: () => 'tok',
              client: MockClient((request) async {
                requests.add(request);
                return http.Response('{"status":"erased"}', 200);
              }),
            ),
          ),
          documentRegistrationViewModelProvider.overrideWith(
            (ref) => DocumentRegistrationViewModel(
              repository: _KycRepository(status),
              files: captures,
            ),
          ),
        ],
        child: MaterialApp(
          theme: SkylineTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const DocumentViewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a driver waiting on review can delete their account', (
    tester,
  ) async {
    await pump(tester, KycStatus.submitted);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    check(
      find.textContaining('Earnings not yet paid out').evaluate(),
    ).isNotEmpty();

    await tester.tap(find.widgetWithText(TextButton, 'Delete account').last);
    await tester.pumpAndSettle();

    check(requests).length.equals(1);
    check(requests.single)
      ..has((r) => r.method, 'method').equals('DELETE')
      ..has((r) => r.url.path, 'path').equals('/driver/account');
    check(captures.cleared).equals(1);
    check(sessions.cleared).equals(1);
  });

  testWidgets('a verified driver finds it on Account instead', (tester) async {
    await pump(tester, KycStatus.verified);

    check(find.text('Delete account').evaluate()).isEmpty();
  });
}

class _SessionStorage implements DriverSessionStorage {
  int cleared = 0;

  @override
  Future<DriverAuthSession?> read() async => cleared > 0
      ? null
      : const DriverAuthSession(token: 'tok', driver: _driver);

  @override
  Future<void> write(DriverAuthSession session) async {}

  @override
  Future<void> clear() async => cleared++;
}

/// No captures on the device, and no disk I/O (which would never finish
/// inside a widget test's fake clock).
class _NoCaptures extends DocumentFileStore {
  int cleared = 0;

  @override
  Future<String?> pathFor(DocumentKind kind) async => null;

  @override
  Future<void> discard(DocumentKind kind) async {}

  @override
  Future<void> discardAll() async => cleared++;
}

class _KycRepository implements DriverKycRepository {
  _KycRepository(this.status);

  final KycStatus status;

  @override
  Future<DriverKyc> load() async =>
      DriverKyc(status: status, fullName: 'Ravi Kumar');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
