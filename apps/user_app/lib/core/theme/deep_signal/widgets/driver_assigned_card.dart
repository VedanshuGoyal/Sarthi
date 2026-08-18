import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'deep_signal_card.dart';
import 'deep_signal_hatch.dart';

/// **Driver assigned.** The card shown once a driver accepts: a status eyebrow
/// (the only accent-coloured text here), the driver's identity and vehicle, the
/// plate, and a three-way action bar of equal thirds divided by hairlines.
///
/// State-free per the reusable-widget guideline: driver details in, the three
/// actions out. [photo] is optional; without it a hatched placeholder stands in.
class DeepSignalDriverAssignedCard extends StatelessWidget {
  const DeepSignalDriverAssignedCard({
    super.key,
    required this.status,
    required this.name,
    required this.rating,
    required this.trips,
    required this.vehicle,
    required this.plate,
    required this.onMessage,
    required this.onCall,
    required this.onCancel,
    this.photo,
    this.width = 390,
  });

  /// The accent eyebrow, e.g. "Driver en route".
  final String status;
  final String name;

  /// The rating, e.g. "4.96".
  final String rating;

  /// Trip count, e.g. "2,318".
  final String trips;

  /// Vehicle description, e.g. "Silver Toyota Prius".
  final String vehicle;

  /// Registration plate, e.g. "LM72 KDR".
  final String plate;

  final VoidCallback onMessage;
  final VoidCallback onCall;
  final VoidCallback onCancel;

  /// An optional driver photo; a hatched tile stands in when null.
  final ImageProvider? photo;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
            child: Text(
              status.toUpperCase(),
              style: t.eyebrow(color: t.accent),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              22,
              DeepSignalTokens.s14,
              22,
              20,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PhotoTile(photo: photo),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: t.title(24, height: 1.1)),
                      const SizedBox(height: 5),
                      Text(
                        '$rating ★ · $trips TRIPS',
                        style: t.mono(
                          color: t.muted,
                          trackingEm: 0.12,
                          height: 1.9,
                        ),
                      ),
                      Text(
                        vehicle.toUpperCase(),
                        style: t.mono(
                          color: t.muted,
                          trackingEm: 0.12,
                          height: 1.9,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'PLATE',
                      style: t.mono(color: t.faint, trackingEm: 0.16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plate,
                      style: t.mono(
                        size: 15,
                        color: t.fg,
                        trackingEm: 0.08,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const DeepSignalDivider(),
          IntrinsicHeight(
            child: Row(
              children: [
                _Action(label: 'Message', onTap: onMessage),
                _VDivider(color: t.hairline),
                _Action(label: 'Call', onTap: onCall),
                _VDivider(color: t.hairline),
                _Action(label: 'Cancel', onTap: onCancel, muted: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      VerticalDivider(width: 1, thickness: 1, color: color);
}

/// The 64px hatched (or photographed) driver tile.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: t.hairlineStrong),
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
        image: photo == null
            ? null
            : DecorationImage(image: photo!, fit: BoxFit.cover),
      ),
      child: photo != null
          ? null
          : DeepSignalHatch(
              base: t.raised,
              stripe: t.hairlineStrong,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'PHOTO',
                    style: t.mono(size: 7, color: t.faint, trackingEm: 0.08),
                  ),
                ),
              ),
            ),
    );
  }
}

/// One third of the action bar. [muted] renders the "Cancel" action lighter.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: t.mono(color: muted ? t.label : t.fg, trackingEm: 0.18),
          ),
        ),
      ),
    );
  }
}
