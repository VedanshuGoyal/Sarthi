import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../account_providers.dart';

/// "Delete account" under Log out: asks first, then has the server erase
/// the account and signs out. A refusal (a ride underway, an unpaid ride)
/// is shown as the server explains it.
class DeleteAccountButton extends ConsumerWidget {
  const DeleteAccountButton({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;

    final vm = ref.read(accountDeletionViewModelProvider);
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await vm.deleteAccount();
    if (!deleted && vm.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(vm.error!)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SkylineTokens.of(context);
    final deleting = ref.watch(
      accountDeletionViewModelProvider.select((vm) => vm.isDeleting),
    );
    return TextButton.icon(
      onPressed: deleting ? null : () => _delete(context, ref),
      style: TextButton.styleFrom(foregroundColor: t.danger),
      icon: deleting
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.danger),
            )
          : const Icon(Icons.delete_forever_rounded),
      label: Text(context.l10n.accountDelete),
    );
  }
}

/// The confirmation: pops true to delete, false (or null) to keep.
class DeleteAccountDialog extends StatelessWidget {
  const DeleteAccountDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final l10n = context.l10n;
    // What deleting the account removes and what MOJUD has to keep.
    return AlertDialog(
      title: Text(l10n.accountDeleteConfirmTitle),
      content: SingleChildScrollView(
        child: Text(l10n.accountDeleteExplanation, style: t.body(size: 14.5)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: t.danger),
          child: Text(l10n.accountDelete),
        ),
      ],
    );
  }
}
