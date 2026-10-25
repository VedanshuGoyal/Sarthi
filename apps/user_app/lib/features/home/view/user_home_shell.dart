import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../core/services/push_service.dart';
import '../../auth/auth_controller.dart';
import '../../auth/auth_providers.dart';
import '../../auth/domain/auth_user.dart';
import '../../notifications/notification_providers.dart';
import '../../profile/view/profile_screen.dart';
import '../../ride/ride_providers.dart';
import '../../ride/view/activity_panel.dart';
import '../../ride/view/rate_ride_sheet.dart';
import '../../ride/view_model/my_bookings_view_model.dart';
import 'home_screen.dart';

/// The signed-in customer's app: three tabs — Home (book a driver),
/// Activity (upcoming and completed rides) and Account.
///
/// Phones get a bottom navigation bar; wide screens (tablets, the web build)
/// a navigation rail, per the responsive-layout guideline. Tabs sit in an
/// [IndexedStack] so switching keeps each one's scroll position. The shell
/// owns the bookings refresh, so Activity and its badge stay current
/// whichever tab is open, and the push registration: a "Driver assigned"
/// notification refreshes the rides at once, and tapping one opens Activity
/// (and that ride, when it's in the list). It also asks for a rating when
/// the bookings view model says a ride is waiting for one — once per ride.
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
  final List<StreamSubscription<void>> _push = [];
  int _index = 0;
  bool _askingForRating = false;

  @override
  void initState() {
    super.initState();
    _bookings = ref.read(myBookingsViewModelProvider)
      ..addListener(_maybeAskForRating);
    final push = ref.read(pushServiceProvider);
    _push
      ..add(push.arrivals.listen((_) => _bookings.load()))
      ..add(push.taps.listen(_openFromPush));
    // Deferred: providers can't notify during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _bookings.startPolling();
      unawaited(ref.read(pushRegistrationProvider).start());
      final launchedBy = await push.takeLaunchTap();
      if (launchedBy != null && mounted) _openFromPush(launchedBy);
    });
  }

  @override
  void dispose() {
    for (final sub in _push) {
      sub.cancel();
    }
    _bookings
      ..removeListener(_maybeAskForRating)
      ..stopPolling();
    super.dispose();
  }

  /// A tapped notification opens Activity, and the ride it's about if it's
  /// in the list (after a refresh, since the push may be news to the list).
  Future<void> _openFromPush(PushEvent event) async {
    _select(_activityTab);
    final rideId = event.rideId;
    if (rideId == null) return;
    await _bookings.load();
    if (!mounted || _bookings.byId(rideId) == null) return;
    await openRideDetails(context, rideId);
  }

  /// Offers the rating sheet for the ride the view model picked — only over
  /// the shell itself (never on top of a booking flow), and once per ride.
  Future<void> _maybeAskForRating() async {
    if (_askingForRating || !mounted) return;
    final ride = _bookings.ratingPrompt;
    if (ride == null || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    _askingForRating = true;
    _bookings.markRatingAsked(ride.id);
    final rated = await showRateRideSheet(context, ride);
    _askingForRating = false;
    if (rated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for rating your trip.')),
      );
    }
  }

  void _select(int index) {
    setState(() => _index = index);
    // Opening Activity re-reads the rides, so it's never stale.
    if (index == _activityTab) _bookings.load();
  }

  /// Stops this phone's notifications and revokes the session on the server
  /// (both best-effort), then wipes it from memory and secure storage —
  /// returning the app to onboarding.
  Future<void> _logout() async {
    await ref
        .read(pushRegistrationProvider)
        .stop()
        .timeout(const Duration(seconds: 5), onTimeout: () {});
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
