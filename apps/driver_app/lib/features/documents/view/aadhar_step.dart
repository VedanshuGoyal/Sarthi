import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../document_providers.dart';
import '../domain/document_validators.dart';
import '../widgets/verified_details.dart';

/// Document step 3 — the Aadhar number, then a DigiLocker sign-in that proves
/// it's the driver's.
///
/// DigiLocker opens in a browser tab. When the driver comes back to the app
/// the result is read from the backend straight away; the "I've finished"
/// button is there for when that first read is too early.
class AadharStep extends ConsumerStatefulWidget {
  const AadharStep({super.key});

  @override
  ConsumerState<AadharStep> createState() => _AadharStepState();
}

class _AadharStepState extends ConsumerState<AadharStep> {
  final TextEditingController _number = TextEditingController();
  late final AppLifecycleListener _lifecycle;

  /// DigiLocker is open (or was) and the result hasn't been read yet.
  bool _waiting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _number.dispose();
    super.dispose();
  }

  void _onResume() {
    if (_waiting) _complete();
  }

  Future<void> _verify() async {
    final vm = ref.read(documentRegistrationViewModelProvider);

    // The number is only re-sent when the driver typed one. Once it's saved
    // the backend keeps just the last 4 digits, so an untouched field means
    // "leave it as it is", not "clear it".
    final typed = _number.text.trim();
    if (typed.isNotEmpty || vm.kyc.aadhaarLast4 == null) {
      final numberError = DocumentValidators.aadharNumber(typed);
      if (numberError != null) {
        setState(() => _error = numberError);
        return;
      }
      await vm.setAadhar(number: typed);
      if (vm.error != null) {
        setState(() => _error = vm.error);
        return;
      }
      _number.clear();
    }

    final session = await vm.startDigiLocker();
    if (!mounted) return;
    if (session == null) {
      setState(() => _error = vm.error);
      return;
    }

    final opened = await launchUrl(
      session.url,
      mode: LaunchMode.inAppBrowserView,
    );
    if (!mounted) return;
    setState(() {
      _waiting = opened;
      _error = opened ? null : "Couldn't open DigiLocker. Try again.";
    });
  }

  Future<void> _complete() async {
    final vm = ref.read(documentRegistrationViewModelProvider);
    if (vm.isSaving) return;

    final verified = await vm.completeDigiLocker();
    if (!mounted) return;
    setState(() {
      if (verified) {
        _waiting = false;
        _error = null;
        return;
      }
      // Still in DigiLocker: keep waiting. Anything else ends this session,
      // and the driver starts a new one.
      final pending = vm.errorCode == 'verification_pending';
      _waiting = pending;
      _error = pending ? 'Finish the steps in DigiLocker first.' : vm.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final kyc = vm.kyc;
    final last4 = kyc.aadhaarLast4;
    final dob = kyc.dateOfBirth;

    final Widget footer;
    if (kyc.isAadhaarVerified) {
      footer = SarthiPrimaryButton(
        label: 'Continue',
        onPressed: () => Navigator.of(context).pop(),
      );
    } else if (_waiting) {
      footer = SarthiPrimaryButton(
        label: vm.isSaving ? 'Checking…' : "I've finished in DigiLocker",
        onPressed: vm.isSaving ? null : _complete,
      );
    } else {
      footer = SarthiPrimaryButton(
        label: vm.isSaving ? 'Opening DigiLocker…' : 'Verify with DigiLocker',
        onPressed: vm.isSaving ? null : _verify,
      );
    }

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: 'Aadhar card',
      subtitle: kyc.isAadhaarVerified
          ? 'Your Aadhar is verified.'
          : 'Enter your Aadhar number, then sign in to DigiLocker to verify it.',
      fields: [
        if (kyc.isAadhaarVerified)
          VerifiedDetails(
            title: 'Verified with DigiLocker',
            lines: [
              kyc.fullName,
              if (dob != null) 'Born ${formatCardDate(dob)}',
              if (last4 != null) 'Aadhar XXXX XXXX $last4',
            ],
          )
        else ...[
          SarthiTextField(
            label: 'Aadhar number',
            controller: _number,
            readOnly: _waiting,
            hintText: last4 == null ? 'XXXX XXXX XXXX' : 'XXXX XXXX $last4',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            prefixIcon: const Icon(Icons.credit_card_outlined),
          ),
          if (last4 != null && !_waiting) ...[
            const SizedBox(height: DeepSignalTokens.s8),
            Text(
              'Saved. Leave this blank unless you need to change it.',
              style: t.body(size: 12, color: t.muted),
            ),
          ],
          if (_waiting) ...[
            const SizedBox(height: DeepSignalTokens.s14),
            Text(
              'Finish in DigiLocker, then come back here.',
              style: t.body(size: 13, color: t.muted),
            ),
            TextButton(
              onPressed: vm.isSaving ? null : _verify,
              child: const Text('Open DigiLocker again'),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(_error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: footer,
    );
  }
}
