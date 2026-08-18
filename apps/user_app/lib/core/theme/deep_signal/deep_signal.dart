/// The **Deep Signal** design system — the two-mode (light + dark) ride-card
/// language for the Sarthi customer app.
///
/// Import this barrel to pull in the tokens ([DeepSignalTokens]), the two-mode
/// [DeepSignalTheme], and every card. Wrap the app in [DeepSignalTheme.light] /
/// [DeepSignalTheme.dark] (see `main.dart`) so Material widgets and cards alike
/// adopt the language, and read raw tokens with `DeepSignalTokens.of(context)`.
library;

export 'package:sarthi_shared/sarthi_shared.dart'
    show DeepSignalTheme, DeepSignalTokens;

export 'widgets/deep_signal_card.dart';
export 'widgets/deep_signal_hatch.dart';
export 'widgets/driver_assigned_card.dart';
export 'widgets/fare_breakdown_card.dart';
export 'widgets/finding_driver_skeleton.dart';
export 'widgets/payment_method_card.dart';
export 'widgets/rate_and_tip_card.dart';
export 'widgets/ride_class_picker.dart';
export 'widgets/saved_places_card.dart';
export 'widgets/surge_notice_card.dart';
export 'widgets/trip_history_card.dart';
export 'widgets/trip_progress_sheet.dart';
