import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../document_providers.dart';

/// Document step 5 — the three OS permissions the "Go Online" flow depends
/// on: ride alerts drawn over other apps, GPS streaming while backgrounded,
/// and running unrestricted by battery optimization.
///
/// "Display over other apps" and "battery usage" are Android-only concepts —
/// on iOS those rows are marked not applicable and don't block completion.
class PermissionsStep extends ConsumerStatefulWidget {
  const PermissionsStep({super.key});

  @override
  ConsumerState<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<PermissionsStep> {
  late bool _overlay;
  late bool _backgroundLocation;
  late bool _battery;

  bool get _overlayApplicable => !kIsWeb && Platform.isAndroid;
  bool get _batteryApplicable => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    final data = ref.read(documentRegistrationViewModelProvider).data;
    _overlay = data.overlayPermissionGranted || !_overlayApplicable;
    _backgroundLocation = data.backgroundLocationGranted;
    _battery = data.batteryUnrestricted || !_batteryApplicable;
    _refreshFromOs();
  }

  /// Reconciles with the real OS state (a driver may have granted these
  /// outside the app, or revoked one from system settings since last time).
  Future<void> _refreshFromOs() async {
    final backgroundLocation = await Permission.locationAlways.status;
    final overlay = _overlayApplicable
        ? await Permission.systemAlertWindow.status
        : null;
    final battery = _batteryApplicable
        ? await Permission.ignoreBatteryOptimizations.status
        : null;
    if (!mounted) return;
    setState(() {
      _backgroundLocation = _backgroundLocation || backgroundLocation.isGranted;
      if (overlay != null) _overlay = _overlay || overlay.isGranted;
      if (battery != null) _battery = _battery || battery.isGranted;
    });
  }

  Future<void> _requestOverlay() async {
    final status = await Permission.systemAlertWindow.request();
    if (!mounted) return;
    setState(() => _overlay = status.isGranted);
  }

  Future<void> _requestBackgroundLocation() async {
    // Android/iOS both require foreground location granted before "always"
    // can be requested — the OS silently ignores it otherwise.
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) return;
    final status = await Permission.locationAlways.request();
    if (!mounted) return;
    setState(() => _backgroundLocation = status.isGranted);
  }

  Future<void> _requestBattery() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (!mounted) return;
    setState(() => _battery = status.isGranted);
  }

  bool get _allGranted => _overlay && _backgroundLocation && _battery;

  void _submit() {
    ref
        .read(documentRegistrationViewModelProvider)
        .setPermissions(
          overlayGranted: _overlay,
          backgroundLocationGranted: _backgroundLocation,
          batteryUnrestricted: _battery,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Permissions',
      subtitle:
          "Turn these on so ride offers reach you even when Sarthi Driver "
          "isn't the app on screen.",
      fields: [
        _PermissionRow(
          icon: Icons.picture_in_picture_alt_outlined,
          title: 'Display over other apps',
          subtitle: 'Shows ride alerts on top of whatever app you\'re using.',
          granted: _overlay,
          applicable: _overlayApplicable,
          onTurnOn: _requestOverlay,
        ),
        const SizedBox(height: DeepSignalTokens.s8),
        _PermissionRow(
          icon: Icons.location_on_outlined,
          title: 'Background location',
          subtitle: 'Streams your GPS to riders and dispatch while online.',
          granted: _backgroundLocation,
          applicable: true,
          onTurnOn: _requestBackgroundLocation,
        ),
        const SizedBox(height: DeepSignalTokens.s8),
        _PermissionRow(
          icon: Icons.battery_charging_full_outlined,
          title: 'Battery usage',
          subtitle: 'Stops the OS from pausing location updates to save power.',
          granted: _battery,
          applicable: _batteryApplicable,
          onTurnOn: _requestBattery,
        ),
      ],
      footer: SarthiPrimaryButton(
        label: 'Finish',
        onPressed: _allGranted ? _submit : null,
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.applicable,
    required this.onTurnOn,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool applicable;
  final Future<void> Function() onTurnOn;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);

    return Container(
      padding: const EdgeInsets.all(DeepSignalTokens.s14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: granted ? t.accentBorder : t.hairline),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
      ),
      child: Row(
        children: [
          Icon(icon, color: granted ? t.accent : t.muted, size: 22),
          const SizedBox(width: DeepSignalTokens.s14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.title(15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  applicable ? subtitle : 'Not required on this device',
                  style: t.body(size: 13, color: t.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: DeepSignalTokens.s8),
          if (!applicable)
            Icon(Icons.check_circle, color: t.accent, size: 22)
          else if (granted)
            Icon(Icons.check_circle, color: t.accent, size: 22)
          else
            TextButton(onPressed: onTurnOn, child: const Text('Turn on')),
        ],
      ),
    );
  }
}
