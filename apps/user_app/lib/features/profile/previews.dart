import 'package:flutter/widget_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../auth/domain/auth_user.dart';
import '../ride/data/cars_repository.dart';
import '../ride/domain/car.dart';
import '../ride/domain/car_type.dart';
import '../ride/domain/transmission.dart';
import '../ride/ride_providers.dart';
import '../ride/view_model/saved_cars_view_model.dart';
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

const _sampleCars = [
  Car(
    id: 'c1',
    registration: 'DL01AB1234',
    type: CarType.sedan,
    transmission: Transmission.manual,
  ),
  Car(
    id: 'c2',
    registration: 'DL05MN0007',
    type: CarType.suv,
    transmission: Transmission.automatic,
  ),
];

/// Hosts the screen with the "My cars" block seeded so no network or platform
/// storage is touched. The repository is never invoked — the seeded state
/// skips the load.
Widget _profile({List<Car> cars = _sampleCars, VoidCallback? onLogout}) {
  return ProviderScope(
    overrides: [
      savedCarsViewModelProvider.overrideWith(
        (ref) =>
            SavedCarsViewModel(repository: CarsRepository(), initialCars: cars),
      ),
    ],
    child: ProfileScreen(user: _sampleUser, onLogout: onLogout),
  );
}

@Preview(name: 'Profile', group: 'Profile', theme: profilePreviewTheme)
Widget profilePreview() => _profile(onLogout: () {});

@Preview(name: 'No saved cars', group: 'Profile', theme: profilePreviewTheme)
Widget profileNoCarsPreview() => _profile(cars: const [], onLogout: () {});

@Preview(
  name: 'No logout (read-only)',
  group: 'Profile',
  theme: profilePreviewTheme,
)
Widget profileReadOnlyPreview() => _profile();

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
