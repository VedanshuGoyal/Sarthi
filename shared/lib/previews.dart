import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'sarthi_shared.dart';

/// Shared Sarthi light/dark theme applied to every component preview.
PreviewThemeData sarthiPreviewTheme() => PreviewThemeData(
  materialLight: SarthiTheme.light(),
  materialDark: SarthiTheme.dark(),
);

@Preview(
  name: 'Primary button — idle',
  group: 'Sarthi UI',
  theme: sarthiPreviewTheme,
)
Widget primaryButtonPreview() => Padding(
  padding: const EdgeInsets.all(16),
  child: SarthiPrimaryButton(label: 'Continue', onPressed: () {}),
);

@Preview(
  name: 'Primary button — loading',
  group: 'Sarthi UI',
  theme: sarthiPreviewTheme,
)
Widget primaryButtonLoadingPreview() => const Padding(
  padding: EdgeInsets.all(16),
  child: SarthiPrimaryButton(
    label: 'Continue',
    onPressed: null,
    isLoading: true,
  ),
);

@Preview(
  name: 'Phone field (+91)',
  group: 'Sarthi UI',
  theme: sarthiPreviewTheme,
)
Widget phoneFieldPreview() =>
    const Padding(padding: EdgeInsets.all(16), child: SarthiPhoneField());

@Preview(
  name: 'Phone field — error',
  group: 'Sarthi UI',
  theme: sarthiPreviewTheme,
)
Widget phoneFieldErrorPreview() => const Padding(
  padding: EdgeInsets.all(16),
  child: SarthiPhoneField(errorText: 'Enter a valid 10-digit number'),
);

@Preview(name: 'Text field', group: 'Sarthi UI', theme: sarthiPreviewTheme)
Widget textFieldPreview() => const Padding(
  padding: EdgeInsets.all(16),
  child: SarthiTextField(label: 'Full name', hintText: 'Asha Sharma'),
);
