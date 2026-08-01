import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../auth_providers.dart';
import '../view_model/registration_view_model.dart';

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
      ref.read(registrationViewModelProvider).submitOtp(_controller.text);

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(registrationViewModelProvider);
    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      title: 'Verify your number',
      subtitle: 'Enter the ${vm.otpLength}-digit code sent to ${vm.phoneE164}.',
      fields: [
        SarthiTextField(
          label: 'Verification code',
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
        label: 'Verify',
        isLoading: vm.isLoading,
        // A dead OTP can't be verified — the user must start over.
        onPressed: vm.isOtpInvalidated ? null : _submit,
      ),
    );
  }

  /// The "resend / locked / invalidated" area beneath the code field, chosen by
  /// the current OTP-session state.
  Widget _resendSection(BuildContext context, RegistrationViewModel vm) {
    final theme = Theme.of(context);

    // Terminal state: too many wrong codes — offer a fresh start.
    if (vm.isOtpInvalidated) {
      return _Notice(
        message: 'That code is no longer valid. Request a new one to continue.',
        actionLabel: 'Start over',
        onAction: vm.isLoading ? null : vm.back,
      );
    }

    // Resend cap hit: locked until the countdown clears, or restart now.
    if (vm.isResendLocked) {
      return _Notice(
        message:
            'Too many code requests. Try again in '
            '${_formatCountdown(vm.resendCountdown)}, or start over.',
        actionLabel: 'Start over',
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
          "Didn't get it?",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (vm.canResend)
          TextButton(
            onPressed: vm.isLoading ? null : vm.resendOtp,
            child: const Text('Resend code'),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Resend code in ${_formatCountdown(vm.resendCountdown)}',
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
