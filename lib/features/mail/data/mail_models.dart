/// Types of the Edgepost Mail Worker API (mail_worker/API.md).
library;

DateTime _date(Object? v) =>
    (v is String ? DateTime.tryParse(v) : null) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class MailAddress {
  const MailAddress(this.address, [this.name]);

  factory MailAddress.fromJson(Object? j) {
    final m = j! as Map;
    final name = m['name'] as String?;
    return MailAddress(m['address'] as String, (name == null || name.trim().isEmpty) ? null : name.trim());
  }

  /// Parses `Name <addr@x>` or a bare address.
  static MailAddress? tryParse(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$').firstMatch(s);
    final addr = (m != null ? m.group(2)! : s).trim();
    if (!isValidEmail(addr)) return null;
    final name = m?.group(1)?.trim();
    return MailAddress(addr, (name == null || name.isEmpty) ? null : name);
  }

  static bool isValidEmail(String s) => RegExp(r'^[^@\s<>(),;:"]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(s.trim());

  final String address;
  final String? name;

  String get domain => address.contains('@') ? address.split('@').last.toLowerCase() : '';
  String get display => name ?? address;
  String get formatted => name == null ? address : '$name <$address>';

  bool sameAs(MailAddress other) => address.toLowerCase() == other.address.toLowerCase();

  Map<String, dynamic> toJson() => {'name': name, 'address': address};

  @override
  bool operator ==(Object other) => other is MailAddress && sameAs(other);

  @override
  int get hashCode => address.toLowerCase().hashCode;
}

enum MailFolder { inbox, sent, archive, trash }

MailFolder _folder(Object? v) => MailFolder.values.firstWhere((f) => f.name == v, orElse: () => MailFolder.inbox);

List<MailAddress> _addrs(Object? v) => (v as List? ?? const []).map(MailAddress.fromJson).toList();

class MessageSummary {
  const MessageSummary({
    required this.id,
    required this.threadId,
    required this.folder,
    required this.outgoing,
    required this.mailbox,
    required this.domain,
    required this.from,
    required this.to,
    required this.cc,
    required this.replyTo,
    required this.subject,
    required this.snippet,
    required this.date,
    required this.inReplyTo,
    required this.read,
    required this.starred,
    required this.hasAttachments,
    required this.size,
    required this.accountId,
  });

  factory MessageSummary.fromJson(Map<String, dynamic> j, {required String accountId}) => MessageSummary(
    id: '${j['id']}',
    threadId: j['threadId'] as String,
    folder: _folder(j['folder']),
    outgoing: j['direction'] == 'out',
    mailbox: '${j['mailbox'] ?? ''}',
    domain: '${j['domain'] ?? ''}',
    from: MailAddress.fromJson(j['from']),
    to: _addrs(j['to']),
    cc: _addrs(j['cc']),
    replyTo: _addrs(j['replyTo']),
    subject: '${j['subject'] ?? ''}',
    snippet: '${j['snippet'] ?? ''}',
    date: _date(j['date']),
    inReplyTo: j['inReplyTo'] as String?,
    read: j['read'] == true,
    starred: j['starred'] == true,
    hasAttachments: j['hasAttachments'] == true,
    size: (j['size'] as num?)?.toInt() ?? 0,
    accountId: accountId,
  );

  final String id;
  final String threadId;
  final MailFolder folder;

  /// Sent by the user (direction "out").
  final bool outgoing;

  /// Domain address the message landed on, or was sent from.
  final String mailbox;
  final String domain;
  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> replyTo;
  final String subject;
  final String snippet;
  final DateTime date;
  final String? inReplyTo;
  final bool read;
  final bool starred;
  final bool hasAttachments;
  final int size;

  /// Cloudflare account whose mail Worker holds this message (app-side tag).
  final String accountId;

  /// Globally unique key across accounts.
  String get key => '$accountId/$id';

  MessageSummary copyWith({bool? read, bool? starred, MailFolder? folder}) => MessageSummary(
    id: id,
    threadId: threadId,
    folder: folder ?? this.folder,
    outgoing: outgoing,
    mailbox: mailbox,
    domain: domain,
    from: from,
    to: to,
    cc: cc,
    replyTo: replyTo,
    subject: subject,
    snippet: snippet,
    date: date,
    inReplyTo: inReplyTo,
    read: read ?? this.read,
    starred: starred ?? this.starred,
    hasAttachments: hasAttachments,
    size: size,
    accountId: accountId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'threadId': threadId,
    'folder': folder.name,
    'direction': outgoing ? 'out' : 'in',
    'mailbox': mailbox,
    'domain': domain,
    'from': from.toJson(),
    'to': to.map((a) => a.toJson()).toList(),
    'cc': cc.map((a) => a.toJson()).toList(),
    'replyTo': replyTo.map((a) => a.toJson()).toList(),
    'subject': subject,
    'snippet': snippet,
    'date': date.toIso8601String(),
    'inReplyTo': inReplyTo,
    'read': read,
    'starred': starred,
    'hasAttachments': hasAttachments,
    'size': size,
    'accountId': accountId,
  };
}

class MailAttachment {
  const MailAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.contentId,
    this.inline = false,
  });

  factory MailAttachment.fromJson(Map<String, dynamic> j) => MailAttachment(
    id: '${j['id']}',
    filename: '${j['filename'] ?? 'attachment'}',
    mimeType: '${j['mimeType'] ?? 'application/octet-stream'}',
    size: (j['size'] as num?)?.toInt() ?? 0,
    contentId: j['contentId'] as String?,
    inline: j['inline'] == true,
  );

  final String id;
  final String filename;
  final String mimeType;
  final int size;
  final String? contentId;
  final bool inline;
}

class MessageDetail {
  const MessageDetail({required this.summary, this.text, this.html, this.attachments = const []});

  factory MessageDetail.fromJson(Map<String, dynamic> j, {required String accountId}) => MessageDetail(
    summary: MessageSummary.fromJson(j, accountId: accountId),
    text: j['text'] as String?,
    html: j['html'] as String?,
    attachments: (j['attachments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MailAttachment.fromJson)
        .toList(),
  );

  final MessageSummary summary;
  final String? text;
  final String? html;
  final List<MailAttachment> attachments;

  List<MailAttachment> get visibleAttachments => attachments.where((a) => !a.inline || a.contentId == null).toList();
}

class Mailbox {
  const Mailbox({
    required this.address,
    required this.domain,
    required this.unread,
    required this.total,
    required this.accountId,
  });

  factory Mailbox.fromJson(Map<String, dynamic> j, {required String accountId}) => Mailbox(
    address: '${j['address']}',
    domain: '${j['domain'] ?? ''}',
    unread: (j['unread'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    accountId: accountId,
  );

  final String address;
  final String domain;
  final int unread;
  final int total;
  final String accountId;
}

class MessagePage {
  const MessagePage(this.messages, this.nextCursor);
  final List<MessageSummary> messages;
  final String? nextCursor;
}

class SyncResult {
  const SyncResult(this.messages, this.deleted, this.cursor, {required this.sendUsage, required this.unreadTotal});
  final List<MessageSummary> messages;
  final List<String> deleted;
  final String cursor;

  /// Live counters reported with every sync.
  final SendUsage sendUsage;
  final int unreadTotal;

  bool get hasChanges => messages.isNotEmpty || deleted.isNotEmpty;
}

class OutgoingAttachment {
  const OutgoingAttachment({required this.filename, required this.mimeType, required this.bytes});
  final String filename;
  final String mimeType;
  final List<int> bytes;
}

/// Body of `POST /v1/send`.
class SendRequest {
  const SendRequest({
    required this.from,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    this.replyTo,
    required this.subject,
    required this.text,
    this.html,
    this.attachments = const [],
    this.inReplyTo,
    this.forwardOf,
    this.includeOriginalAttachments = false,
    this.brandLogo = false,
    this.clientMessageId,
  });

  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final MailAddress? replyTo;
  final String subject;
  final String text;
  final String? html;
  final List<OutgoingAttachment> attachments;

  /// Local id of the message being replied to (the Worker adds In-Reply-To / References).
  final String? inReplyTo;
  final String? forwardOf;
  final bool includeOriginalAttachments;

  /// The Worker attaches the From domain's logo inline, for the HTML's
  /// `cid:` image in the signature.
  final bool brandLogo;

  /// Idempotency key: the Worker returns the first result for a repeat within
  /// 15 minutes, so retrying after a timeout never sends twice.
  final String? clientMessageId;

  SendRequest withClientMessageId(String id) => SendRequest(
    from: from,
    to: to,
    cc: cc,
    bcc: bcc,
    replyTo: replyTo,
    subject: subject,
    text: text,
    html: html,
    attachments: attachments,
    inReplyTo: inReplyTo,
    forwardOf: forwardOf,
    includeOriginalAttachments: includeOriginalAttachments,
    brandLogo: brandLogo,
    clientMessageId: id,
  );
}

/// A domain's logo in the mail service: a PNG, stored at 2× the size it's
/// shown at.
class BrandLogo {
  const BrandLogo({required this.width, required this.height, required this.size, required this.updatedAt});

  factory BrandLogo.fromJson(Map<String, dynamic> j) => BrandLogo(
    width: (j['width'] as num).toInt(),
    height: (j['height'] as num).toInt(),
    size: (j['size'] as num).toInt(),
    updatedAt: j['updatedAt'] as String,
  );

  final int width;
  final int height;
  final int size;

  /// Changes with every new logo: the key of the cached image.
  final String updatedAt;

  /// Shown in mail at half its pixels (sharp on high-density screens),
  /// within 240 × 48.
  (double, double) get shown {
    final s = [240 / width, 48 / height, 0.5].reduce((a, b) => a < b ? a : b);
    return ((width * s).roundToDouble(), (height * s).roundToDouble());
  }

  Map<String, dynamic> toJson() => {'width': width, 'height': height, 'size': size, 'updatedAt': updatedAt};
}

/// What mail sent from a domain ends with: its signature and logo.
class DomainBrand {
  const DomainBrand({required this.domain, required this.signature, this.logo});

  factory DomainBrand.fromJson(Map<String, dynamic> j) => DomainBrand(
    domain: j['domain'] as String,
    signature: j['signature'] as String,
    logo: j['logo'] == null ? null : BrandLogo.fromJson(j['logo'] as Map<String, dynamic>),
  );

  final String domain;
  final String signature;
  final BrandLogo? logo;

  bool get isEmpty => signature.trim().isEmpty && logo == null;

  Map<String, dynamic> toJson() => {'domain': domain, 'signature': signature, 'logo': logo?.toJson()};
}

/// Someone the mail service has sent to (To or Cc), for recipient
/// suggestions.
class MailContact {
  const MailContact({required this.address, this.name, required this.count, required this.lastSent});

  factory MailContact.fromJson(Map<String, dynamic> j) => MailContact(
    address: (j['address'] as String).toLowerCase(),
    name: switch (j['name']) {
      final String n when n.trim().isNotEmpty => n.trim(),
      _ => null,
    },
    count: (j['count'] as num).toInt(),
    lastSent: DateTime.parse(j['lastSent'] as String),
  );

  /// Lower-case.
  final String address;

  /// The display name last sent to.
  final String? name;

  /// Messages sent to it.
  final int count;
  final DateTime lastSent;

  MailAddress get mail => MailAddress(address, name);
  String get domain => address.split('@').last;

  Map<String, dynamic> toJson() => {
    'address': address,
    'name': name,
    'count': count,
    'lastSent': lastSent.toUtc().toIso8601String(),
  };
}

/// One account's deployed mail service, as stored in secure storage.
class MailService {
  const MailService({
    required this.accountId,
    required this.workerUrl,
    required this.apiKey,
    required this.workerVersion,
    required this.domains,
    required this.sendingDomains,
    required this.d1Id,
    required this.r2Bucket,
  });

  factory MailService.fromJson(Map<String, dynamic> j) => MailService(
    accountId: j['accountId'] as String,
    workerUrl: j['workerUrl'] as String,
    apiKey: j['apiKey'] as String,
    workerVersion: j['workerVersion'] as String,
    domains: (j['domains'] as List).cast<String>(),
    sendingDomains: (j['sendingDomains'] as List).cast<String>(),
    d1Id: j['d1Id'] as String,
    r2Bucket: j['r2Bucket'] as String,
  );

  final String accountId;
  final String workerUrl;
  final String apiKey;
  final String workerVersion;
  final List<String> domains;
  final List<String> sendingDomains;
  final String d1Id;
  final String r2Bucket;

  MailService withVersion(String version) => MailService(
    accountId: accountId,
    workerUrl: workerUrl,
    apiKey: apiKey,
    workerVersion: version,
    domains: domains,
    sendingDomains: sendingDomains,
    d1Id: d1Id,
    r2Bucket: r2Bucket,
  );

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'workerUrl': workerUrl,
    'apiKey': apiKey,
    'workerVersion': workerVersion,
    'domains': domains,
    'sendingDomains': sendingDomains,
    'd1Id': d1Id,
    'r2Bucket': r2Bucket,
  };
}

/// Send budget reported by the mail Worker: recipients sent in the last 31
/// days against the user's [limit].
class SendUsage {
  const SendUsage({required this.used, required this.limit, this.resetsAt});

  factory SendUsage.fromJson(Map<String, dynamic> j) => SendUsage(
    used: (j['used'] as num).toInt(),
    limit: (j['limit'] as num).toInt(),
    resetsAt: j['resetsAt'] is String ? DateTime.parse(j['resetsAt'] as String) : null,
  );

  final int used;
  final int limit;
  final DateTime? resetsAt;
}
