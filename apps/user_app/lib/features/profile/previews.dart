import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../auth/domain/auth_user.dart';
import 'view/profile_screen.dart';
import 'view/widgets/user_avatar.dart';

/// Shared Sarthi theme applied to every profile preview.
PreviewThemeData profilePreviewTheme() => PreviewThemeData(
  materialLight: SarthiTheme.light(),
  materialDark: SarthiTheme.dark(),
);

final _sampleUser = AuthUser(
  id: 'u1',
  phoneE164: '+919876543210',
  name: 'Vedanshu Goyal',
  email: 'vedanshu@example.com',
  dateOfBirth: DateTime(2000, 1, 12),
);

@Preview(name: 'Profile', group: 'Profile', theme: profilePreviewTheme)
Widget profilePreview() => ProfileScreen(user: _sampleUser, onLogout: () {});

@Preview(name: 'No logout (read-only)', group: 'Profile', theme: profilePreviewTheme)
Widget profileReadOnlyPreview() => ProfileScreen(user: _sampleUser);

@Preview(name: 'Avatar sizes', group: 'Profile', theme: profilePreviewTheme)
Widget avatarPreview() => const Center(
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      UserAvatar(name: 'Vedanshu Goyal', radius: 16),
      SizedBox(width: 16),
      UserAvatar(name: 'Priya', radius: 24),
      SizedBox(width: 16),
      UserAvatar(name: 'A P J Abdul Kalam', radius: 40),
    ],
  ),
);
