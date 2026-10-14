import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart' show EpPressable;
import '../../../core/theme/tokens.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';
import '../data/reply_builder.dart';
import 'compose_screen.dart';
import 'mail_html_view.dart';
import 'mail_widgets.dart';

/// A conversation, oldest first; the focused (or newest) message is open.
/// Reply, Reply all and Forward sit in the bottom toolbar, always in reach.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.threadId, this.focusId, this.onClosed});

  final String threadId;
  final String? focusId;

  /// Shown beside the inbox (an iPad split): what archiving or trashing the
  /// thread does instead of going back.
  final VoidCallback? onClosed;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final Set<String> _expanded = {};
  bool _remoteImages = false;
  bool _initialised = false;

  (String, String) get _threadKey => (ref.read(activeAccountProvider)!.id, widget.threadId);

  MessageSummary? _replyTarget(List<MessageSummary> msgs) {
    if (msgs.isEmpty) return null;
    final focus = msgs.where((m) => m.id == widget.focusId).firstOrNull;
    // Reply to the newest message that isn't ours, else the newest.
    return focus ?? msgs.lastWhere((m) => !m.outgoing, orElse: () => msgs.last);
  }

  void _compose(ComposeMode mode, MessageSummary m) => context.push(
    '/mail/compose',
    extra: ComposeArgs(accountId: m.accountId, mode: mode, parent: m),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(threadProvider(_threadKey));
    final patches = ref.watch(mailPatchesProvider);
    return async.when(
      loading: () => EpPage(
        title: '',
        largeTitle: false,
        slivers: const [EpFill(child: EpLoading())],
      ),
      error: (e, _) => EpPage(
        title: '',
        largeTitle: false,
        slivers: [
          EpFill(
            child: EpMessage(
              icon: EpIcon.cloud,
              title: describeMailError(context, e),
              action: EpButton(
                label: l.actionRetry,
                secondary: true,
                onPressed: () => ref.invalidate(threadProvider(_threadKey)),
              ),
            ),
          ),
        ],
      ),
      data: (raw) {
        final msgs = [for (final m in raw) patches[m.key] ?? m]..sort((a, b) => a.date.compareTo(b.date));
        if (!_initialised && msgs.isNotEmpty) {
          _initialised = true;
          _expanded.add(_replyTarget(msgs)!.id);
          final unread = msgs.where((m) => !m.read).toList();
          _expanded.addAll(unread.map((m) => m.id));
          // Mark read after this frame: providers can't change during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final m in unread) {
              ref.read(mailActionsProvider).setRead(m, true).ignore();
            }
          });
        }
        final target = _replyTarget(msgs);
        final subject = msgs.isEmpty ? '' : (msgs.last.subject.isEmpty ? l.mailNoSubject : msgs.last.subject);
        return EpPage(
          title: subject,
          largeTitle: false,
          onRefresh: () async => ref.invalidate(threadProvider(_threadKey)),
          actions: [
            if (target != null)
              EpAction(
                icon: target.starred ? EpIcon.starFill : EpIcon.star,
                label: target.starred ? l.mailUnstar : l.mailStar,
                onPressed: () => ref.read(mailActionsProvider).setStarred(target, !target.starred),
              ),
          ],
          bottomBar: target == null
              ? null
              : _Toolbar(message: target, onCompose: _compose, onAfterMove: widget.onClosed ?? () => context.pop()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
                child: Text(
                  '${l.mailThreadCount(msgs.length)} · ${msgs.isEmpty ? '' : msgs.first.mailbox}',
                  style: TextStyle(color: EpColors.of(context).inkMuted, fontSize: 13),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: msgs.length,
              itemBuilder: (context, i) {
                final m = msgs[i];
                final open = _expanded.contains(m.id);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
                  child: _MessageCard(
                    summary: m,
                    expanded: open,
                    remoteImages: _remoteImages,
                    onToggle: () => setState(() => open ? _expanded.remove(m.id) : _expanded.add(m.id)),
                    onLoadImages: () => setState(() => _remoteImages = true),
                    onReply: () => _compose(ComposeMode.reply, m),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _MessageCard extends ConsumerWidget {
  const _MessageCard({
    required this.summary,
    required this.expanded,
    required this.remoteImages,
    required this.onToggle,
    required this.onLoadImages,
    required this.onReply,
  });

  final MessageSummary summary;
  final bool expanded;
  final bool remoteImages;
  final VoidCallback onToggle;
  final VoidCallback onLoadImages;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final m = summary;
    // Received mail heads its card with the sender on the card's own
    // surface; your replies sit on a neutral wash as "You → name", so a
    // thread reads as a conversation.
    final mine = m.outgoing;
    final band = mine ? c.neutralWash : c.surface;
    final fg = c.ink;
    final fgMuted = c.inkMuted;
    final who = mine ? l.mailYouTo(m.to.isEmpty ? '' : m.to.first.display) : m.from.display;
    final header = Semantics(
      button: true,
      expanded: expanded,
      label: '$who, ${mailTime(context, m.date)}',
      child: EpPressable(
        onTap: onToggle,
        child: Container(
          color: band,
          padding: const EdgeInsets.fromLTRB(EpSpace.md, EpSpace.md, EpSpace.md, EpSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(who, style: EpType.title(context, size: 16, color: fg)),
                    const SizedBox(height: 2),
                    if (expanded) ...[
                      Text(m.from.address, style: TextStyle(fontSize: 13, color: fgMuted)),
                      const SizedBox(height: 4),
                      _AddrLine(label: l.mailFieldTo, addrs: m.to, color: fgMuted),
                      if (m.cc.isNotEmpty) _AddrLine(label: l.mailFieldCc, addrs: m.cc, color: fgMuted),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat.yMMMd().add_Hm().format(m.date.toLocal()),
                        style: EpType.numbers(TextStyle(color: fgMuted, fontSize: 12)),
                      ),
                    ] else
                      Text(
                        m.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fgMuted, fontSize: 14),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: EpSpace.sm),
              // The long date sits under the sender so the address keeps the
              // full width; only the short time rides on the right.
              if (expanded)
                EpIconButton(icon: EpIcon.reply, label: l.mailReply, color: c.tint, onPressed: onReply)
              else
                Text(mailTime(context, m.date), style: EpType.numbers(TextStyle(color: fgMuted, fontSize: 12))),
            ],
          ),
        ),
      ),
    );

    // A Material surface (not a bare DecoratedBox) so the attachment rows'
    // ink shows on Android.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EpRadius.md),
        side: BorderSide(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (expanded) _Body(summary: m, remoteImages: remoteImages, onLoadImages: onLoadImages),
        ],
      ),
    );
  }
}

class _AddrLine extends StatelessWidget {
  const _AddrLine({required this.label, required this.addrs, required this.color});
  final String label;
  final List<MailAddress> addrs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: EpType.fieldLabel(context, color: color),
          ),
          TextSpan(
            text: addrs.map((a) => a.formatted).join(', '),
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary, required this.remoteImages, required this.onLoadImages});
  final MessageSummary summary;
  final bool remoteImages;
  final VoidCallback onLoadImages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final async = ref.watch(messageDetailProvider((summary.accountId, summary.id)));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(EpSpace.xl), child: EpLoading()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(EpSpace.lg),
        child: Text(describeMailError(context, e), style: TextStyle(color: c.attention)),
      ),
      data: (d) {
        final html = d.html;
        final hasRemote = html != null && RegExp(r'''src\s*=\s*["']?https?:''', caseSensitive: false).hasMatch(html);
        return Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.md, 0, EpSpace.md, EpSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasRemote && !remoteImages)
                Padding(
                  padding: const EdgeInsets.only(bottom: EpSpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(l.mailRemoteImagesBlocked, style: TextStyle(color: c.inkMuted, fontSize: 13)),
                      ),
                      EpTextButton(label: l.mailLoadImages, onPressed: onLoadImages),
                    ],
                  ),
                ),
              if (html != null && html.trim().isNotEmpty)
                MailHtmlView(
                  html: resolveInlineImages(
                    html,
                    ref.watch(inlineImagesProvider((summary.accountId, summary.id))).value ?? const {},
                  ),
                  allowRemote: remoteImages,
                )
              else
                SelectableText(d.text ?? '', style: TextStyle(color: c.ink, fontSize: 16, height: 1.45)),
              if (d.visibleAttachments.isNotEmpty) ...[
                const SizedBox(height: EpSpace.md),
                Text(l.mailAttachments(d.visibleAttachments.length).toUpperCase(), style: EpType.groupLabel(context)),
                const SizedBox(height: EpSpace.xs),
                for (final a in d.visibleAttachments) _AttachmentRow(accountId: summary.accountId, attachment: a),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AttachmentRow extends ConsumerStatefulWidget {
  const _AttachmentRow({required this.accountId, required this.attachment});
  final String accountId;
  final MailAttachment attachment;

  @override
  ConsumerState<_AttachmentRow> createState() => _AttachmentRowState();
}

class _AttachmentRowState extends ConsumerState<_AttachmentRow> {
  bool _busy = false;

  /// Downloads to the app's temp folder and hands the file to the OS share
  /// sheet, which offers Quick Look / the right app.
  Future<void> _open() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(mailClientProvider(widget.accountId)).attachment(widget.attachment.id);
      final dir = await getTemporaryDirectory();
      final safe = widget.attachment.filename.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final file = File('${dir.path}/$safe');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: widget.attachment.mimeType, name: safe)],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } on Object catch (e) {
      if (mounted) showEpToast(context, l.mailAttachmentFailed(describeMailError(context, e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final a = widget.attachment;
    return EpTile(
      leading: EpIconView(a.mimeType.startsWith('image/') ? EpIcon.image : EpIcon.attach, color: c.inkMuted),
      title: Text(a.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
      additionalInfo: Text(formatBytes(a.size), style: EpType.numbers(const TextStyle())),
      trailing: _busy ? const CircularProgressIndicator.adaptive() : EpIconView(EpIcon.share, color: c.tint),
      onTap: _busy ? null : _open,
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.message, required this.onCompose, required this.onAfterMove});
  final MessageSummary message;
  final void Function(ComposeMode, MessageSummary) onCompose;
  final VoidCallback onAfterMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final actions = ref.read(mailActionsProvider);
    final archiveTo = message.folder == MailFolder.archive ? MailFolder.inbox : MailFolder.archive;

    Future<void> move(MailFolder to, String done) async {
      try {
        await actions.move(message, to);
        if (!context.mounted) return;
        showEpToast(
          context,
          done,
          actionLabel: l.actionUndo,
          onAction: () => actions.move(message.copyWith(folder: to), message.folder),
        );
        onAfterMove();
      } on Object catch (e) {
        if (context.mounted) showEpToast(context, describeMailError(context, e));
      }
    }

    final items = <(EpIcon, String, VoidCallback)>[
      (
        EpIcon.archive,
        archiveTo == MailFolder.inbox ? l.mailMoveToInbox : l.mailArchive,
        () => move(archiveTo, archiveTo == MailFolder.inbox ? l.mailMoved : l.mailArchived),
      ),
      (EpIcon.trash, l.mailTrash, () => move(MailFolder.trash, l.mailTrashed)),
      (EpIcon.reply, l.mailReply, () => onCompose(ComposeMode.reply, message)),
      (EpIcon.replyAll, l.mailReplyAll, () => onCompose(ComposeMode.replyAll, message)),
      (EpIcon.forward, l.mailForward, () => onCompose(ComposeMode.forward, message)),
    ];

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        for (final (icon, label, onTap) in items)
          isCupertino(context)
              ? Semantics(
                  button: true,
                  label: label,
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    onPressed: onTap,
                    child: Icon(icon.cupertino, size: 24),
                  ),
                )
              : IconButton(tooltip: label, onPressed: onTap, icon: Icon(icon.material)),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row),
      ),
    );
  }
}
