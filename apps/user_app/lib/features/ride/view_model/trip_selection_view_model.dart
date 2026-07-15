import 'package:flutter/foundation.dart';

import '../domain/trip_type.dart';

/// Drives the post-login "what kind of trip?" chooser.
///
/// A [ChangeNotifier] per the MVVM guideline: it owns the transient selection
/// state — which [TripType] is picked — and exposes command methods the view
/// calls. It holds no business logic and never touches widgets, the network, or
/// storage.
class TripSelectionViewModel extends ChangeNotifier {
  /// [initialType] is a seam used by previews and tests to start with an option
  /// pre-selected; production code uses the default (nothing selected).
  TripSelectionViewModel({TripType? initialType}) : _selectedType = initialType;

  TripType? _selectedType;
  TripType? get selectedType => _selectedType;

  /// True once the customer has picked a trip type — gates the CTA.
  bool get hasSelection => _selectedType != null;

  /// Picks [type]. Tapping the already-selected option is a no-op so we don't
  /// churn listeners.
  void select(TripType type) {
    if (_selectedType == type) return;
    _selectedType = type;
    notifyListeners();
  }
}
