import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../driver_auth_providers.dart';
import '../view_model/driver_registration_view_model.dart';

/// Formats remaining [seconds] as `m:ss`, e.g. 60 → `1:00`, 9 → `0:09`.
String _formatCountdown(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// Step 2 — verify the number with the one-time code.
class OtpStep extends ConsumerStatefulWidget {
  const OtpStep({super.key});

  @override
  ConsumerState<OtpStep> createState() => _OtpStepState();
}

class _OtpStepState extends ConsumerState<OtpStep> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      ref.read(driverRegistrationViewModelProvider).submitOtp(_controller.text);

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(driverRegistrationViewModelProvider);
    final l10n = context.l10n;
    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      title: l10n.otpTitle,
      subtitle: l10n.otpSubtitle(vm.otpLength, vm.phoneE164),
      fields: [
        SarthiTextField(
          label: l10n.otpFieldLabel,
          controller: _controller,
          autofocus: true,
          hintText: '••••••',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          errorText: vm.errorText,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(vm.otpLength),
          ],
          onChanged: vm.onOtpChanged,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        _resendSection(context, vm),
      ],
      footer: SarthiPrimaryButton(
        label: l10n.otpVerify,
        isLoading: vm.isLoading,
        // A dead OTP can't be verified — the driver must start over.
        onPressed: vm.isOtpInvalidated ? null : _submit,
      ),
    );
  }

  /// The "resend / locked / invalidated" area beneath the code field, chosen by
  /// the current OTP-session state.
  Widget _resendSection(BuildContext context, DriverRegistrationViewModel vm) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Terminal state: too many wrong codes — offer a fresh start.
    if (vm.isOtpInvalidated) {
      return _Notice(
        message: l10n.otpInvalidated,
        actionLabel: l10n.otpStartOver,
        onAction: vm.isLoading ? null : vm.back,
      );
    }

    // Resend cap hit: locked until the countdown clears, or restart now.
    if (vm.isResendLocked) {
      return _Notice(
        message: l10n.otpResendLocked(_formatCountdown(vm.resendCountdown)),
        actionLabel: l10n.otpStartOver,
        onAction: vm.isLoading ? null : vm.back,
      );
    }

    // Normal case: a resend button once the cooldown elapses, else a countdown.
    // A Wrap (not a Row) lets the label and control reflow onto a second line on
    // narrow screens instead of overflowing.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.otpDidntGetIt,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (vm.canResend)
          TextButton(
            onPressed: vm.isLoading ? null : vm.resendOtp,
            child: Text(l10n.otpResend),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              l10n.otpResendIn(_formatCountdown(vm.resendCountdown)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A short explanatory line with a single trailing action, used for the OTP
/// lockout and invalidation states.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}
