import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';
import 'ride_format.dart';

/// Opens the cancel sheet for [booking], saying cancelling costs [feePaise]
/// (0: free), and resolves with the reason the customer picked once they
/// confirm, or null when they keep the ride. [initialReason] pre-picks the
/// reason given last time, when the sheet is shown again.
Future<String?> showCancelRideSheet(
  BuildContext context,
  MyBooking booking, {
  int feePaise = 0,
  String? initialReason,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CancelRideSheet(
      booking: booking,
      feePaise: feePaise,
      initialReason: initialReason,
    ),
  );
}

/// "Cancel this ride?": what cancelling costs — free before the driver
/// reaches the pickup, [feePaise] once they're there — a warning when a
/// driver is already on it, the reasons to pick from ("Other" opens a text
/// field), and a clear choice between keeping the ride and cancelling it.
/// Pops with the reason on confirm; the caller sends the cancel, agreeing
/// to the fee this sheet showed.
class CancelRideSheet extends StatefulWidget {
  const CancelRideSheet({
    super.key,
    required this.booking,
    this.feePaise = 0,
    this.initialReason,
  });

  final MyBooking booking;

  /// What cancelling now costs, in paise; 0 when it's free.
  final int feePaise;

  /// A reason to start with picked: one of [cancelReasons], or the
  /// customer's own words (which pick "Other").
  final String? initialReason;

  @override
  State<CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends State<CancelRideSheet> {
  String? _reason;
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialReason?.trim();
    if (initial == null || initial.isEmpty) return;
    if (cancelReasons.contains(initial)) {
      _reason = initial;
    } else {
      _reason = otherCancelReason;
      _other.text = initial;
    }
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  bool get _hasFee => widget.feePaise > 0;

  /// What cancelling costs, in one line.
  String get _costLine {
    final b = widget.booking;
    if (_hasFee) {
      final name = b.driverFirstName ?? 'Your driver';
      return '$name has reached your pickup, so cancelling now costs '
          '${RideFormat.rupees(widget.feePaise)}.';
    }
    // At the pickup with no fee: a server without one, or it's waived.
    if (b.status == BookingStatus.arrived) return 'Cancelling is free.';
    return 'Cancelling is free until the driver reaches your pickup. After '
        'that it costs ${RideFormat.rupees(pickupCancellationFeePaise)}.';
  }

  /// What a driver already on the ride means for the customer, if any.
  String? get _driverWarning {
    final b = widget.booking;
    final name = b.driverFirstName ?? 'Your driver';
    if (_hasFee) {
      return "You'll pay the fee by UPI, like a ride, before your next "
          'booking. $name will be told you cancelled.';
    }
    return switch (b.status) {
      BookingStatus.arrived =>
        '$name is already waiting at your pickup. They will be told you '
            'cancelled.',
      BookingStatus.accepted =>
        '$name has accepted this ride and is planning around it. They will '
            'be told you cancelled.',
      _ => null,
    };
  }

  String? get _chosenReason {
    final reason = _reason;
    if (reason != otherCancelReason) return reason;
    final typed = _other.text.trim();
    return typed.isEmpty ? otherCancelReason : typed;
  }

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final warning = _driverWarning;
    return Padding(
      // Keep the "Other" field above the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Skyline.s24,
          0,
          Skyline.s24,
          Skyline.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cancel this ride?', style: t.title(20)),
            const SizedBox(height: Skyline.s4),
            Text(
              _costLine,
              style: _hasFee
                  ? t.title(14, color: t.danger)
                  : t.body(size: 13, color: t.ink),
            ),
            if (warning != null) ...[
              const SizedBox(height: Skyline.s16),
              Container(
                padding: const EdgeInsets.all(Skyline.s12),
                decoration: BoxDecoration(
                  color: t.primarySoft,
                  borderRadius: BorderRadius.circular(Skyline.radius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: t.primaryText,
                    ),
                    const SizedBox(width: Skyline.s8),
                    Expanded(
                      child: Text(
                        warning,
                        style: t.body(size: 13, color: t.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Skyline.s12),
            Text('Tell us why — it helps us improve.', style: t.body(size: 13)),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in cancelReasons)
                    RadioListTile<String>(
                      value: reason,
                      title: Text(reason),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            if (_reason == otherCancelReason) ...[
              const SizedBox(height: Skyline.s4),
              TextField(
                controller: _other,
                autofocus: true,
                maxLength: maxCancelReasonLength,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Tell us more (optional)',
                ),
              ),
            ],
            const SizedBox(height: Skyline.s16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: _reason == null
                  ? null
                  : () => Navigator.of(context).pop(_chosenReason),
              child: Text(
                _hasFee
                    ? 'Cancel and pay ${RideFormat.rupees(widget.feePaise)}'
                    : 'Cancel ride',
              ),
            ),
            const SizedBox(height: Skyline.s8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep my ride'),
            ),
          ],
        ),
      ),
    );
  }
}
