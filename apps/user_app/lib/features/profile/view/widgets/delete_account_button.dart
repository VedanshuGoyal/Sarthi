import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../../l10n/l10n.dart';
import '../../profile_providers.dart';

/// What deleting an account removes, and what MOJUD has to keep — in the
/// app's language.
String get deleteAccountExplanation => L10n.current.accountDeleteExplanation;

/// Asks the customer to confirm deleting their account; true when they do.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final t = SkylineTokens.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = context.l10n;
      return AlertDialog(
        title: Text(l10n.accountDeleteConfirmTitle),
        content: Text(l10n.accountDeleteExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: t.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.accountDelete),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// "Delete account" under "Log out": confirms, then erases the account
/// through [accountDeletionViewModelProvider], which signs out on success.
/// A refusal (a ride under way or unpaid) is shown in a snack bar.
class DeleteAccountButton extends ConsumerWidget {
  const DeleteAccountButton({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await showDeleteAccountDialog(context) || !context.mounted) return;
    final vm = ref.read(accountDeletionViewModelProvider);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.accountDeleteFailed;
    if (await vm.deleteAccount()) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(vm.errorText ?? failed)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SkylineTokens.of(context);
    final deleting = ref.watch(
      accountDeletionViewModelProvider.select((vm) => vm.isDeleting),
    );
    return TextButton.icon(
      onPressed: deleting ? null : () => _delete(context, ref),
      icon: deleting
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_forever_rounded),
      label: Text(
        deleting ? context.l10n.accountDeleting : context.l10n.accountDelete,
      ),
      style: TextButton.styleFrom(foregroundColor: t.danger),
    );
  }
}
