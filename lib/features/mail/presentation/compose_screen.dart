import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart' show EpPressable;
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../data/branding.dart';
import '../data/contacts.dart';
import '../data/mail_client.dart' show MailException;
import '../data/mail_live.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';
import '../data/message_size.dart';
import '../data/recent_from.dart';
import '../data/recipient_suggestions.dart';
import '../data/reply_builder.dart';
import '../data/signature.dart';
import '../mail_routes.dart' show mailDomainPath;
import 'from_picker.dart';
import 'mail_widgets.dart';
import 'recipient_field.dart';

/// What the compose sheet opens with.
class ComposeArgs {
  const ComposeArgs({required this.accountId, this.mode = ComposeMode.compose, this.parent, this.domain});

  /// The account whose mail service sends it.
  final String accountId;
  final ComposeMode mode;
  final MessageSummary? parent;

  /// Preferred sending domain for a new message (e.g. opened from a domain).
  final String? domain;
}

/// Everything the form needs before it can build the draft: services,
/// saved identities (names, signatures), known mailboxes and the parent.
final _composeContextProvider = FutureProvider.autoDispose.family<MessageDetail?, ComposeArgs>((ref, args) async {
  await ref.watch(mailServicesProvider.future);
  await ref.watch(identitySettingsProvider(args.accountId).future);
  try {
    await ref.watch(mailboxesProvider(args.accountId).future);
  } on MailException {
    // Mailboxes only refine the From list; compose works without them.
  }
  final p = args.parent;
  return p == null ? null : ref.watch(messageDetailProvider((p.accountId, p.id)).future);
});

/// Opens the system picker (photo library or documents). A provider so tests
/// can hand in files.
final attachmentPickerProvider = Provider<Future<List<PlatformFile>> Function(FileType type)>(
  (ref) =>
      (type) => FilePicker.pickFiles(type: type),
);

class ComposeScreen extends ConsumerWidget {
  const ComposeScreen({super.key, required this.args});
  final ComposeArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    // Loading or failing to load the message being answered must never trap
    // the user: the page's navigation bar carries the modal's Close.
    Widget waiting(Widget body) => EpPage(
      title: l.mailCompose,
      largeTitle: false,
      slivers: [EpFill(child: body)],
    );
    return ref
        .watch(_composeContextProvider(args))
        .when(
          loading: () => waiting(const EpLoading()),
          error: (e, _) => waiting(EpMessage(icon: EpIcon.warning, title: describeMailError(context, e))),
          data: (d) => _ComposeForm(args: args, parentDetail: d),
        );
  }
}

class _ComposeForm extends ConsumerStatefulWidget {
  const _ComposeForm({required this.args, required this.parentDetail});
  final ComposeArgs args;
  final MessageDetail? parentDetail;

  @override
  ConsumerState<_ComposeForm> createState() => _ComposeFormState();
}

class _ComposeFormState extends ConsumerState<_ComposeForm> {
  late ComposeDraft _draft;
  late MailAddress _from;
  List<MailAddress> _to = [];
  List<MailAddress> _cc = [];
  List<MailAddress> _bcc = [];
  bool _showCcBcc = false;
  final _subject = TextEditingController();
  final _body = TextEditingController();

  /// This message's signature: the From domain's, until the user edits it
  /// here (then it's theirs, and changing From keeps it).
  final _signature = TextEditingController();
  bool _signatureEdited = false;
  bool _settingSignature = false;

  /// What the domain's default (or a restored draft) put in [_signature]:
  /// the signature is edited once its text differs.
  String _appliedSignature = '';
  bool _includeLogo = true;
  final _toKey = GlobalKey<RecipientFieldState>();
  final _ccKey = GlobalKey<RecipientFieldState>();
  final _bccKey = GlobalKey<RecipientFieldState>();
  bool _includeQuote = true;
  bool _includeOriginals = true;
  bool _showQuote = false;
  final List<OutgoingAttachment> _attachments = [];
  bool _sending = false;
  bool _dirty = false;
  Timer? _autosave;

  /// One idempotency key per message: retries after a timeout never send twice.
  final String _clientMessageId = _randomId();

  static String _randomId() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  String get _draftKey {
    final p = widget.args.parent;
    return 'mail:draft:${widget.args.mode.name}:${p?.id ?? 'new'}';
  }

  @override
  void initState() {
    super.initState();
    final account = widget.args.accountId;
    final service = ref.read(mailServiceProvider(account));
    final identities = ref.read(identitiesProvider(account));
    final own = {
      for (final i in identities) i.address.toLowerCase(),
      for (final b in ref.read(mailboxesProvider(account)).value ?? const <Mailbox>[]) b.address.toLowerCase(),
    };
    final parent = widget.parentDetail;
    if (parent != null) {
      _draft = buildDraft(
        parent,
        mode: widget.args.mode,
        ownAddresses: own,
        identities: identities.map((i) => i.mail).toList(),
        locale: null,
      );
    } else {
      _draft = ComposeDraft(mode: ComposeMode.compose, accountId: account, from: _defaultIdentity(identities, service));
    }
    _from = _draft.from;
    _to = [..._draft.to];
    _cc = [..._draft.cc];
    _showCcBcc = _cc.isNotEmpty;
    _subject.text = _draft.subject;
    _includeOriginals = _draft.includeOriginalAttachments;
    _subject.addListener(_markDirty);
    _body.addListener(_markDirty);
    _signature.addListener(() {
      // Selection and caret moves notify too: only a text change edits.
      if (_settingSignature || _signature.text == _appliedSignature && !_signatureEdited) return;
      final edited = _signature.text != _appliedSignature;
      if (edited != _signatureEdited) setState(() => _signatureEdited = edited);
      _markDirty();
    });
    // The domain's signature, once the brands load (cached: usually at once).
    ref.listenManual(brandsProvider(account), (_, _) => _applyDomainSignature(), fireImmediately: true);
    _restoreDraft();
  }

  String get _domain => _from.address.split('@').last.toLowerCase();

  DomainBrand get _brand => brandOf(ref.read(brandsProvider(widget.args.accountId)).value?.data ?? const [], _domain);

  /// The From domain's default signature, unless the user wrote their own.
  void _applyDomainSignature() {
    if (_signatureEdited || !mounted) return;
    _settingSignature = true;
    _appliedSignature = _brand.signature;
    _signature.text = _appliedSignature;
    _settingSignature = false;
    setState(() {});
  }

  /// Back to the domain's default.
  void _resetSignature() {
    setState(() => _signatureEdited = false);
    _applyDomainSignature();
    _markDirty();
  }

  SignatureBlock get _signatureBlock {
    final logo = _brand.logo;
    return SignatureBlock(text: _signature.text, logo: _includeLogo ? logo : null);
  }

  /// New messages start from contact@ on the preferred domain (or the first
  /// one), unless a saved identity on that domain exists.
  MailAddress _defaultIdentity(List<Identity> identities, MailService? service) {
    final domain = (widget.args.domain ?? service?.domains.firstOrNull ?? 'example.com').toLowerCase();
    final onDomain = identities.where((i) => i.address.toLowerCase().endsWith('@$domain')).toList();
    final contact = onDomain.where((i) => i.address.toLowerCase().startsWith('contact@')).firstOrNull;
    if (contact != null) return contact.mail;
    return MailAddress('contact@$domain');
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _subject.dispose();
    _body.dispose();
    _signature.dispose();
    super.dispose();
  }

  void _markDirty() {
    _dirty = true;
    _autosave?.cancel();
    _autosave = Timer(const Duration(seconds: 1), _saveDraft);
  }

  Future<void> _saveDraft() => ref.read(cacheStoreProvider).write(widget.args.accountId, _draftKey, {
    'from': _from.toJson(),
    'to': _to.map((a) => a.toJson()).toList(),
    'cc': _cc.map((a) => a.toJson()).toList(),
    'bcc': _bcc.map((a) => a.toJson()).toList(),
    'subject': _subject.text,
    'body': _body.text,
    'includeQuote': _includeQuote,
    'signature': _signature.text,
    'signatureEdited': _signatureEdited,
    'includeLogo': _includeLogo,
  });

  Future<void> _restoreDraft() async {
    final hit = await ref.read(cacheStoreProvider).read(widget.args.accountId, _draftKey);
    if (hit == null || !mounted) return;
    final j = hit.value as Map<String, dynamic>;
    List<MailAddress> list(Object? v) => (v as List? ?? const []).map(MailAddress.fromJson).toList();
    setState(() {
      _from = MailAddress.fromJson(j['from']);
      _to = list(j['to']);
      _cc = list(j['cc']);
      _bcc = list(j['bcc']);
      _showCcBcc = _cc.isNotEmpty || _bcc.isNotEmpty;
      _subject.text = j['subject'] as String;
      _body.text = j['body'] as String;
      _includeQuote = j['includeQuote'] as bool;
      _settingSignature = true;
      _signature.text = j['signature'] as String;
      _settingSignature = false;
      _signatureEdited = j['signatureEdited'] as bool;
      if (!_signatureEdited) _appliedSignature = _signature.text;
      _includeLogo = j['includeLogo'] as bool;
      _dirty = false;
    });
    showEpToast(context, context.l10n.mailDraftRestored);
  }

  SendRequest _request() => _draft.toRequest(
    from: _from,
    to: _to,
    cc: _cc,
    bcc: _bcc,
    subject: _subject.text.trim(),
    body: _body.text,
    signature: _signatureBlock,
    includeQuote: _includeQuote,
    attachments: _attachments,
    includeOriginalAttachments: _includeOriginals,
  );

  /// Size of the message as Cloudflare will see it (attachments base64-encoded,
  /// the logo included).
  int get _estimate {
    final r = _request();
    return estimateMessageBytes(
      text: r.text,
      html: r.html,
      attachmentRawSizes: [
        for (final a in _attachments) a.bytes.length,
        if (_includeOriginals && _draft.originalAttachmentBytes > 0) _draft.originalAttachmentBytes,
        if (r.brandLogo) _brand.logo!.size,
      ],
    );
  }

  /// Reassurance before the limit bites: from 80% of the account's sending
  /// limit, say how many sends are left.
  Widget? _sendsLeft(BuildContext context) {
    final account = widget.args.accountId;
    final (used, limit) = ref.watch(
      mailLiveProvider.select((s) {
        final u = s.usageByAccount[account];
        return (u?.used ?? 0, u?.limit ?? 0);
      }),
    );
    if (limit <= 0 || used / limit < 0.8) return null;
    final left = (limit - used).clamp(0, limit);
    final c = EpColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, 0, EpSpace.lg, EpSpace.sm),
      child: Text(
        context.l10n.mailSendsLeft(left),
        style: TextStyle(color: left == 0 ? c.attention : c.caution, fontSize: 13),
      ),
    );
  }

  Future<void> _pickFrom() async {
    final chosen = await showFromPicker(context, accountId: widget.args.accountId, current: _from);
    if (chosen == null || !mounted) return;
    final sameDomain = chosen.address.split('@').last.toLowerCase() == _domain;
    setState(() {
      _from = chosen;
      if (!sameDomain) _includeLogo = true;
    });
    if (!sameDomain) _applyDomainSignature();
    _markDirty();
  }

  /// Photo library or document picker. Each file is checked against what's
  /// left of Cloudflare's 5 MB (as sent) before it's read into memory.
  Future<void> _attach() async {
    final l = context.l10n;
    final type = await showEpActionSheet<FileType>(
      context,
      actions: [
        EpSheetAction(label: l.mailAttachPhoto, value: FileType.media, icon: EpIcon.image),
        EpSheetAction(label: l.mailAttachFile, value: FileType.any, icon: EpIcon.attach),
      ],
    );
    if (type == null || !mounted) return;
    try {
      final files = await ref.read(attachmentPickerProvider)(type);
      for (final f in files) {
        final size = await f.length() ?? 0;
        final room = remainingRawBytes(_estimate);
        if (size > room) {
          if (mounted) showEpToast(context, l.mailAttachTooBig(f.name, formatBytes(size), formatBytes(room)));
          continue;
        }
        final bytes = await f.readAsBytes();
        _attachments.add(OutgoingAttachment(filename: f.name, mimeType: _mimeFor(f.name), bytes: bytes));
      }
      if (mounted) setState(_markDirty);
    } on Object catch (e) {
      if (mounted) showEpToast(context, l.mailAttachFailed('$e'));
    }
  }

  Future<void> _send() async {
    final l = context.l10n;
    final okTo = _toKey.currentState?.commitPending() ?? true;
    final okCc = _ccKey.currentState?.commitPending() ?? true;
    final okBcc = _bccKey.currentState?.commitPending() ?? true;
    if (!okTo || !okCc || !okBcc) return;
    if (_to.isEmpty && _cc.isEmpty && _bcc.isEmpty) {
      showEpToast(context, l.mailRecipientsRequired);
      return;
    }
    if (_estimate > kMaxOutboundBytes) {
      showEpToast(context, l.mailSizeOver);
      return;
    }
    final accountId = widget.args.accountId;
    final req = _request().withClientMessageId(_clientMessageId);
    setState(() => _sending = true);
    try {
      await ref.read(mailClientProvider(accountId)).send(req);
      unawaited(ref.read(recentFromProvider(accountId).notifier).remember(_from));
      ref.read(contactsProvider(accountId).notifier).noteSent([...req.to, ...req.cc]);
      _autosave?.cancel();
      await ref.read(cacheStoreProvider).remove(widget.args.accountId, _draftKey);
      final p = widget.args.parent;
      if (p != null) ref.invalidate(threadProvider((p.accountId, p.threadId)));
      ref.invalidate(mailListProvider);
      if (!mounted) return;
      showEpToast(context, l.mailSent);
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final details = mailErrorDetails(e);
      final retry = await showEpConfirm(
        context,
        title: l.mailSendFailedTitle,
        message: [
          describeMailError(context, e, fromDomain: _from.domain),
          if (details != null) l.mailErrorDetails(details),
        ].join('\n\n'),
        confirmLabel: l.actionRetry,
      );
      if (retry && mounted) await _send();
    }
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final hasContent = _dirty && (_body.text.trim().isNotEmpty || _to.isNotEmpty || _attachments.isNotEmpty);
    if (!hasContent) {
      await ref.read(cacheStoreProvider).remove(widget.args.accountId, _draftKey);
      if (mounted) context.pop();
      return;
    }
    final choice = await showEpActionSheet<String>(
      context,
      title: l.mailDiscardTitle,
      actions: [
        EpSheetAction(label: l.mailSaveDraft, value: 'save'),
        EpSheetAction(label: l.mailDiscard, value: 'discard', destructive: true),
      ],
    );
    if (choice == null || !mounted) return;
    _autosave?.cancel();
    if (choice == 'save') {
      await _saveDraft();
    } else {
      await ref.read(cacheStoreProvider).remove(widget.args.accountId, _draftKey);
    }
    if (mounted) context.pop();
  }

  String _title(BuildContext context) {
    final l = context.l10n;
    return switch (widget.args.mode) {
      ComposeMode.compose => l.mailCompose,
      ComposeMode.reply => l.mailReply,
      ComposeMode.replyAll => l.mailReplyAll,
      ComposeMode.forward => l.mailForward,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final cupertino = isCupertino(context);
    final sendLabel = _sending ? l.mailSending : l.actionSend;
    final estimate = _estimate;
    final ratio = (estimate / kMaxOutboundBytes).clamp(0.0, 1.0);
    final over = estimate > kMaxOutboundBytes;
    // Everyone on the message (and From) is left out of the suggestions.
    final suggestions = RecipientSuggestions(
      contacts: ref.watch(contactsProvider(widget.args.accountId)).value?.data ?? const [],
      locales: View.of(context).platformDispatcher.locales,
      exclude: {
        _from.address,
        for (final a in [..._to, ..._cc, ..._bcc]) a.address,
      },
    );

    final PreferredSizeWidget bar = cupertino
        ? CupertinoNavigationBar(
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _sending ? null : _cancel,
              child: Text(l.actionCancel),
            ),
            middle: Text(_title(context)),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _sending || over ? null : _send,
              child: _sending
                  ? const CupertinoActivityIndicator()
                  : Text(sendLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            backgroundColor: c.canvas.withValues(alpha: 0.95),
          )
        : AppBar(
            leading: IconButton(
              tooltip: l.actionCancel,
              icon: const Icon(Icons.close),
              onPressed: _sending ? null : _cancel,
            ),
            title: Text(_title(context)),
            actions: [
              IconButton(
                tooltip: l.mailAddAttachment,
                icon: const Icon(Icons.attach_file),
                onPressed: _sending ? null : _attach,
              ),
              Padding(
                padding: const EdgeInsets.only(right: EpSpace.sm),
                child: FilledButton.icon(
                  onPressed: _sending || over ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, size: 18),
                  label: Text(sendLabel),
                ),
              ),
            ],
          );

    final divider = Divider(height: 1, color: c.hairline);
    final quoted = _draft.quotedText;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_sending) _cancel();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: bar,
        body: SafeArea(
          child: EpReadableWidth(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _FromRow(address: _from, onTap: _sending ? null : _pickFrom),
                ?_sendsLeft(context),
                divider,
                RecipientField(
                  key: _toKey,
                  suggestions: suggestions,
                  label: l.mailFieldTo,
                  value: _to,
                  autofocus: widget.args.mode == ComposeMode.compose || widget.args.mode == ComposeMode.forward,
                  onChanged: (v) => setState(() {
                    _to = v;
                    _markDirty();
                  }),
                ),
                divider,
                if (_showCcBcc) ...[
                  RecipientField(
                    key: _ccKey,
                    suggestions: suggestions,
                    label: l.mailFieldCc,
                    value: _cc,
                    onChanged: (v) => setState(() => _cc = v),
                  ),
                  divider,
                  RecipientField(
                    key: _bccKey,
                    suggestions: suggestions,
                    label: l.mailFieldBcc,
                    value: _bcc,
                    onChanged: (v) => setState(() => _bcc = v),
                  ),
                  divider,
                ] else ...[
                  _FieldRow(
                    label: '${l.mailFieldCc}/${l.mailFieldBcc}',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EpTextButton(label: l.mailAddCcBcc, onPressed: () => setState(() => _showCcBcc = true)),
                    ),
                  ),
                  divider,
                ],
                _FieldRow(
                  label: l.mailFieldSubject,
                  child: cupertino
                      ? CupertinoTextField.borderless(
                          controller: _subject,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          style: TextStyle(color: c.ink, fontSize: 16),
                        )
                      : TextField(
                          controller: _subject,
                          style: TextStyle(color: c.ink, fontSize: 16),
                          // 48 dp row, as tall as the others.
                          decoration: bareInputDecoration(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                ),
                divider,
                Padding(
                  padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.md),
                  child: cupertino
                      ? CupertinoTextField.borderless(
                          controller: _body,
                          autofocus: widget.args.mode == ComposeMode.reply || widget.args.mode == ComposeMode.replyAll,
                          placeholder: l.mailBodyPlaceholder,
                          maxLines: null,
                          minLines: 8,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(color: c.ink, fontSize: 17, height: 1.4),
                        )
                      : TextField(
                          controller: _body,
                          autofocus: widget.args.mode == ComposeMode.reply || widget.args.mode == ComposeMode.replyAll,
                          maxLines: null,
                          minLines: 8,
                          keyboardType: TextInputType.multiline,
                          decoration: bareInputDecoration(hintText: l.mailBodyPlaceholder),
                        ),
                ),
                divider,
                _SignatureSection(
                  accountId: widget.args.accountId,
                  domain: _domain,
                  controller: _signature,
                  edited: _signatureEdited,
                  onReset: _resetSignature,
                  logo: _brand.logo,
                  includeLogo: _includeLogo,
                  onIncludeLogo: (v) => setState(() {
                    _includeLogo = v;
                    _markDirty();
                  }),
                ),
                if (quoted.isNotEmpty) ...[
                  divider,
                  EpSwitchTile(
                    title: l.mailIncludeQuote,
                    value: _includeQuote,
                    onChanged: (v) => setState(() => _includeQuote = v),
                  ),
                  if (_includeQuote)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
                      child: _showQuote
                          ? Text(quoted, style: TextStyle(color: c.inkMuted, fontSize: 14, height: 1.4))
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: EpTextButton(
                                label: l.mailShowQuoted,
                                onPressed: () => setState(() => _showQuote = true),
                              ),
                            ),
                    ),
                ],
                if (_draft.mode == ComposeMode.forward && _draft.originalAttachmentBytes > 0)
                  EpSwitchTile(
                    title: l.mailIncludeAttachments,
                    value: _includeOriginals,
                    onChanged: (v) => setState(() => _includeOriginals = v),
                  ),
                divider,
                _AttachmentsBar(
                  attachments: _attachments,
                  onAdd: _sending ? null : _attach,
                  onRemove: (a) => setState(() {
                    _attachments.remove(a);
                    _markDirty();
                  }),
                ),
                // Noise on a plain message; it matters once files are involved.
                if (_attachments.isNotEmpty || _includeOriginals || estimate > 1024 * 1024)
                  _SizeMeter(
                    ratio: ratio,
                    over: over,
                    label: over ? l.mailSizeOver : l.mailSizeAsSent(formatBytes(estimate)),
                  ),
                const SizedBox(height: EpSpace.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "From" shown as name over address; the whole row opens the From sheet.
class _FromRow extends StatelessWidget {
  const _FromRow({required this.address, required this.onTap});
  final MailAddress address;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final at = address.address.indexOf('@');
    return Semantics(
      button: true,
      label: '${l.mailFieldFrom} ${address.formatted}',
      excludeSemantics: true,
      child: EpPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: 10),
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Text(l.mailFieldFrom, softWrap: false, style: TextStyle(color: c.inkMuted, fontSize: 15)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (address.name != null)
                        Text(
                          address.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      // Wraps at "@" (zero-width space) rather than cutting the
                      // domain: it's what tells contact@ addresses apart.
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: address.address.substring(0, at),
                              style: TextStyle(
                                color: c.ink,
                                fontWeight: address.name == null ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            TextSpan(
                              text: '\u200B${address.address.substring(at)}',
                              style: TextStyle(color: c.inkMuted),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c.ink),
                      ),
                    ],
                  ),
                ),
                EpIconView(EpIcon.chevron, size: 18, color: c.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Attachment chips with size and remove, plus an "Attach" chip.
class _AttachmentsBar extends StatelessWidget {
  const _AttachmentsBar({required this.attachments, required this.onAdd, required this.onRemove});
  final List<OutgoingAttachment> attachments;
  final VoidCallback? onAdd;
  final ValueChanged<OutgoingAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    Widget chip({required Widget icon, required Widget label, VoidCallback? onTap, Widget? trailing, Color? bg}) =>
        Material(
          color: bg ?? c.canvas,
          shape: StadiumBorder(side: BorderSide(color: c.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: EdgeInsets.only(left: 12, right: trailing == null ? 14 : 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 6),
                    Flexible(child: label),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.sm),
      child: Wrap(
        spacing: EpSpace.sm,
        runSpacing: EpSpace.sm,
        children: [
          for (final a in attachments)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: chip(
                icon: EpIconView(
                  a.mimeType.startsWith('image/') ? EpIcon.image : EpIcon.attach,
                  size: 18,
                  color: c.inkMuted,
                ),
                label: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.filename,
                        style: TextStyle(color: c.ink),
                      ),
                      TextSpan(
                        text: '  ${formatBytes(a.bytes.length)}',
                        style: EpType.numbers(TextStyle(color: c.inkMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: l.actionRemove,
                  visualDensity: VisualDensity.compact,
                  icon: EpIconView(EpIcon.close, size: 16, color: c.inkMuted),
                  onPressed: () => onRemove(a),
                ),
              ),
            ),
          chip(
            icon: EpIconView(EpIcon.attach, size: 18, color: c.tint),
            label: Text(
              l.mailAddAttachment,
              style: TextStyle(color: c.tint, fontWeight: FontWeight.w600),
            ),
            onTap: onAdd,
            bg: c.surface,
          ),
        ],
      ),
    );
  }
}

/// Thin meter of the message size as sent against Cloudflare's 5 MB.
class _SizeMeter extends StatelessWidget {
  const _SizeMeter({required this.ratio, required this.over, required this.label});
  final double ratio;
  final bool over;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final color = over ? c.attention : (ratio > 0.8 ? c.caution : c.ok);
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(EpRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: ratio),
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) =>
                    LinearProgressIndicator(value: v, minHeight: 4, color: color, backgroundColor: c.hairline),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                label,
                style: EpType.numbers(TextStyle(fontSize: 13, color: over ? c.attention : c.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    // Merged so the field is announced with its label ("Subject, text field").
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Padding(
                padding: const EdgeInsets.only(right: EpSpace.sm),
                child: Text(label, softWrap: false, style: TextStyle(color: c.inkMuted, fontSize: 15)),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

String _mimeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
        'pdf': 'application/pdf',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'heic': 'image/heic',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'zip': 'application/zip',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'ics': 'text/calendar',
        'json': 'application/json',
        'mp4': 'video/mp4',
        'mov': 'video/quicktime',
        'mp3': 'audio/mpeg',
      }[ext] ??
      'application/octet-stream';
}

/// The message's signature: the domain's logo (with a switch to leave it
/// out of this message) and the text in a field, plainly editable here for
/// this message only (Reset goes back to the domain's), with a way to the
/// domain's default.
class _SignatureSection extends ConsumerWidget {
  const _SignatureSection({
    required this.accountId,
    required this.domain,
    required this.controller,
    required this.edited,
    required this.onReset,
    required this.logo,
    required this.includeLogo,
    required this.onIncludeLogo,
  });

  final String accountId;
  final String domain;
  final TextEditingController controller;
  final bool edited;
  final VoidCallback onReset;
  final BrandLogo? logo;
  final bool includeLogo;
  final ValueChanged<bool> onIncludeLogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final image = logo == null ? null : ref.watch(brandLogoProvider((accountId, domain))).value;
    final style = TextStyle(color: c.ink, fontSize: 15, height: 1.4);
    final field = isCupertino(context)
        ? CupertinoTextField.borderless(
            controller: controller,
            placeholder: l.mailSignaturePlaceholder,
            padding: const EdgeInsets.all(EpSpace.md),
            minLines: 2,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: style,
          )
        : Padding(
            padding: const EdgeInsets.all(EpSpace.md),
            child: TextField(
              controller: controller,
              minLines: 2,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: style,
              decoration: bareInputDecoration(hintText: l.mailSignaturePlaceholder),
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(child: Text(l.mailSignature.toUpperCase(), style: EpType.groupLabel(context))),
                if (edited) EpTextButton(label: l.mailSignatureReset, onPressed: onReset),
              ],
            ),
          ),
          if (logo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: EpSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedOpacity(
                        opacity: includeLogo ? 1 : 0.35,
                        duration: const Duration(milliseconds: 160),
                        child: image == null
                            ? SizedBox(width: logo!.shown.$1, height: logo!.shown.$2)
                            : Image.memory(
                                image,
                                width: logo!.shown.$1,
                                height: logo!.shown.$2,
                                semanticLabel: l.mailSignatureLogoLabel(domain),
                                errorBuilder: (_, _, _) => SizedBox(width: logo!.shown.$1, height: logo!.shown.$2),
                              ),
                      ),
                    ),
                  ),
                  Text(l.mailSignatureLogo, style: TextStyle(color: c.ink, fontSize: 15)),
                  const SizedBox(width: EpSpace.sm),
                  Switch.adaptive(value: includeLogo, onChanged: onIncludeLogo),
                ],
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.hairline),
              borderRadius: BorderRadius.circular(EpRadius.md),
            ),
            child: field,
          ),
          Padding(
            padding: const EdgeInsets.only(top: EpSpace.xs),
            child: Text(
              edited ? l.mailSignatureEditedHere : l.mailSignatureThisMessage,
              style: TextStyle(color: c.inkMuted, fontSize: 13),
            ),
          ),
          Transform.translate(
            // The button's own padding: its text lines up with the caption.
            offset: Offset(isCupertino(context) ? -EpSpace.md : -EpSpace.sm, 0),
            child: EpTextButton(
              label: l.mailSignatureEditDefault(domain),
              onPressed: () => context.push(mailDomainPath(domain)),
            ),
          ),
        ],
      ),
    );
  }
}
