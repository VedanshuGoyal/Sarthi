import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../profile_providers.dart';

/// What deleting an account removes, and what MOJUD has to keep.
const String deleteAccountExplanation =
    "We'll remove your name, email, phone number, saved cars and recent "
    'pickups, and sign you out on every device. Records of past rides and '
    'payments are kept, without your details, because the law requires us '
    "to keep them. This can't be undone.";

/// Asks the customer to confirm deleting their account; true when they do.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final t = SkylineTokens.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(deleteAccountExplanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete account'),
        ),
      ],
    ),
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
    if (await vm.deleteAccount()) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            vm.errorText ?? "Couldn't delete your account. Please try again.",
          ),
        ),
      );
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
      label: Text(deleting ? 'Deleting your account…' : 'Delete account'),
      style: TextButton.styleFrom(foregroundColor: t.danger),
    );
  }
}
