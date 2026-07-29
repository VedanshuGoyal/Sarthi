import 'package:flutter/material.dart';

import '../deep_signal_tokens.dart';
import 'deep_signal_card.dart';

/// **Payment method.** The one inverted card in the set — it flips against the
/// mode: an ink card in light mode, the single pale surface in dark mode. Use it
/// sparingly, as the design intends.
///
/// State-free: pure display of a masked card.
class DeepSignalPaymentMethodCard extends StatelessWidget {
  const DeepSignalPaymentMethodCard({
    super.key,
    required this.maskedNumber,
    required this.holder,
    required this.expiry,
    this.label = 'Payment',
    this.badge = 'Default',
    this.width = 390,
  });

  /// The masked PAN, e.g. "•••• •••• •••• 4172".
  final String maskedNumber;

  /// The cardholder, e.g. "A. Vance".
  final String holder;

  /// The expiry, e.g. "09 / 29".
  final String expiry;

  final String label;
  final String badge;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DeepSignalTokens.of(context);
    return DeepSignalCard(
      width: width,
      color: t.invertedSurface,
      border: Border.all(color: t.invertedSurface),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label.toUpperCase(),
                style: t.mono(
                  size: 9.5,
                  color: t.invertedFgAlpha(0.5),
                  trackingEm: 0.2,
                ),
              ),
              Text(
                badge.toUpperCase(),
                style: t.mono(
                  size: 9.5,
                  color: t.invertedAccent,
                  trackingEm: 0.14,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 26, 0, 20),
            child: Text(
              maskedNumber,
              style: t.mono(size: 22, color: t.invertedFg, trackingEm: 0.14),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                holder.toUpperCase(),
                style: t.mono(color: t.invertedFgAlpha(0.6), trackingEm: 0.14),
              ),
              Text(
                expiry,
                style: t.mono(color: t.invertedFgAlpha(0.6), trackingEm: 0.14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
