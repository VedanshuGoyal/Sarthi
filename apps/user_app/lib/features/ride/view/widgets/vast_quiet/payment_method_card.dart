import 'package:flutter/material.dart';

import 'vast_quiet_card.dart';
import 'vast_quiet_theme.dart';

/// **1g — Payment method.** The single inverted card in the set: an ink fill
/// with white type and the alpenglow reserved for the "DEFAULT" flag. Use it
/// sparingly — its weight is the point.
///
/// State-free per the reusable-widget guideline: card details in, nothing out.
class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
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

  /// Cardholder, e.g. "A. Vance".
  final String holder;

  /// Expiry, e.g. "09 / 29".
  final String expiry;

  /// The eyebrow label, e.g. "Payment".
  final String label;

  /// The accent flag, e.g. "Default".
  final String badge;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: VastQuietCard(
        color: VastQuiet.ink,
        border: Border.all(color: VastQuiet.ink),
        padding: const EdgeInsets.all(VastQuiet.s22),
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
                  style: VastQuiet.eyebrow(color: VastQuiet.onInk50),
                ),
                Text(
                  badge.toUpperCase(),
                  style: VastQuiet.mono(
                    size: 9.5,
                    color: VastQuiet.alpenglow,
                    trackingEm: 0.14,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text(
                maskedNumber,
                style: VastQuiet.mono(
                  size: 22,
                  color: VastQuiet.onInk,
                  trackingEm: 0.14,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  holder.toUpperCase(),
                  style: VastQuiet.mono(
                    color: VastQuiet.onInk55,
                    trackingEm: 0.14,
                  ),
                ),
                Text(
                  expiry,
                  style: VastQuiet.mono(
                    color: VastQuiet.onInk55,
                    trackingEm: 0.14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
