import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_hatch.dart';
import 'vast_quiet_theme.dart';

/// **1b — Driver assigned.** The card shown once a driver accepts: a status
/// eyebrow (the only accent-coloured text here), the driver's identity and
/// vehicle, the plate, and a three-way action bar of equal thirds divided by
/// hairlines.
///
/// State-free per the reusable-widget guideline: driver details in, the three
/// actions out. [photo] is optional; without it a hatched placeholder stands in.
class DriverAssignedCard extends StatelessWidget {
  const DriverAssignedCard({
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
    return SizedBox(
      width: width,
      child: VastQuietCard(
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              child: Text(
                status.toUpperCase(),
                style: VastQuiet.eyebrow(color: VastQuiet.alpenglow),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, VastQuiet.s14, 22, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoTile(photo: photo),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: VastQuiet.title(24, height: 1.1)),
                        const SizedBox(height: 5),
                        Text(
                          '$rating ★ · $trips TRIPS',
                          style: VastQuiet.mono(
                            color: VastQuiet.ink50,
                            trackingEm: 0.12,
                            height: 1.9,
                          ),
                        ),
                        Text(
                          vehicle.toUpperCase(),
                          style: VastQuiet.mono(
                            color: VastQuiet.ink50,
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
                        style: VastQuiet.mono(
                          color: VastQuiet.ink42,
                          trackingEm: 0.16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        plate,
                        style: VastQuiet.mono(
                          size: 15,
                          color: VastQuiet.ink,
                          trackingEm: 0.08,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const VastQuietDivider(),
            IntrinsicHeight(
              child: Row(
                children: [
                  _Action(label: 'Message', onTap: onMessage),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: VastQuiet.hairline,
                  ),
                  _Action(label: 'Call', onTap: onCall),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: VastQuiet.hairline,
                  ),
                  _Action(label: 'Cancel', onTap: onCancel, muted: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 64px hatched (or photographed) driver tile.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: VastQuiet.hairlineStrong),
        borderRadius: BorderRadius.circular(VastQuiet.radius),
        image: photo == null
            ? null
            : DecorationImage(image: photo!, fit: BoxFit.cover),
      ),
      child: photo != null
          ? null
          : VastQuietHatch(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'PHOTO',
                    style: VastQuiet.mono(
                      size: 7,
                      color: VastQuiet.ink42,
                      trackingEm: 0.08,
                    ),
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
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: VastQuiet.mono(
              color: muted ? VastQuiet.ink45 : VastQuiet.ink,
              trackingEm: 0.18,
            ),
          ),
        ),
      ),
    );
  }
}
