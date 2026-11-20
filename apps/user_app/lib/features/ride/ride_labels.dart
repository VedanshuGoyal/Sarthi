import '../../l10n/l10n.dart';
import 'domain/car_type.dart';
import 'domain/my_booking.dart';
import 'domain/transmission.dart';
import 'domain/trip_type.dart';

/// The customer-facing words for a booking's values, in the app's language.
/// Pass `context.l10n` from a widget, or `L10n.current` from code without a
/// context. The domain types stay word-free.

extension TripTypeText on TripType {
  /// "One-Way", "Round Trip", "Multi-Stop".
  String labelIn(AppLocalizations l10n) => switch (this) {
    TripType.oneWay => l10n.tripTypeOneWay,
    TripType.roundTrip => l10n.tripTypeRoundTrip,
    TripType.multiStop => l10n.tripTypeMultiStop,
  };
}

extension BookingStatusText on BookingStatus {
  /// What the customer sees on the status pill: "Finding a driver", …
  String labelIn(AppLocalizations l10n) => switch (this) {
    BookingStatus.requested => l10n.bookingStatusRequested,
    BookingStatus.accepted => l10n.bookingStatusAccepted,
    BookingStatus.arrived => l10n.bookingStatusArrived,
    BookingStatus.inProgress => l10n.bookingStatusInProgress,
    BookingStatus.completed => l10n.bookingStatusCompleted,
    BookingStatus.cancelled => l10n.bookingStatusCancelled,
    BookingStatus.expired => l10n.bookingStatusExpired,
  };
}

extension CarTypeText on CarType {
  String labelIn(AppLocalizations l10n) => switch (this) {
    CarType.hatchback => l10n.carTypeHatchback,
    CarType.sedan => l10n.carTypeSedan,
    CarType.suv => l10n.carTypeSuv,
    CarType.luxury => l10n.carTypeLuxury,
  };
}

extension TransmissionText on Transmission {
  String labelIn(AppLocalizations l10n) => switch (this) {
    Transmission.automatic => l10n.transmissionAutomatic,
    Transmission.manual => l10n.transmissionManual,
  };
}

/// A cancel reason in the app's language: one of [cancelReasons] (which go
/// to the server in English, as the driver and the MOJUD team read them) in
/// the customer's words, or — typed by the customer — as written.
String cancelReasonLabel(String reason, AppLocalizations l10n) =>
    switch (reason) {
      'Plans changed' => l10n.cancelReasonPlansChanged,
      'Booked by mistake' => l10n.cancelReasonBookedByMistake,
      'Driver asked me to cancel' => l10n.cancelReasonDriverAsked,
      'Driver is not responding' => l10n.cancelReasonDriverNotResponding,
      'Found another option' => l10n.cancelReasonFoundAnotherOption,
      otherCancelReason => l10n.cancelReasonOther,
      _ => reason,
    };

extension MyBookingText on MyBooking {
  /// "Cancelled by you" and the like, or null when the server didn't say.
  String? cancelledByLabelIn(AppLocalizations l10n) => switch (cancelledBy) {
    null || '' => null,
    'customer' => l10n.bookingCancelledByYou,
    'driver' => l10n.bookingCancelledByDriver,
    // The driver waited at the pickup and the customer never came.
    'no_show' => l10n.bookingCancelledNoShow,
    _ => l10n.bookingStatusCancelled,
  };

  /// Who cancelled and why, on one line — "Cancelled by you · Plans
  /// changed"; null when the server said neither.
  String? cancellationSummaryIn(AppLocalizations l10n) {
    final who = cancelledByLabelIn(l10n);
    final why = cancelReason?.trim() ?? '';
    final reason = why.isEmpty ? null : cancelReasonLabel(why, l10n);
    return switch ((who, reason)) {
      (final who?, final reason?) => l10n.bookingCancelledSummary(who, reason),
      (final who?, null) => who,
      (null, final reason?) => reason,
      (null, null) => null,
    };
  }
}

extension RidePaymentText on RidePayment {
  /// How the customer paid, in words: "UPI", "Cash", "Waived by MOJUD", or
  /// the gateway's own mode made readable ("NET_BANKING" → "Net Banking").
  String modeLabelIn(AppLocalizations l10n) {
    final m = mode.trim().toUpperCase();
    if (m.isEmpty || m.startsWith('UPI')) return l10n.paymentModeUpi;
    if (m == 'CASH') return l10n.paymentModeCash;
    if (m == 'WAIVED') return l10n.paymentModeWaived;
    return [
      for (final word in m.split('_'))
        if (word.isNotEmpty) '${word[0]}${word.substring(1).toLowerCase()}',
    ].join(' ');
  }
}

extension PaymentLineText on PaymentLine {
  /// The server's short label for the line ("Round trip · Tue 17 Nov"), as
  /// sent; without one, what it was for: "Ride" / "Cancellation fee".
  String labelIn(AppLocalizations l10n) =>
      label ??
      switch (kind) {
        PaymentLineKind.ride => l10n.paymentLineRide,
        PaymentLineKind.cancellationFee => l10n.paymentLineCancellationFee,
      };
}
