/// Sarthi shared design system.
///
/// A single source of truth for the look and feel that both the customer
/// ([user_app]) and driver ([driver_app]) apps share: the Deep Signal
/// two-mode theme (`DeepSignalTheme` + `DeepSignalTokens` + the
/// `ThemeModeController` that switches between them), the legacy ultramarine
/// [SarthiTheme], and a small kit of reusable, state-free widgets (buttons,
/// text fields, the +91 phone field).
///
/// Widgets here only render data and emit events through callbacks — they hold
/// no business logic and never touch the network, disk, or plugins.
library;

export 'src/theme/sarthi_colors.dart';
export 'src/theme/sarthi_theme.dart';
export 'src/theme/deep_signal/deep_signal_theme.dart';
export 'src/theme/deep_signal/deep_signal_tokens.dart';
export 'src/theme/theme_mode_controller.dart';
export 'src/widgets/sarthi_primary_button.dart';
export 'src/widgets/sarthi_text_field.dart';
export 'src/widgets/sarthi_phone_field.dart';
export 'src/widgets/sarthi_form_scaffold.dart';
