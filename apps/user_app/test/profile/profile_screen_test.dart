import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/auth/domain/auth_user.dart';
import 'package:user_app/features/profile/view/profile_screen.dart';
import 'package:user_app/features/profile/view/widgets/user_avatar.dart';

final _user = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Vedanshu Goyal',
  email: 'vedanshu@example.com',
  dateOfBirth: DateTime(2000, 1, 12),
);

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onLogout,
}) {
  return tester.pumpWidget(
    MaterialApp(home: ProfileScreen(user: _user, onLogout: onLogout)),
  );
}

void main() {
  testWidgets('shows the account details, formatted for reading', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Vedanshu Goyal'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('vedanshu@example.com'), findsOneWidget);
    expect(find.text('12 Jan 2000'), findsOneWidget);
    // The avatar carries the customer's initials.
    expect(find.text('VG'), findsOneWidget);
  });

  testWidgets('tapping Log out emits the event', (tester) async {
    var loggedOut = false;
    await _pump(tester, onLogout: () => loggedOut = true);

    await tester.tap(find.text('Log out'));
    await tester.pump();

    expect(loggedOut, isTrue);
  });

  testWidgets('without a logout handler the button is absent', (tester) async {
    await _pump(tester);

    expect(find.text('Log out'), findsNothing);
  });

  test('initials cover full names, single names, and blanks', () {
    expect(UserAvatar.initials('Vedanshu Goyal'), 'VG');
    expect(UserAvatar.initials('Priya'), 'P');
    expect(UserAvatar.initials('A P J Abdul Kalam'), 'AK');
    expect(UserAvatar.initials('   '), '?');
  });
}
