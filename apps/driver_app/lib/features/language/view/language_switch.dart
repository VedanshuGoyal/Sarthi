import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../domain/app_language.dart';
import '../language_providers.dart';

/// English / हिंदी, each named in its own script so a driver can find their
/// language whichever one the app is in. Renders [selected] and reports a
/// tap through [onSelected].
class LanguageSegments extends StatelessWidget {
  const LanguageSegments({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// [AppLanguage.english] or [AppLanguage.hindi] — the language on screen.
  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<AppLanguage>(
      segments: [
        ButtonSegment(
          value: AppLanguage.english,
          label: Text(l10n.languageEnglish),
        ),
        ButtonSegment(
          value: AppLanguage.hindi,
          label: Text(l10n.languageHindi),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (choice) => onSelected(choice.single),
    );
  }
}

/// The Account screen's language setting: a card titled "Language · भाषा"
/// with [LanguageSegments]. Until the driver picks, the app follows the
/// phone and the card says so.
class LanguageSwitch extends ConsumerWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(languageViewModelProvider);
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    final shown = AppLanguage.forLocale(Localizations.localeOf(context));
    return SkylineCard(
      padding: const EdgeInsets.all(Skyline.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate_rounded, color: t.primaryText),
              const SizedBox(width: Skyline.s12),
              Expanded(child: Text(l10n.languageTitle, style: t.title(15))),
            ],
          ),
          const SizedBox(height: Skyline.s12),
          SizedBox(
            width: double.infinity,
            child: LanguageSegments(
              selected: shown,
              onSelected: ref.read(languageViewModelProvider).select,
            ),
          ),
          if (vm.language == AppLanguage.system) ...[
            const SizedBox(height: Skyline.s8),
            Text(l10n.languageFollowsPhone, style: t.body(size: 12.5)),
          ],
        ],
      ),
    );
  }
}

/// A compact language picker for app bars on screens before the Account
/// tab exists — the start screen and the Document View — so a driver whose
/// phone is in English can switch to Hindi before onboarding.
class LanguageMenuButton extends ConsumerWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final shown = AppLanguage.forLocale(Localizations.localeOf(context));
    return PopupMenuButton<AppLanguage>(
      icon: const Icon(Icons.translate_rounded),
      tooltip: l10n.languageTitle,
      initialValue: shown,
      onSelected: ref.read(languageViewModelProvider).select,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: AppLanguage.english,
          checked: shown == AppLanguage.english,
          child: Text(l10n.languageEnglish),
        ),
        CheckedPopupMenuItem(
          value: AppLanguage.hindi,
          checked: shown == AppLanguage.hindi,
          child: Text(l10n.languageHindi),
        ),
      ],
    );
  }
}
