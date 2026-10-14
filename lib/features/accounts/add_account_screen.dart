import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/account_switcher.dart';
import '../../core/accounts/vault.dart';
import '../../core/adaptive/ep_icons.dart';
import '../../core/adaptive/ep_page.dart';
import '../../core/adaptive/ep_widgets.dart';
import '../../core/l10n.dart';
import '../../core/theme/tokens.dart';
import '../onboarding/presentation/capability_list.dart';

/// Adds Cloudflare accounts: ones the stored tokens already reach (one tap),
/// or the accounts a new API token reaches (verified first, then the user
/// picks which to add). Done switches to the new account.
class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key, this.onboarding = false});

  /// First run: no other account exists, Done opens Today.
  final bool onboarding;

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _label = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  bool _reveal = false;
  String? _error;

  /// Verified, waiting for the user to pick accounts.
  TokenCandidate? _candidate;
  final Set<String> _picked = {};

  /// Permission checks running: (done, total).
  (int, int)? _progress;

  /// Accounts just added (shown with what the token can do in each).
  List<String> _added = const [];
  String? _tokenId;

  @override
  void dispose() {
    _label.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _token.text = text);
  }

  Future<void> _verify() async {
    final l = context.l10n;
    if (_token.text.trim().isEmpty) {
      setState(() => _error = l.addTokenEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final candidate = await ref.read(vaultProvider.notifier).inspect(_token.text);
      if (!mounted) return;
      final added = {for (final a in ref.read(accountsProvider)) a.id};
      setState(() {
        _candidate = candidate;
        _picked
          ..clear()
          ..addAll([for (final a in candidate.check.accounts) if (!added.contains(a.id)) a.id]);
      });
      // One account, nothing to choose: add it straight away.
      if (candidate.check.accounts.length == 1 && _picked.length == 1) await _addFromToken();
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromToken() async {
    final candidate = _candidate!;
    setState(() => _progress = (0, 1));
    try {
      final ids = await ref.read(vaultProvider.notifier).add(
            candidate,
            _picked,
            label: _label.text,
            onProbed: (done, total) {
              if (mounted) setState(() => _progress = (done, total));
            },
          );
      final token = ref.read(tokensProvider).firstWhere((t) => t.token == candidate.token);
      if (mounted) {
        setState(() {
          _added = ids;
          _tokenId = token.id;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeError(context, e));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _addAvailable(String accountId) async {
    setState(() => _progress = (0, 1));
    try {
      await ref.read(vaultProvider.notifier).addAvailable({accountId});
      await _finish(accountId);
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e));
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  /// Opens the new account (on first run the vault already made it active);
  /// a token kept for accounts already added just closes.
  Future<void> _finish(String? accountId) async {
    if (widget.onboarding) {
      if (mounted) context.go('/today');
      return;
    }
    if (accountId == null) {
      if (mounted) context.pop();
      return;
    }
    if (mounted) await switchAccount(context, accountId);
  }

  @override
  Widget build(BuildContext context) {
    if (_added.isNotEmpty || (_tokenId != null && _candidate != null)) return _done(context);
    if (_progress != null) return _checking(context);
    if (_candidate != null) return _choose(context);
    return _form(context);
  }

  Widget _checking(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final (done, total) = _progress!;
    return EpPage(
      title: l.accountAdd,
      largeTitle: false,
      slivers: [
        EpFill(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: EpSpace.lg),
              Text(l.addAccountChecking(done, total), style: TextStyle(color: c.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final available = widget.onboarding ? const [] : (ref.watch(vaultProvider).value?.available ?? const []);
    return EpPage(
      title: widget.onboarding ? l.addTokenTitle : l.accountAdd,
      largeTitle: false,
      slivers: [
        if (available.isNotEmpty)
          SliverToBoxAdapter(
            child: EpSection(
              header: l.addAccountAvailable,
              footer: l.addAccountAvailableHelp,
              children: [
                for (final a in available)
                  EpTile(
                    title: Text(a.name),
                    trailing: EpTextButton(label: l.actionAdd, emphasized: true, onPressed: () => _addAvailable(a.id)),
                    onTap: () => _addAvailable(a.id),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (available.isNotEmpty) ...[
                  Text(l.addAccountNewToken.toUpperCase(), style: EpType.groupLabel(context)),
                  const SizedBox(height: EpSpace.md),
                ],
                EpTextField(
                  label: l.addTokenLabel,
                  placeholder: l.addTokenLabelPlaceholder,
                  controller: _label,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: EpSpace.lg),
                EpTextField(
                  label: l.addTokenField,
                  controller: _token,
                  monospace: true,
                  obscure: !_reveal,
                  autocorrect: false,
                  errorText: _error,
                  helperText: l.addTokenFieldHelp,
                  onSubmitted: (_) => _verify(),
                  suffix: EpIconButton(
                    icon: _reveal ? EpIcon.eyeOff : EpIcon.eye,
                    size: 20,
                    color: c.inkMuted,
                    label: _reveal ? l.actionHide : l.actionShow,
                    onPressed: () => setState(() => _reveal = !_reveal),
                  ),
                ),
                const SizedBox(height: EpSpace.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: EpButton(label: l.addTokenPaste, secondary: true, onPressed: _busy ? null : _paste),
                ),
                const SizedBox(height: EpSpace.lg),
                EpButton(label: l.addTokenVerify, busy: _busy, onPressed: _verify),
                if (_busy) ...[
                  const SizedBox(height: EpSpace.md),
                  Text(l.addTokenVerifying, textAlign: TextAlign.center, style: TextStyle(color: c.inkMuted)),
                ],
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: RecommendedPermissions()),
      ],
    );
  }

  Widget _choose(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final candidate = _candidate!;
    final added = {for (final a in ref.watch(accountsProvider)) a.id};
    final fresh = [for (final a in candidate.check.accounts) if (!added.contains(a.id)) a];
    final allAdded = fresh.isEmpty;
    return EpPage(
      title: l.addAccountChoose,
      largeTitle: false,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: Text(
              allAdded ? l.addAccountAllAdded : l.addAccountChooseHelp(candidate.check.accounts.length),
              style: TextStyle(color: c.ink, fontSize: 16, height: 1.4),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            children: [
              for (final a in candidate.check.accounts)
                if (added.contains(a.id))
                  EpTile(title: Text(a.name, style: TextStyle(color: c.inkMuted)), additionalInfo: Text(l.addAccountAlready))
                else
                  EpTile(
                    title: Text(a.name),
                    trailing: Checkbox.adaptive(
                      activeColor: c.tint,
                      checkColor: c.onTint,
                      value: _picked.contains(a.id),
                      onChanged: (v) => setState(() => v == true ? _picked.add(a.id) : _picked.remove(a.id)),
                    ),
                    onTap: () => setState(() => _picked.contains(a.id) ? _picked.remove(a.id) : _picked.add(a.id)),
                  ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: EpButton(
              label: allAdded ? l.addAccountKeepToken : l.addAccountConfirm(_picked.length),
              onPressed: allAdded || _picked.isNotEmpty ? _addFromToken : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final l = context.l10n;
    final vault = ref.watch(vaultProvider).value;
    final token = vault?.tokens.where((t) => t.id == _tokenId).firstOrNull;
    final shown = _added.isNotEmpty ? _added : [for (final a in token?.accounts ?? const []) a.id];
    return EpPage(
      title: l.addTokenAddedTitle,
      largeTitle: false,
      slivers: [
        if (token != null)
          for (final id in shown)
            SliverToBoxAdapter(
              child: CapabilityList(
                header: vault?.accountById(id)?.name,
                credential: token,
                accountId: id,
                footer: id == shown.last ? l.addTokenWriteNote : null,
              ),
            ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: EpButton(label: l.actionDone, onPressed: () => _finish(_added.firstOrNull)),
          ),
        ),
      ],
    );
  }
}
