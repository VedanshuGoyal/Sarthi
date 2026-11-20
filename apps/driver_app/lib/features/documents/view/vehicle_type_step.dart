import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sarthi_shared/sarthi_shared.dart';

import '../../../l10n/l10n.dart';
import '../document_providers.dart';
import '../domain/vehicle_type.dart';
import 'document_labels.dart';

/// Document step 1 — which gearbox(es) the driver can drive.
class VehicleTypeStep extends ConsumerStatefulWidget {
  const VehicleTypeStep({super.key});

  @override
  ConsumerState<VehicleTypeStep> createState() => _VehicleTypeStepState();
}

class _VehicleTypeStepState extends ConsumerState<VehicleTypeStep> {
  VehicleType? _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref
        .read(documentRegistrationViewModelProvider)
        .kyc
        .transmission;
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) return;

    final vm = ref.read(documentRegistrationViewModelProvider);
    await vm.setVehicleType(selected);
    if (!mounted) return;
    if (vm.error != null) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final vm = ref.watch(documentRegistrationViewModelProvider);
    final t = DeepSignalTokens.of(context);
    final l10n = context.l10n;

    return SarthiFormScaffold(
      leading: const BackButton(),
      title: l10n.vehicleStepTitle,
      subtitle: l10n.vehicleStepSubtitle,
      fields: [
        for (final type in VehicleType.values) ...[
          _OptionCard(
            label: type.labelIn(l10n),
            selected: _selected == type,
            onTap: () => setState(() => _selected = type),
            t: t,
          ),
          if (type != VehicleType.values.last)
            const SizedBox(height: DeepSignalTokens.s8),
        ],
        if (vm.error != null) ...[
          const SizedBox(height: DeepSignalTokens.s8),
          Text(vm.error!, style: t.body(size: 13, color: Colors.red)),
        ],
      ],
      footer: SarthiPrimaryButton(
        label: vm.isSaving ? l10n.vehicleStepSaving : l10n.commonContinue,
        onPressed: _selected == null || vm.isSaving ? null : _submit,
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.t,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final DeepSignalTokens t;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
        child: Container(
          padding: const EdgeInsets.all(DeepSignalTokens.s14),
          decoration: BoxDecoration(
            color: selected ? t.raised : t.surface,
            border: Border.all(color: selected ? t.accentBorder : t.hairline),
            borderRadius: BorderRadius.circular(DeepSignalTokens.radius),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: t.title(15, weight: FontWeight.w600)),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? t.accent : t.edge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
