import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/layout.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';
import '../data/mail_settings.dart';
import '../data/reply_builder.dart';
import 'compose_screen.dart';
import 'mail_widgets.dart';
import 'thread_screen.dart';
import '../mail_routes.dart' show threadPath, threadSelectionProvider;

/// The Mail tab: one board of strips across every domain mailbox.
class MailHomeScreen extends ConsumerStatefulWidget {
  const MailHomeScreen({super.key, this.initialDomain});

  /// Opened from a domain's hub: scope to that domain.
  final String? initialDomain;

  @override
  ConsumerState<MailHomeScreen> createState() => _MailHomeScreenState();
}

class _MailHomeScreenState extends ConsumerState<MailHomeScreen> {
  MailFolder _folder = MailFolder.inbox;
  String? _mailbox;
  String? _domain;
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _domain = widget.initialDomain;
    _scroll.addListener(_onScroll);
    // A thread opened from Today, a banner or a notification, beside the
    // inbox (see openThread).
    _open = ref.read(threadSelectionProvider);
    if (_open != null) _clearSelection();
    ref.listenManual(threadSelectionProvider, (_, next) {
      if (next == null) return;
      setState(() => _open = next);
      _clearSelection();
    });
  }

  void _clearSelection() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) ref.read(threadSelectionProvider.notifier).clear();
  });

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _account => ref.read(activeAccountProvider)!.id;

  MailListKey get _q => (
    _account,
    MailQuery(folder: _folder, mailbox: _mailbox, domain: _domain, search: _query.isEmpty ? null : _query),
  );

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) ref.read(mailListProvider(_q).notifier).loadMore();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
  }

  String _folderLabel(MailFolder f) {
    final l = context.l10n;
    return switch (f) {
      MailFolder.inbox => l.mailFolderInbox,
      MailFolder.sent => l.mailFolderSent,
      MailFolder.archive => l.mailFolderArchive,
      MailFolder.trash => l.mailFolderTrash,
    };
  }

  Future<void> _pickScope() async {
    final l = context.l10n;
    final boxes = ref.read(mailboxesProvider(_account)).value ?? const <Mailbox>[];
    final domains = {for (final b in boxes) b.domain}.toList()..sort();
    final choice = await showEpActionSheet<String>(
      context,
      actions: [
        EpSheetAction(label: l.mailAllInboxes, value: '*'),
        for (final d in domains) ...[
          EpSheetAction(label: d, value: 'd:$d', icon: EpIcon.domains),
          for (final b in boxes.where((b) => b.domain == d))
            EpSheetAction(
              label: b.unread > 0 ? '${b.address}  ·  ${b.unread}' : b.address,
              value: 'm:${b.address}',
              icon: EpIcon.inbox,
            ),
        ],
      ],
    );
    if (choice == null) return;
    setState(() {
      _mailbox = choice.startsWith('m:') ? choice.substring(2) : null;
      _domain = choice.startsWith('d:') ? choice.substring(2) : null;
    });
  }

  void _openCompose([ComposeMode mode = ComposeMode.compose, MessageSummary? parent]) {
    context.push(
      '/mail/compose',
      extra: ComposeArgs(accountId: _account, mode: mode, parent: parent, domain: _domain),
    );
  }

  /// The thread open beside the inbox, in a split: its id and the message
  /// to scroll to.
  (String, String?)? _open;

  /// Whether the inbox sits in a split this frame (set as it lays out).
  bool _split = false;

  void _openThread(MessageSummary m) {
    if (_split) {
      setState(() => _open = (m.threadId, m.id));
    } else {
      context.push(threadPath(m.threadId, focus: m.id));
    }
  }

  /// A window narrowing past the split keeps the open thread, pushed over
  /// the inbox as on a phone.
  void _keepOpenThread() {
    final open = _open!;
    _open = null; // during layout: the next build has no detail
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(threadPath(open.$1, focus: open.$2));
    });
  }

  /// A message leaving the list takes its open thread with it.
  void _closeIfOpen(MessageSummary m) {
    if (_open?.$1 == m.threadId) setState(() => _open = null);
  }

  Future<void> _messageActions(MessageSummary m) async {
    final l = context.l10n;
    final actions = ref.read(mailActionsProvider);
    final choice = await showEpActionSheet<String>(
      context,
      title: m.subject.isEmpty ? l.mailNoSubject : m.subject,
      actions: [
        EpSheetAction(label: l.mailReply, value: 'reply', icon: EpIcon.reply),
        EpSheetAction(label: l.mailReplyAll, value: 'replyAll', icon: EpIcon.replyAll),
        EpSheetAction(label: l.mailForward, value: 'forward', icon: EpIcon.forward),
        EpSheetAction(
          label: m.read ? l.mailMarkUnread : l.mailMarkRead,
          value: 'read',
          icon: m.read ? EpIcon.markUnread : EpIcon.markRead,
        ),
        EpSheetAction(
          label: m.starred ? l.mailUnstar : l.mailStar,
          value: 'star',
          icon: m.starred ? EpIcon.star : EpIcon.starFill,
        ),
        if (m.folder != MailFolder.archive && m.folder != MailFolder.trash)
          EpSheetAction(label: l.mailArchive, value: 'archive', icon: EpIcon.archive),
        if (m.folder != MailFolder.inbox) EpSheetAction(label: l.mailMoveToInbox, value: 'inbox', icon: EpIcon.inbox),
        EpSheetAction(
          label: m.folder == MailFolder.trash ? l.mailDeleteForever : l.mailTrash,
          value: 'trash',
          icon: EpIcon.trash,
          destructive: true,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'reply':
          _openCompose(ComposeMode.reply, m);
        case 'replyAll':
          _openCompose(ComposeMode.replyAll, m);
        case 'forward':
          _openCompose(ComposeMode.forward, m);
        case 'read':
          await actions.setRead(m, !m.read);
        case 'star':
          await actions.setStarred(m, !m.starred);
        case 'archive':
          await _moveWithUndo(m, MailFolder.archive, l.mailArchived);
        case 'inbox':
          await _moveWithUndo(m, MailFolder.inbox, l.mailMoved);
        case 'trash':
          await _trash(m);
      }
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeMailError(context, e));
    }
  }

  Future<void> _moveWithUndo(MessageSummary m, MailFolder to, String message) async {
    final actions = ref.read(mailActionsProvider);
    await actions.move(m, to);
    if (!mounted) return;
    showEpToast(
      context,
      message,
      actionLabel: context.l10n.actionUndo,
      onAction: () => actions.move(m.copyWith(folder: to), m.folder),
    );
  }

  Future<void> _trash(MessageSummary m) async {
    final l = context.l10n;
    if (m.folder == MailFolder.trash) {
      final ok = await showEpConfirm(
        context,
        title: l.mailDeleteForever,
        message: l.mailDeleteForeverConfirm,
        confirmLabel: l.actionDelete,
        destructive: true,
      );
      if (!ok) return;
      await ref.read(mailActionsProvider).delete(m);
      if (mounted) showEpToast(context, l.mailDeleted);
      return;
    }
    await _moveWithUndo(m, MailFolder.trash, l.mailTrashed);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final services = ref.watch(mailServicesProvider);
    if (services.isLoading && !services.hasValue) {
      return EpPage(
        title: l.tabMail,
        account: true,
        slivers: const [EpFill(child: EpLoading())],
      );
    }
    if (services.value?[account] == null) return const _NoServiceScreen();

    final listAsync = ref.watch(mailListProvider(_q));
    // Deleted from Cloudflare: nothing here works until it's set up again,
    // so the page holds only that.
    if (isMailServiceMissing(listAsync.error) || isMailServiceMissing(listAsync.value?.refreshError)) {
      return EpPage(
        title: l.tabMail,
        account: true,
        slivers: [EpFill(child: MailServiceMissing(accountId: account))],
      );
    }
    final patches = ref.watch(mailPatchesProvider);
    final boxes = ref.watch(mailboxesProvider(account)).value ?? const <Mailbox>[];
    final unread = boxes
        .where((b) => _domain == null || b.domain == _domain)
        .where((b) => _mailbox == null || b.address == _mailbox)
        .fold(0, (s, b) => s + b.unread);
    final scopeLabel = _mailbox ?? _domain ?? l.mailAllInboxes;

    final open = _open;
    // Only the tab on screen moves its thread over the tabs.
    final onScreen = TickerMode.valuesOf(context).enabled;
    return EpSplit(
      list: (context, split) {
        _split = split;
        if (!split && _open != null && onScreen) _keepOpenThread();
        return _inbox(context, l, account, listAsync, patches, unread, scopeLabel);
      },
      detail: open == null
          ? EpSplitPlaceholder(icon: EpIcon.inbox, text: l.mailSplitPlaceholder)
          : ThreadScreen(
              key: ValueKey(open.$1),
              threadId: open.$1,
              focusId: open.$2,
              onClosed: () => setState(() => _open = null),
            ),
    );
  }

  Widget _inbox(
    BuildContext context,
    AppLocalizations l,
    String account,
    AsyncValue<MailListState> listAsync,
    Map<String, MessageSummary> patches,
    int unread,
    String scopeLabel,
  ) {
    return EpPage(
      title: _folder == MailFolder.inbox ? l.tabMail : _folderLabel(_folder),
      account: true,
      scrollController: _scroll,
      subtitle: Text('$scopeLabel · ${l.mailUnreadCount(unread)}'),
      onRefresh: () async {
        ref.invalidate(mailboxesProvider(account));
        await ref.read(mailListProvider(_q).notifier).refresh();
      },
      actions: [EpAction(icon: EpIcon.filter, label: l.mailChooseInbox(scopeLabel), onPressed: _pickScope)],
      floatingAction: EpAction(icon: EpIcon.compose, label: l.mailCompose, onPressed: _openCompose),
      slivers: [
        const SliverToBoxAdapter(child: _AlertsOffer()),
        SliverToBoxAdapter(child: _controls(context)),
        ...listAsync.when(
          loading: () => [const EpFill(child: EpLoading())],
          error: (e, _) => [
            EpFill(
              child: EpMessage(
                icon: EpIcon.cloud,
                title: describeMailError(context, e),
                action: EpButton(
                  label: l.actionRetry,
                  secondary: true,
                  onPressed: () => ref.invalidate(mailListProvider(_q)),
                ),
              ),
            ),
          ],
          data: (s) => _list(context, s, applyPatches(s.messages, patches, _folder)),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final l = context.l10n;
    final search = isCupertino(context)
        ? CupertinoSearchTextField(controller: _search, placeholder: l.mailSearchPlaceholder, onChanged: _onSearch)
        : SearchBar(
            controller: _search,
            hintText: l.mailSearchPlaceholder,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: _onSearch,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xs, EpSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: EpSpace.md),
          EpSegmented<MailFolder>(
            segments: {for (final f in MailFolder.values) f: _folderLabel(f)},
            value: _folder,
            onChanged: (f) => setState(() => _folder = f),
          ),
        ],
      ),
    );
  }

  List<Widget> _list(BuildContext context, MailListState s, List<MessageSummary> messages) {
    final l = context.l10n;
    final c = EpColors.of(context);
    if (messages.isEmpty) {
      return [
        EpFill(
          child: EpMessage(
            icon: _query.isNotEmpty ? EpIcon.search : EpIcon.inbox,
            title: _query.isNotEmpty
                ? l.emptySearch(_query)
                : (_folder == MailFolder.inbox ? l.mailEmptyInbox : l.mailEmptyFolder(_folderLabel(_folder))),
          ),
        ),
      ];
    }
    return [
      // A failed refresh keeps the last copy on screen and says why.
      if (s.refreshError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
            child: Text(describeMailError(context, s.refreshError!), style: TextStyle(color: c.caution, fontSize: 13)),
          ),
        ),
      // The selected segment already names the folder.
      SliverStripBay(
        itemCount: messages.length,
        itemBuilder: (context, i) => _swipeable(messages[i]),
      ),
      if (s.loadingMore || s.hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: Center(
              child: s.loadingMore
                  ? const CircularProgressIndicator.adaptive()
                  : EpButton(
                      label: l.mailLoadMore,
                      secondary: true,
                      onPressed: () => ref.read(mailListProvider(_q).notifier).loadMore(),
                    ),
            ),
          ),
        ),
    ];
  }

  /// Swipe right to reply (the strip stays), swipe left to archive or trash
  /// (the strip leaves with Undo).
  Widget _swipeable(MessageSummary m) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final leaveTo = m.folder == MailFolder.inbox ? MailFolder.archive : MailFolder.trash;
    final leaveLabel = leaveTo == MailFolder.archive ? l.mailArchive : l.mailTrash;
    Future<void> leave() async {
      _closeIfOpen(m);
      try {
        if (m.folder == MailFolder.trash) {
          await _trash(m);
        } else {
          await _moveWithUndo(m, leaveTo, leaveTo == MailFolder.archive ? l.mailArchived : l.mailTrashed);
        }
      } on Object catch (e) {
        if (mounted) showEpToast(context, describeMailError(context, e));
      }
    }

    // Swipes are hand-offs for touch; screen readers get the same actions
    // from the rotor / actions menu.
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.mailReply): () => _openCompose(ComposeMode.reply, m),
        CustomSemanticsAction(label: leaveLabel): leave,
      },
      child: Dismissible(
        key: ValueKey('swipe-${m.key}'),
        background: _SwipeBg(
          color: c.tintWash,
          onColor: c.tint,
          icon: EpIcon.reply,
          label: l.mailReply,
          alignEnd: false,
        ),
        secondaryBackground: _SwipeBg(
          color: leaveTo == MailFolder.archive ? c.neutralWash : c.attentionWash,
          onColor: leaveTo == MailFolder.archive ? c.ink : c.attention,
          icon: leaveTo == MailFolder.archive ? EpIcon.archive : EpIcon.trash,
          label: leaveLabel,
          alignEnd: true,
        ),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            _openCompose(ComposeMode.reply, m);
            return false;
          }
          if (m.folder == MailFolder.trash) {
            await _trash(m);
            return false;
          }
          try {
            await _moveWithUndo(m, leaveTo, leaveTo == MailFolder.archive ? l.mailArchived : l.mailTrashed);
            _closeIfOpen(m);
            return true;
          } on Object catch (e) {
            if (mounted) showEpToast(context, describeMailError(context, e));
            return false;
          }
        },
        child: MessageStrip(
          message: m,
          showMailbox: _mailbox == null,
          selected: _split && _open?.$1 == m.threadId,
          onTap: () {
            if (!m.read) ref.read(mailActionsProvider).setRead(m, true).ignore();
            _openThread(m);
          },
          onLongPress: () => _messageActions(m),
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.label,
    required this.alignEnd,
  });
  final Color color;
  final Color onColor;
  final EpIcon icon;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(EpRadius.md)),
    padding: const EdgeInsets.symmetric(horizontal: EpSpace.xl),
    alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EpIconView(icon, color: onColor),
        const SizedBox(width: EpSpace.sm),
        Text(
          label,
          style: TextStyle(color: onColor, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _NoServiceScreen extends StatelessWidget {
  const _NoServiceScreen();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return EpPage(
      title: l.tabMail,
      account: true,
      slivers: [
        EpFill(
          child: EpMessage(
            icon: EpIcon.inbox,
            title: l.mailSetupNoService,
            message: l.mailSetupNoServiceBody,
            action: EpButton(label: l.mailSetupStart, onPressed: () => context.push('/mail/setup')),
          ),
        ),
      ],
    );
  }
}

/// One-time, in-context offer to turn on alerts, above the inbox: asks for
/// notification permission only when the user taps Turn on. Inline so it
/// never covers what's on screen; "Not now" hides it for good.
class _AlertsOffer extends ConsumerWidget {
  const _AlertsOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider).value;
    final show = prefs != null && !prefs.any && !prefs.offerDismissed;
    return AnimatedSize(
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: show ? const _AlertsOfferCard() : const SizedBox(width: double.infinity),
    );
  }
}

class _AlertsOfferCard extends ConsumerWidget {
  const _AlertsOfferCard();

  /// One compact row: the inbox stays the first thing on screen, even at
  /// large text. Settings explains each alert.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final prefs = ref.read(notificationPrefsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, 0, EpSpace.lg, EpSpace.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(EpRadius.md),
          border: Border.all(color: c.hairline),
        ),
        child: Padding(
          // Air above and below when the title wraps at large text.
          padding: const EdgeInsetsDirectional.only(start: EpSpace.md, top: EpSpace.xs, bottom: EpSpace.xs),
          child: Row(
            children: [
              EpIconView(EpIcon.bell, size: 18, color: c.tint),
              const SizedBox(width: EpSpace.sm),
              Expanded(
                child: Text(
                  l.notifOfferTitle,
                  style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              EpTextButton(
                label: l.notifOfferAction,
                emphasized: true,
                onPressed: () async {
                  final ok = await prefs.set(mail: true, budget: true, delivery: true);
                  if (!ok && context.mounted) showEpToast(context, l.settingsNotificationsDenied);
                },
              ),
              EpIconButton(
                icon: EpIcon.close,
                size: 18,
                color: c.inkMuted,
                label: l.notifOfferLater,
                onPressed: prefs.dismissOffer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
