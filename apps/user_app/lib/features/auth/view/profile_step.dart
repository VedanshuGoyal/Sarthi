import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../../language/view/language_switch.dart';
import '../auth_providers.dart';
import '../view_model/registration_view_model.dart';
import 'consent_checkbox.dart';

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
      helpText: context.l10n.authDobSelect,
    );
    if (picked == null || !mounted) return;
    ref.read(registrationViewModelProvider).onDateOfBirthChanged(picked);
    _dob.text = _formatDate(context.l10n, picked);
  }

  /// Formats a date as `12 Jan 2000` (`12 जनवरी 2000`) without `intl`.
  static String _formatDate(AppLocalizations l10n, DateTime d) =>
      l10n.fmtDateWithYear(d.day, l10n.monthShort(d.month), d.year);

  /// Which field a server message is about, read from its (English) words;
  /// the app's own validation names its field ([RegistrationViewModel.errorField]).
  static ProfileField? _fieldOf(String message) {
    final error = message.toLowerCase();
    if (error.contains('name')) return ProfileField.name;
    if (error.contains('email')) return ProfileField.email;
    if (error.contains('birth') || error.contains('old')) {
      return ProfileField.dateOfBirth;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(registrationViewModelProvider);
    final l10n = context.l10n;

    // The view model surfaces one error at a time; route it to the field it
    // refers to, falling back to a general message for anything else.
    final errorText = vm.errorText;
    final field =
        vm.errorField ?? (errorText == null ? null : _fieldOf(errorText));
    String? errorFor(ProfileField f) => field == f ? errorText : null;
    final nameError = errorFor(ProfileField.name);
    final emailError = errorFor(ProfileField.email);
    final dobError = errorFor(ProfileField.dateOfBirth);
    final consentError = errorFor(ProfileField.consent);
    final generalError = field == null ? errorText : null;

    // A date picked before a language switch is shown in the new language.
    if (vm.dateOfBirth case final dob?) {
      final shown = _formatDate(l10n, dob);
      if (_dob.text != shown) _dob.text = shown;
    }

    return SarthiFormScaffold(
      leading: BackButton(onPressed: vm.isLoading ? null : vm.back),
      actions: const [LanguageMenuButton()],
      title: l10n.authProfileTitle,
      subtitle: l10n.authProfileSubtitle,
      fields: [
        SarthiTextField(
          label: l10n.authFullName,
          controller: _name,
          autofocus: true,
          hintText: l10n.authFullName,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          errorText: nameError,
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: 20),
        SarthiTextField(
          label: l10n.authEmail,
          controller: _email,
          hintText: l10n.authEmail,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          errorText: emailError,
          prefixIcon: const Icon(Icons.mail_outline),
        ),
        const SizedBox(height: 20),
        SarthiTextField(
          label: l10n.authDateOfBirth,
          controller: _dob,
          hintText: l10n.authDateOfBirth,
          readOnly: true,
          onTap: _pickDate,
          errorText: dobError,
          prefixIcon: const Icon(Icons.cake_outlined),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        const SizedBox(height: 12),
        ConsentCheckbox(
          value: vm.consented,
          onChanged: vm.isLoading ? null : vm.onConsentChanged,
          errorText: consentError,
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
        label: l10n.authCreateAccount,
        isLoading: vm.isLoading,
        onPressed: _submit,
      ),
    );
  }
}
