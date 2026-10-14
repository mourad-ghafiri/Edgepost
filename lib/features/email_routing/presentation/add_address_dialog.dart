import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../data/email_routing_models.dart';
import '../data/email_routing_providers.dart';

/// Asks for a destination address, adds it to the account and confirms that
/// Cloudflare emailed the verification link. Returns the new address.
Future<DestinationAddress?> showAddDestinationDialog(BuildContext context, String accountId) async {
  final created = await showAdaptiveDialog<DestinationAddress>(
    context: context,
    builder: (_) => _AddAddressDialog(accountId: accountId),
  );
  if (created != null && context.mounted) {
    showEpToast(context, context.l10n.routingAddressAddedToast(created.email));
  }
  return created;
}

class _AddAddressDialog extends ConsumerStatefulWidget {
  const _AddAddressDialog({required this.accountId});
  final String accountId;

  @override
  ConsumerState<_AddAddressDialog> createState() => _AddAddressDialogState();
}

class _AddAddressDialogState extends ConsumerState<_AddAddressDialog> {
  final _ctl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final email = _ctl.text.trim();
    if (!isValidEmail(email)) {
      setState(() => _error = l.routingAddressInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref.read(destinationAddressesProvider(widget.accountId).notifier).add(email);
      if (mounted) Navigator.pop(context, created);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(context, e, permission: Capability.emailAddresses.permission);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final cupertino = isCupertino(context);
    final field = cupertino
        ? CupertinoTextField(
            controller: _ctl,
            autofocus: true,
            autocorrect: false,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            placeholder: l.routingAddressPlaceholder,
            style: EpType.data(context, size: 15),
            onSubmitted: (_) => _submit(),
          )
        : TextField(
            controller: _ctl,
            autofocus: true,
            autocorrect: false,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            style: EpType.data(context, size: 15),
            decoration: InputDecoration(hintText: l.routingAddressPlaceholder, errorText: _error, errorMaxLines: 4),
            onSubmitted: (_) => _submit(),
          );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cupertino ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(l.routingAddAddressMessage),
        const SizedBox(height: 12),
        field,
        if (cupertino && _error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: c.attention, fontSize: 13)),
        ],
      ],
    );
    final addLabel = _busy ? l.loading : l.actionAdd;
    return AlertDialog.adaptive(
      title: Text(l.routingAddAddressTitle),
      content: content,
      actions: cupertino
          ? [
              CupertinoDialogAction(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.actionCancel)),
              CupertinoDialogAction(isDefaultAction: true, onPressed: _busy ? null : _submit, child: Text(addLabel)),
            ]
          : [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.actionCancel)),
              TextButton(onPressed: _busy ? null : _submit, child: Text(addLabel)),
            ],
    );
  }
}
