import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'auth_providers.dart';
import 'data/auth_repository.dart';
import 'view/otp_step.dart';
import 'view/phone_step.dart';
import 'view/profile_step.dart';
import 'view_model/registration_view_model.dart';

/// Shared Sarthi theme applied to every auth-flow preview.
PreviewThemeData authPreviewTheme() => PreviewThemeData(
  materialLight: SarthiTheme.light(),
  materialDark: SarthiTheme.dark(),
);

/// Wraps a step in a Riverpod scope whose view model starts at [step], so each
/// screen can be previewed in isolation without walking the whole flow.
Widget _seeded(RegistrationStep step, Widget child) {
  return ProviderScope(
    overrides: [
      registrationViewModelProvider.overrideWith(
        (ref) => RegistrationViewModel(
          repository: AuthRepository(),
          initialStep: step,
          phoneNational: '9876543210',
        ),
      ),
    ],
    child: child,
  );
}

@Preview(name: '1 · Phone (+91)', group: 'Auth flow', theme: authPreviewTheme)
Widget phoneStepPreview() => _seeded(RegistrationStep.phone, const PhoneStep());

@Preview(name: '2 · OTP', group: 'Auth flow', theme: authPreviewTheme)
Widget otpStepPreview() => _seeded(RegistrationStep.otp, const OtpStep());

@Preview(name: '3 · Name & email', group: 'Auth flow', theme: authPreviewTheme)
Widget profileStepPreview() =>
    _seeded(RegistrationStep.profile, const ProfileStep());
