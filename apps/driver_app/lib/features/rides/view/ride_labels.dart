import '../../../l10n/l10n.dart';
import '../domain/ride.dart';

/// The driver-facing words for a ride's values, in the app's language.
/// Pass `context.l10n` from a widget, or `L10n.current` from code without a
/// context.

extension RideStatusText on RideStatus {
  /// Short label for status chips.
  String labelIn(AppLocalizations l10n) => switch (this) {
    RideStatus.requested => l10n.rideStatusRequested,
    RideStatus.accepted => l10n.rideStatusAccepted,
    RideStatus.arrived => l10n.rideStatusArrived,
    RideStatus.inProgress => l10n.rideStatusInProgress,
    RideStatus.completed => l10n.rideStatusCompleted,
    RideStatus.cancelled => l10n.rideStatusCancelled,
    RideStatus.unknown => l10n.rideStatusUnknown,
  };
}

extension TripKindText on TripKind {
  String labelIn(AppLocalizations l10n) => switch (this) {
    TripKind.roundTrip => l10n.tripKindRoundTrip,
    TripKind.oneWay => l10n.tripKindOneWay,
    TripKind.multiStop => l10n.tripKindMultiStop,
    TripKind.other => l10n.tripKindOther,
  };
}

extension RidePaymentStatusText on RidePaymentStatus {
  /// "Awaiting payment", "Paid", "Paid out" — empty when there's nothing to
  /// pay.
  String labelIn(AppLocalizations l10n) => switch (this) {
    RidePaymentStatus.none => '',
    RidePaymentStatus.due => l10n.ridePaymentDue,
    RidePaymentStatus.paid => l10n.ridePaymentPaid,
    RidePaymentStatus.paidOut => l10n.ridePaymentPaidOut,
  };
}

extension RideText on Ride {
  /// The status chip's text: the known label or, for a status this build
  /// doesn't know, the server's own word (`on_hold` → "On hold"), as sent.
  String statusLabelIn(AppLocalizations l10n) {
    final raw = (rawStatus ?? '').replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (status != RideStatus.unknown || raw.isEmpty) {
      return status.labelIn(l10n);
    }
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  /// "Cancelled by customer" ("Customer cancelled at the pickup" when that
  /// cost them a fee), "Customer didn't come" or "Cancelled".
  String cancelLabelIn(AppLocalizations l10n) => switch (cancelledBy) {
    'customer' when hasCancellationFee => l10n.rideCancelledAtPickup,
    'customer' => l10n.rideCancelledByCustomer,
    'no_show' => l10n.rideCancelledNoShow,
    _ => l10n.rideStatusCancelled,
  };
}

extension RideCarText on RideCar {
  /// The car's type: a known one in the app's language, a newer server's
  /// as sent ("Coupe"), or "Car" when there's none.
  String carTypeLabelIn(AppLocalizations l10n) => switch (carType) {
    'hatchback' => l10n.carTypeHatchback,
    'sedan' => l10n.carTypeSedan,
    'suv' => l10n.carTypeSuv,
    'luxury' => l10n.carTypeLuxury,
    '' => l10n.carTypeUnknown,
    _ => '${carType[0].toUpperCase()}${carType.substring(1)}',
  };

  /// "Manual" / "Automatic", or empty when unknown.
  String transmissionLabelIn(AppLocalizations l10n) => switch (transmission) {
    'manual' => l10n.transmissionManual,
    'automatic' => l10n.transmissionAutomatic,
    _ => '',
  };
}
