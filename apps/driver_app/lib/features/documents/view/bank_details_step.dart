import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../document_providers.dart';
import '../domain/document_validators.dart';

/// Document step 6 — where the driver's earnings get paid out.
class BankDetailsStep extends ConsumerStatefulWidget {
  const BankDetailsStep({super.key});

  @override
  ConsumerState<BankDetailsStep> createState() => _BankDetailsStepState();
}

class _BankDetailsStepState extends ConsumerState<BankDetailsStep> {
  final TextEditingController _holderName = TextEditingController();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _confirmAccountNumber = TextEditingController();
  final TextEditingController _ifsc = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // The account number is deliberately not prefilled: the backend encrypts
    // it and returns only the last 4 digits, so there is nothing to restore.
    // Re-entering it is also the point — it's how a typo gets caught.
    final account = ref
        .read(documentRegistrationViewModelProvider)
        .kyc
        .bankAccount;
    _holderName.text = account?.accountHolderName ?? '';
    _ifsc.text = account?.ifscCode ?? '';
  }

  @override
  void dispose() {
    _holderName.dispose();
    _accountNumber.dispose();
    _confirmAccountNumber.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    for (final error in [
      DocumentValidators.bankAccountHolderName(_holderName.text),
      DocumentValidators.bankAccountNumber(_accountNumber.text),
      DocumentValidators.confirmBankAccountNumber(
        _confirmAccountNumber.text,
        _accountNumber.text,
      ),
      DocumentValidators.ifscCode(_ifsc.text),
    ]) {
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }

    final vm = ref.read(documentRegistrationViewModelProvider);
    await vm.setBankDetails(
      accountHolderName: _holderName.text,
      accountNumber: _accountNumber.text,
      ifscCode: _ifsc.text,
    );
    if (!mounted) return;
    if (vm.error != null) {
      setState(() => _error = vm.error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final saved = vm.kyc.bankAccount;

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Bank details',
      subtitle: 'Your earnings are paid out to this account after every trip.',
      fields: [
        SarthiTextField(
          label: 'Account holder name',
          controller: _holderName,
          hintText: 'As it appears on the bank account',
          textCapitalization: TextCapitalization.words,
          prefixIcon: const Icon(Icons.person_outline),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        SarthiTextField(
          label: 'Account number',
          controller: _accountNumber,
          hintText: 'Account number',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(18),
          ],
          prefixIcon: const Icon(Icons.account_balance_outlined),
        ),
        if (saved != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(
            'Currently paying out to the account ending '
            '${saved.accountNumberLast4}. Re-enter the number to change it.',
            style: t.body(size: 12, color: t.muted),
          ),
        ],
        const SizedBox(height: DeepSignalTokens.s14),
        SarthiTextField(
          label: 'Confirm account number',
          controller: _confirmAccountNumber,
          hintText: 'Re-enter account number',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(18),
          ],
          prefixIcon: const Icon(Icons.account_balance_outlined),
        ),
        const SizedBox(height: DeepSignalTokens.s14),
        SarthiTextField(
          label: 'IFSC code',
          controller: _ifsc,
          hintText: 'e.g. HDFC0001234',
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(11)],
          prefixIcon: const Icon(Icons.pin_outlined),
        ),
        if (_error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(_error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: SarthiPrimaryButton(
        label: vm.isSaving ? 'Saving…' : 'Finish',
        onPressed: vm.isSaving ? null : _submit,
      ),
    );
  }
}
