import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../profile/view/profile_screen.dart';
import '../../ride/ride_providers.dart';
import '../../ride/view/activity_panel.dart';
import '../../ride/view_model/my_bookings_view_model.dart';
import 'home_screen.dart';

/// The signed-in customer's app: three tabs — Home (book a driver),
/// Activity (upcoming and completed rides) and Account.
///
/// Phones get a bottom navigation bar; wide screens (tablets, the web build)
/// a navigation rail, per the responsive-layout guideline. Tabs sit in an
/// [IndexedStack] so switching keeps each one's scroll position. The shell
/// owns the bookings refresh, so Activity and its badge stay current
/// whichever tab is open.
class UserHomeShell extends ConsumerStatefulWidget {
  const UserHomeShell({super.key, required this.user});

  final AuthUser user;

  @override
  ConsumerState<UserHomeShell> createState() => _UserHomeShellState();
}

class _UserHomeShellState extends ConsumerState<UserHomeShell> {
  static const double _railBreakpoint = 840;

  static const int _activityTab = 1;
  static const int _accountTab = 2;

  static const _destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  late final MyBookingsViewModel _bookings;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _bookings = ref.read(myBookingsViewModelProvider);
    // Deferred: providers can't notify during a build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _bookings.startPolling(),
    );
  }

  @override
  void dispose() {
    _bookings.stopPolling();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _index = index);
    // Opening Activity re-reads the rides, so it's never stale.
    if (index == _activityTab) _bookings.load();
  }

  /// Revokes the session on the server (best-effort), then wipes it from memory
  /// and secure storage — returning the app to onboarding.
  Future<void> _logout() async {
    final auth = ref.read(authControllerProvider.notifier);
    final token = auth.token;
    if (token != null) {
      try {
        await ref.read(authRepositoryProvider).logout(token);
      } catch (_) {
        // Already clearing locally; a failed server revoke shouldn't block it.
      }
    }
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final upcoming = ref.watch(
      myBookingsViewModelProvider.select((vm) => vm.active.length),
    );

    final panels = IndexedStack(
      index: _index,
      children: [
        HomeScreen(
          user: widget.user,
          onOpenAccount: () => _select(_accountTab),
        ),
        const ActivityPanel(),
        ProfileScreen(user: widget.user, onLogout: _logout),
      ],
    );

    Widget icon(int i, {required bool selected}) {
      final (outline, filled, _) = _destinations[i];
      final badge = i == _activityTab ? upcoming : 0;
      return Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: t.signal,
        child: Icon(selected ? filled : outline),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _railBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: t.surface,
                  indicatorColor: t.primarySoft,
                  destinations: [
                    for (final (i, (_, _, label)) in _destinations.indexed)
                      NavigationRailDestination(
                        icon: icon(i, selected: false),
                        selectedIcon: icon(i, selected: true),
                        label: Text(label),
                      ),
                  ],
                ),
                VerticalDivider(width: 1, color: t.hairline),
                Expanded(child: panels),
              ],
            ),
          );
        }
        return Scaffold(
          body: panels,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            backgroundColor: t.surface,
            indicatorColor: t.primarySoft,
            surfaceTintColor: Colors.transparent,
            destinations: [
              for (final (i, (_, _, label)) in _destinations.indexed)
                NavigationDestination(
                  icon: icon(i, selected: false),
                  selectedIcon: icon(i, selected: true),
                  label: label,
                ),
            ],
          ),
        );
      },
    );
  }
}
