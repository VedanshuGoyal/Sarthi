import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../domain/my_booking.dart';

/// Opens the cancel sheet for [booking] and resolves with the reason the
/// customer picked once they confirm, or null when they keep the ride.
Future<String?> showCancelRideSheet(BuildContext context, MyBooking booking) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CancelRideSheet(booking: booking),
  );
}

/// "Cancel this ride?": a warning when a driver is already on it, the
/// reasons to pick from ("Other" opens a text field), and a clear choice
/// between keeping the ride and cancelling it. Pops with the reason on
/// confirm; the caller sends the cancel.
class CancelRideSheet extends StatefulWidget {
  const CancelRideSheet({super.key, required this.booking});

  final MyBooking booking;

  @override
  State<CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends State<CancelRideSheet> {
  String? _reason;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  /// What a driver already on the ride means for the customer, if any.
  String? get _driverWarning {
    final b = widget.booking;
    final name = b.driverFirstName ?? 'Your driver';
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
              "Cancelling is free. Tell us why — it helps us improve.",
              style: t.body(size: 13),
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
            const SizedBox(height: Skyline.s8),
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
              child: const Text('Cancel ride'),
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
