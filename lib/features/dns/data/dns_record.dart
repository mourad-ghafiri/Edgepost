import '../../../core/cloudflare/models.dart';

/// Record types the editor has dedicated forms for, in display order.
/// Anything else is edited through the raw "Other" form.
/// Reference: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/
abstract final class DnsTypes {
  static const editable = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'SRV', 'CAA', 'NS', 'PTR', 'HTTPS', 'URI'];

  /// Only address-resolving records can be proxied:
  /// https://developers.cloudflare.com/dns/proxy-status/
  static const proxiable = {'A', 'AAAA', 'CNAME'};

  /// Types whose value is set through the structured `data` object; their
  /// `content` is formatted by Cloudflare.
  static const structured = {'SRV', 'CAA', 'HTTPS', 'URI'};

  /// Types that take the top-level `priority` field (required for MX and URI).
  static const usesPriority = {'MX', 'URI'};

  /// Automatic TTL is sent as 1 (300 s at the edge).
  static const int autoTtl = 1;

  /// TTL presets, in seconds. Valid custom values are 60 to 86400.
  static const ttlPresets = [autoTtl, 60, 120, 300, 1800, 3600, 43200, 86400];

  /// Sort key: known types first in [editable] order, then the rest A–Z.
  static int order(String type) {
    final i = editable.indexOf(type);
    return i >= 0 ? i : editable.length;
  }
}

/// One DNS record as returned by `GET /zones/{zone_id}/dns_records`.
class DnsRecord {
  const DnsRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.content,
    this.proxied = false,
    this.proxiable = false,
    this.ttl = DnsTypes.autoTtl,
    this.priority,
    this.comment,
    this.tags = const [],
    this.data,
    this.settings,
    this.createdOn,
    this.modifiedOn,
  });

  factory DnsRecord.fromJson(Map<String, dynamic> j) => DnsRecord(
    id: '${j['id'] ?? ''}',
    type: '${j['type'] ?? ''}'.toUpperCase(),
    name: '${j['name'] ?? ''}',
    content: '${j['content'] ?? ''}',
    proxied: j['proxied'] == true,
    proxiable: j['proxiable'] == true,
    ttl: (j['ttl'] as num?)?.toInt() ?? DnsTypes.autoTtl,
    priority: (j['priority'] as num?)?.toInt(),
    comment: _nonEmpty(j['comment']),
    tags: (j['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
    data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : null,
    settings: j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : null,
    createdOn: parseCfDate(j['created_on']),
    modifiedOn: parseCfDate(j['modified_on']),
  );

  final String id;
  final String type;

  /// Fully qualified name, e.g. `www.example.com`.
  final String name;
  final String content;
  final bool proxied;
  final bool proxiable;

  /// Seconds; 1 means automatic.
  final int ttl;
  final int? priority;
  final String? comment;
  final List<String> tags;

  /// Structured value for SRV, CAA, HTTPS, URI and other complex types.
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? settings;
  final DateTime? createdOn;
  final DateTime? modifiedOn;


  /// Whether the proxy toggle applies (what the API says, or the type rule).
  bool get canProxy => proxiable || proxied || DnsTypes.proxiable.contains(type);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'content': content,
    'proxied': proxied,
    'proxiable': proxiable,
    'ttl': ttl,
    'priority': ?priority,
    'comment': ?comment,
    if (tags.isNotEmpty) 'tags': tags,
    'data': ?data,
    'settings': ?settings,
    'created_on': ?createdOn?.toIso8601String(),
    'modified_on': ?modifiedOn?.toIso8601String(),
  };

  /// Body that re-creates this record with `POST /dns_records`, used by undo
  /// after a delete: same type, name, value, TTL, proxy state, priority,
  /// comment, tags and settings.
  Map<String, dynamic> toCreateBody() {
    final structured = data != null && data!.isNotEmpty;
    return {
      'type': type,
      'name': name,
      if (!structured) 'content': content,
      'data': ?(structured ? data : null),
      'ttl': ttl,
      if (canProxy) 'proxied': proxied,
      if (DnsTypes.usesPriority.contains(type) && priority != null) 'priority': priority,
      if (comment != null && comment!.isNotEmpty) 'comment': comment,
      if (tags.isNotEmpty) 'tags': tags,
      if (settings != null && settings!.isNotEmpty) 'settings': settings,
    };
  }

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  DnsRecord copyWith({String? id, bool? proxied, int? ttl}) => DnsRecord(
    id: id ?? this.id,
    type: type,
    name: name,
    content: content,
    proxied: proxied ?? this.proxied,
    proxiable: proxiable,
    ttl: ttl ?? this.ttl,
    priority: priority,
    comment: comment,
    tags: tags,
    data: data,
    settings: settings,
    createdOn: createdOn,
    modifiedOn: modifiedOn,
  );
}

/// `result` of `POST /zones/{zone_id}/dns_records/import`.
class DnsImportResult {
  const DnsImportResult({required this.added, required this.parsed});

  factory DnsImportResult.fromJson(Map<String, dynamic> j) => DnsImportResult(
    added: (j['recs_added'] as num?)?.toInt() ?? 0,
    parsed: (j['total_records_parsed'] as num?)?.toInt() ?? 0,
  );

  final int added;
  final int parsed;
}

/// Name helpers. The API wants fully qualified names; the UI shows them
/// relative to the zone, with `@` for the apex.
abstract final class DnsNames {
  static String relative(String fqdn, String zone) {
    final n = _clean(fqdn);
    final z = _clean(zone);
    if (n == z) return '@';
    if (n.endsWith('.$z')) return n.substring(0, n.length - z.length - 1);
    return n;
  }

  static String absolute(String input, String zone) {
    final n = _clean(input);
    final z = _clean(zone);
    if (n.isEmpty || n == '@') return z;
    if (n == z || n.endsWith('.$z')) return n;
    return '$n.$z';
  }

  /// A hostname value (CNAME target, MX server…) where `@` means the zone.
  static String target(String input, String zone) {
    final n = input.trim();
    if (n == '@') return _clean(zone);
    return n.endsWith('.') && n.length > 1 ? n.substring(0, n.length - 1) : n;
  }

  static String _clean(String s) {
    var n = s.trim().toLowerCase();
    while (n.endsWith('.') && n.length > 1) {
      n = n.substring(0, n.length - 1);
    }
    return n;
  }
}

/// Joins the character strings of a TXT value (`"a" "b"` → `ab`). Values the
/// API returns unquoted are passed through.
String txtValue(String content) {
  final s = content.trim();
  if (!s.startsWith('"')) return s;
  final out = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length) {
      out.write(s[++i]);
    } else if (ch == '"') {
      inQuote = !inQuote;
    } else if (inQuote) {
      out.write(ch);
    }
  }
  return out.toString();
}
