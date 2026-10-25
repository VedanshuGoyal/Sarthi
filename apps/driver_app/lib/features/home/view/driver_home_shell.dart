import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../account/view/account_panel.dart';
import '../../auth/domain/driver.dart';
import '../../documents/document_providers.dart';
import '../../notifications/notification_providers.dart';
import '../../rides/rides_providers.dart';
import '../../rides/view/earnings_panel.dart';
import '../../rides/view/rides_panel.dart';
import 'duty_panel.dart';

/// The signed-in, verified driver's home: four panels — Home (duty and ride
/// requests), Rides, Earnings and Account.
///
/// Phones get a bottom navigation bar; wide screens (tablets, the web build)
/// a navigation rail, per the responsive-layout guideline. Panels sit in an
/// [IndexedStack] so switching tabs keeps each one's scroll position.
///
/// The shell also owns push registration: a "New ride request" arriving
/// while the app is open refreshes the feed at once, and tapping one opens
/// Home, where the request is.
class DriverHomeShell extends ConsumerStatefulWidget {
  const DriverHomeShell({super.key, required this.driver});

  final Driver driver;

  @override
  ConsumerState<DriverHomeShell> createState() => _DriverHomeShellState();
}

class _DriverHomeShellState extends ConsumerState<DriverHomeShell> {
  static const double _railBreakpoint = 840;

  static const _destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Rides'),
    (
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
      'Earnings',
    ),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  static const int _homeTab = 0;

  final List<StreamSubscription<void>> _push = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);
    _push
      ..add(push.arrivals.listen((_) => _refreshRequests()))
      ..add(push.taps.listen((_) => _openRequests()));
    // Rides and earnings load themselves when first read; the KYC record
    // (for the Account panel) is shared with onboarding, so refresh it here.
    // Deferred: providers can't be written to during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(documentRegistrationViewModelProvider).load();
      unawaited(ref.read(pushRegistrationProvider).start());
      final launchedBy = await push.takeLaunchTap();
      if (launchedBy != null && mounted) _openRequests();
    });
  }

  @override
  void dispose() {
    for (final sub in _push) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Re-reads the open requests now rather than on the next poll. A no-op
  /// while off duty.
  void _refreshRequests() => ref.read(dutyViewModelProvider).refresh();

  void _openRequests() {
    _select(_homeTab);
    _refreshRequests();
  }

  void _select(int index) {
    setState(() => _index = index);
    // Opening Rides or Earnings re-reads them, so they're never stale.
    if (index == 1) ref.read(myRidesViewModelProvider).load();
    if (index == 2) ref.read(earningsViewModelProvider).load();
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final ongoing = ref.watch(
      myRidesViewModelProvider.select((vm) => vm.ongoing.length),
    );
    final requests = ref.watch(
      dutyViewModelProvider.select((vm) => vm.requests.length),
    );

    final panels = IndexedStack(
      index: _index,
      children: [
        DutyPanel(driver: widget.driver),
        const RidesPanel(),
        const EarningsPanel(),
        AccountPanel(driver: widget.driver),
      ],
    );

    Widget icon(int i, {required bool selected}) {
      final (outline, filled, _) = _destinations[i];
      final badge = switch (i) {
        0 => requests,
        1 => ongoing,
        _ => 0,
      };
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
