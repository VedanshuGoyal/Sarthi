import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../auth_providers.dart';

/// Step 3 — collect the customer's name, email, and date of birth to create
/// the account.
class ProfileStep extends ConsumerStatefulWidget {
  const ProfileStep({super.key});

  @override
  ConsumerState<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<ProfileStep> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _dob = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _dob.dispose();
    super.dispose();
  }

  void _submit() => ref
      .read(registrationViewModelProvider)
      .submitProfile(name: _name.text, email: _email.text);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = ref.read(registrationViewModelProvider).dateOfBirth;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (picked == null) return;
    ref.read(registrationViewModelProvider).onDateOfBirthChanged(picked);
    _dob.text = _formatDate(picked);
  }

  /// Formats a date as `12 Jan 2000` without pulling in `intl`.
  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(registrationViewModelProvider);

    // The view model surfaces one error at a time; route it to the field it
    // refers to, falling back to a general message for anything else.
    final error = vm.errorText?.toLowerCase();
    final nameError = error != null && error.contains('name')
        ? vm.errorText
        : null;
    final emailError = error != null && error.contains('email')
        ? vm.errorText
        : null;
    final dobError =
        error != null && (error.contains('birth') || error.contains('old'))
        ? vm.errorText
        : null;
    final generalError =
        vm.errorText != null &&
            nameError == null &&
            emailError == null &&
            dobError == null
        ? vm.errorText
        : null;

    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      title: 'Complete your profile',
      subtitle: 'Just a couple of details to finish setting up your account.',
      fields: [
        SarthiTextField(
          label: 'Full name',
          controller: _name,
          autofocus: true,
          hintText: 'Full name',
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          errorText: nameError,
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: 20),
        SarthiTextField(
          label: 'Email',
          controller: _email,
          hintText: 'Email',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          errorText: emailError,
          prefixIcon: const Icon(Icons.mail_outline),
        ),
        const SizedBox(height: 20),
        SarthiTextField(
          label: 'Date of birth',
          controller: _dob,
          hintText: 'Date of birth',
          readOnly: true,
          onTap: _pickDate,
          errorText: dobError,
          prefixIcon: const Icon(Icons.cake_outlined),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        if (generalError != null) ...[
          const SizedBox(height: 16),
          Text(
            generalError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
      footer: SarthiPrimaryButton(
        label: 'Create account',
        isLoading: vm.isLoading,
        onPressed: _submit,
      ),
    );
  }
}
