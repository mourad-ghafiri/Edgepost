import 'package:intl/intl.dart';

import 'mail_models.dart';
import 'signature.dart';

enum ComposeMode { compose, reply, replyAll, forward }

/// A compose form's starting state. The user's own text, then the signature,
/// go above [quotedText] / [quotedHtml]; [toRequest] assembles the final
/// message.
class ComposeDraft {
  const ComposeDraft({
    required this.mode,
    required this.accountId,
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.quotedText = '',
    this.quotedHtml,
    this.inReplyTo,
    this.forwardOf,
    this.includeOriginalAttachments = false,
    this.originalAttachmentBytes = 0,
  });

  final ComposeMode mode;
  final String accountId;
  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final String quotedText;
  final String? quotedHtml;
  final String? inReplyTo;
  final String? forwardOf;
  final bool includeOriginalAttachments;

  /// Size of the original's attachments re-attached on forward (counts
  /// against the 5 MiB outbound limit).
  final int originalAttachmentBytes;

  SendRequest toRequest({
    required MailAddress from,
    required List<MailAddress> to,
    required List<MailAddress> cc,
    required List<MailAddress> bcc,
    required String subject,
    required String body,
    SignatureBlock signature = const SignatureBlock(),
    bool includeQuote = true,
    List<OutgoingAttachment> attachments = const [],
    bool? includeOriginalAttachments,
  }) {
    final quote = includeQuote ? quotedText : '';
    final sigText = signatureText(signature);
    final text = [body.trimRight(), if (sigText.isNotEmpty) sigText, if (quote.isNotEmpty) quote].join('\n\n');
    // HTML whenever there's something only HTML carries: the quoted original's
    // formatting, or the signature (with its logo and links).
    String? html;
    final quotedPart = !includeQuote
        ? ''
        : (quotedHtml ?? (quote.isEmpty ? '' : '<div dir="auto">${textToHtml(quote)}</div>'));
    if (!signature.isEmpty || (includeQuote && quotedHtml != null)) {
      html = [
        '<div dir="auto">${textToHtml(body.trimRight())}</div>',
        signatureHtml(signature),
        if (quotedPart.isNotEmpty) '<br>$quotedPart',
      ].join();
    }
    return SendRequest(
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      text: text,
      html: html,
      attachments: attachments,
      inReplyTo: inReplyTo,
      forwardOf: forwardOf,
      includeOriginalAttachments: includeOriginalAttachments ?? this.includeOriginalAttachments,
      brandLogo: signature.logo != null,
    );
  }
}

/// Builds reply, reply-all and forward drafts with the conventions mail
/// clients expect:
/// - "From" is the domain address the message landed on.
/// - Reply honours Reply-To; replying to your own sent message goes back to
///   its recipients.
/// - Reply All copies the original To and Cc minus your own addresses.
/// - Subjects get one "Re:" / "Fwd:" prefix, never stacked.
/// - The original is quoted under an attribution line, in text and HTML.
ComposeDraft buildDraft(
  MessageDetail parent, {
  required ComposeMode mode,
  required Set<String> ownAddresses,
  List<MailAddress> identities = const [],
  String? locale,
}) {
  final p = parent.summary;
  final own = {...ownAddresses.map((a) => a.toLowerCase()), p.mailbox.toLowerCase()};
  bool isOwn(MailAddress a) => own.contains(a.address.toLowerCase());

  final from = _identityFor(p, identities);

  var to = <MailAddress>[];
  var cc = <MailAddress>[];
  if (mode == ComposeMode.reply || mode == ComposeMode.replyAll) {
    if (p.outgoing) {
      to = [...p.to];
      if (mode == ComposeMode.replyAll) cc = [...p.cc];
    } else {
      to = p.replyTo.isNotEmpty ? [...p.replyTo] : [p.from];
      if (mode == ComposeMode.replyAll) {
        cc = [...p.to, ...p.cc].where((a) => !isOwn(a)).toList();
      }
    }
    to = _dedupe(to);
    cc = _dedupe(cc).where((a) => !to.any(a.sameAs)).toList();
    // Never send a reply to ourselves unless that's the whole conversation.
    final external = to.where((a) => !isOwn(a)).toList();
    if (external.isNotEmpty) to = external;
  }

  final original = (parent.text?.trim().isNotEmpty ?? false) ? parent.text!.trimRight() : htmlToText(parent.html ?? '');
  final when = DateFormat('EEE, d MMM yyyy \'at\' HH:mm', locale).format(p.date.toLocal());

  String quotedText;
  String? quotedHtml;
  if (mode == ComposeMode.forward) {
    final header = [
      '---------- Forwarded message ---------',
      'From: ${p.from.formatted}',
      'Date: $when',
      'Subject: ${p.subject}',
      'To: ${p.to.map((a) => a.formatted).join(', ')}',
      if (p.cc.isNotEmpty) 'Cc: ${p.cc.map((a) => a.formatted).join(', ')}',
    ].join('\n');
    quotedText = '$header\n\n$original';
    if (parent.html != null) {
      quotedHtml = '<div>${textToHtml(header)}</div><br>${sanitizeForQuote(parent.html!)}';
    }
  } else if (mode == ComposeMode.compose) {
    quotedText = '';
  } else {
    final attribution = 'On $when, ${p.from.formatted} wrote:';
    quotedText = '$attribution\n${original.split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n')}';
    if (parent.html != null) {
      quotedHtml =
          '<div>${_escape(attribution)}</div>'
          '<blockquote style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">'
          '${sanitizeForQuote(parent.html!)}</blockquote>';
    }
  }

  return ComposeDraft(
    mode: mode,
    accountId: p.accountId,
    from: from,
    to: to,
    cc: cc,
    subject: switch (mode) {
      ComposeMode.reply || ComposeMode.replyAll => prefixSubject(p.subject, 'Re:'),
      ComposeMode.forward => prefixSubject(p.subject, 'Fwd:'),
      ComposeMode.compose => '',
    },
    quotedText: quotedText,
    quotedHtml: quotedHtml,
    inReplyTo: mode == ComposeMode.reply || mode == ComposeMode.replyAll ? p.id : null,
    forwardOf: mode == ComposeMode.forward ? p.id : null,
    includeOriginalAttachments: mode == ComposeMode.forward && parent.visibleAttachments.isNotEmpty,
    originalAttachmentBytes: mode == ComposeMode.forward ? parent.visibleAttachments.fold(0, (s, a) => s + a.size) : 0,
  );
}

MailAddress _identityFor(MessageSummary p, List<MailAddress> identities) {
  final wanted = p.outgoing ? p.from.address : p.mailbox;
  for (final i in identities) {
    if (i.address.toLowerCase() == wanted.toLowerCase()) return i;
  }
  return p.outgoing ? p.from : MailAddress(p.mailbox);
}

List<MailAddress> _dedupe(List<MailAddress> list) {
  final seen = <String>{};
  return [
    for (final a in list)
      if (seen.add(a.address.toLowerCase())) a,
  ];
}

/// Adds [prefix] ("Re:" / "Fwd:") unless the subject already carries it or
/// a common localized equivalent.
String prefixSubject(String subject, String prefix) {
  final s = subject.trim();
  final pattern = prefix == 'Re:'
      ? RegExp(r'^(re|aw|sv|antw|r)(\[\d+\])?\s*:', caseSensitive: false)
      : RegExp(r'^(fwd?|wg|tr|rv)\s*:', caseSensitive: false);
  if (pattern.hasMatch(s)) return s;
  return s.isEmpty ? prefix : '$prefix $s';
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Plain text to minimal safe HTML (paragraph breaks preserved).
String textToHtml(String text) => _escape(text).replaceAll('\r\n', '\n').replaceAll('\n', '<br>');

/// Removes active content from HTML before quoting it in an outgoing message.
String sanitizeForQuote(String html) => html
    .replaceAll(RegExp(r'<(script|style|iframe|object|embed)[\s\S]*?</\1>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<(script|iframe|object|embed|link|meta)[^>]*>', caseSensitive: false), '')
    .replaceAll(
      RegExp(
        r'\son\w+\s*=\s*("[^"]*"|'
        "'[^']*'"
        r'|[^\s>]+)',
        caseSensitive: false,
      ),
      '',
    );

/// Best-effort HTML to text for quoting and snippets.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|head)[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|li|h[1-6]|blockquote)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  return s.replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
