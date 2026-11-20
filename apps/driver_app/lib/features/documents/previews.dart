import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import 'domain/driver_kyc.dart';
import 'widgets/kyc_status_banner.dart';

/// The driver app's light-only Skyline theme, as in main.dart.
PreviewThemeData documentsPreviewTheme() =>
    PreviewThemeData(materialLight: SkylineTheme.light());

Widget _padded(Widget child) =>
    Padding(padding: const EdgeInsets.all(16), child: child);

@Preview(
  name: 'KYC banner — verified',
  group: 'Documents',
  theme: documentsPreviewTheme,
)
Widget kycBannerVerifiedPreview() => _padded(
  const KycStatusBanner(
    status: KycStatus.verified,
    title: 'Cleared to drive',
    lines: [
      'Aadhaar XXXX XXXX 9012 · verified with DigiLocker',
      'Driving licence DL0120190012345 · verified',
      'Bank account •••• 2345 · verified with your bank',
    ],
  ),
);

@Preview(
  name: 'KYC banner — under review',
  group: 'Documents',
  theme: documentsPreviewTheme,
)
Widget kycBannerSubmittedPreview() => _padded(
  const KycStatusBanner(
    status: KycStatus.submitted,
    title: 'Waiting on a reviewer',
    lines: ['Your selfie is being compared by a person.', 'Sent 20 Nov 2026'],
  ),
);

@Preview(
  name: 'KYC banner — sent back',
  group: 'Documents',
  theme: documentsPreviewTheme,
)
Widget kycBannerRejectedPreview() => _padded(
  const KycStatusBanner(
    status: KycStatus.rejected,
    title: 'Sent back by a reviewer',
    lines: ['The selfie is blurred.'],
  ),
);

@Preview(
  name: 'KYC banner — unknown status',
  group: 'Documents',
  theme: documentsPreviewTheme,
)
Widget kycBannerUnknownPreview() => _padded(
  const KycStatusBanner(
    status: KycStatus.unknown,
    title: 'Status not recognised',
    lines: ['Update the app, or write to team@mojud.life if this stays.'],
  ),
);
