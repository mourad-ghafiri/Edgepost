import 'dns_record.dart';

/// Why a field is invalid. The screen maps each to a localized message.
enum DnsFieldError { required, ipv4, ipv6, hostname, recordName, range, flags, type, quotes, tooLong }

/// Form fields of the record editor.
enum DnsField { type, name, content, priority, service, weight, port, target, flags, value }

/// Pure validators, shared by the editor and the templates.
abstract final class DnsValidators {
  static final _ipv4 = RegExp(r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$');
  static final _label = RegExp(r'^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?$');
  static final _type = RegExp(r'^[A-Z][A-Z0-9]{0,9}$');

  static bool isIPv4(String s) => _ipv4.hasMatch(s.trim());

  static bool isIPv6(String s) {
    final v = s.trim();
    if (!v.contains(':') || v.contains('%') || v.contains('[')) return false;
    try {
      Uri.parseIPv6Address(v);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// LDH hostname (underscores allowed for service labels like `_dmarc`),
  /// at most 253 characters with labels of 1–63. An optional trailing dot is
  /// accepted. Internationalized names must be entered in punycode (`xn--`).
  static bool isHostname(String s, {bool allowWildcard = false}) {
    var v = s.trim();
    if (v.endsWith('.')) v = v.substring(0, v.length - 1);
    if (v.isEmpty || v.length > 253) return false;
    final labels = v.split('.');
    for (var i = 0; i < labels.length; i++) {
      final l = labels[i];
      if (allowWildcard && i == 0 && l == '*') continue;
      if (!_label.hasMatch(l)) return false;
    }
    return true;
  }

  /// A record name as typed in the editor: `@`, a relative name, or a fully
  /// qualified one; a leading `*` label makes a wildcard.
  static bool isRecordName(String s) {
    final v = s.trim();
    if (v == '@') return true;
    return isHostname(v, allowWildcard: true);
  }

  /// Parses an unsigned 16-bit value (priority, weight, port).
  static int? uint16(String s) {
    final v = int.tryParse(s.trim());
    return v != null && v >= 0 && v <= 65535 ? v : null;
  }

  /// TXT content made of quoted strings must have matching quotes.
  static bool balancedQuotes(String s) {
    var count = 0;
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\') {
        i++;
      } else if (s[i] == '"') {
        count++;
      }
    }
    return count.isEven;
  }

  static bool isRecordType(String s) => _type.hasMatch(s.trim().toUpperCase());
}

/// Editable state of one record. Holds raw text so the form can show exactly
/// what the user typed; [validate] and [toBody] interpret it.
class DnsDraft {
  DnsDraft({required this.type, this.other = false});

  /// Pre-fills the form from an existing record.
  factory DnsDraft.fromRecord(DnsRecord r, String zone) {
    final known = DnsTypes.editable.contains(r.type);
    final d = DnsDraft(type: r.type, other: !known)
      ..name = DnsNames.relative(r.name, zone)
      ..content = r.content
      ..proxied = r.proxied
      ..ttl = r.ttl
      ..comment = r.comment ?? ''
      ..originalType = r.type
      ..originalData = r.data;
    final data = r.data ?? const <String, dynamic>{};
    String s(Object? v) => v == null ? '' : '$v';
    switch (r.type) {
      case 'MX':
        d.priority = s(r.priority);
      case 'SRV':
        final parts = d.name.split('.');
        if (parts.length >= 2 && parts[0].startsWith('_') && parts[1].startsWith('_')) {
          d.service = parts[0];
          d.proto = parts[1];
          d.name = parts.length > 2 ? parts.sublist(2).join('.') : '@';
        }
        d.priority = s(data['priority'] ?? r.priority);
        d.weight = s(data['weight']);
        d.port = s(data['port']);
        d.target = s(data['target']);
        if (data.isEmpty) _parseSrvContent(d, r.content);
      case 'CAA':
        d.flags = s(data['flags'] ?? 0);
        d.tag = s(data['tag'] ?? 'issue');
        d.value = s(data['value']);
      case 'HTTPS':
        d.priority = s(data['priority']);
        d.target = s(data['target']);
        d.value = s(data['value']);
      case 'URI':
        d.priority = s(r.priority ?? data['priority']);
        d.weight = s(data['weight']);
        d.target = s(data['target']);
    }
    return d;
  }

  /// Uppercase record type. For [other], whatever the user typed.
  String type;

  /// True when the raw "Other" form is used.
  bool other;
  String name = '@';
  String content = '';
  String priority = '';
  String service = '';
  String proto = '_tcp';
  String weight = '';
  String port = '';
  String target = '';
  String flags = '0';
  String tag = 'issue';
  String value = '';
  bool proxied = false;
  int ttl = DnsTypes.autoTtl;
  String comment = '';

  /// Set when editing: the record's type and structured data before edits.
  String? originalType;
  Map<String, dynamic>? originalData;

  static const srvProtocols = ['_tcp', '_udp', '_tls'];
  static const caaTags = ['issue', 'issuewild', 'iodef'];

  String get normalizedType => type.trim().toUpperCase();

  bool get isProxiable => DnsTypes.proxiable.contains(normalizedType);

  /// Proxied records always use automatic TTL.
  int get effectiveTtl => isProxiable && proxied ? DnsTypes.autoTtl : ttl;

  /// A raw-form record whose value lives in `data` (e.g. LOC, DS): its value
  /// is kept as is and only name, TTL and comment are editable here.
  bool get keepsData => other && originalData != null && originalData!.isNotEmpty && normalizedType == originalType;

  bool get isTypeChange => originalType != null && normalizedType != originalType;

  String _serviceLabel() {
    final s = service.trim();
    return s.startsWith('_') ? s : '_$s';
  }

  /// Fully qualified name sent to the API.
  String fullName(String zone) {
    if (normalizedType == 'SRV' && !other) {
      final base = DnsNames.absolute(name, zone);
      return '${_serviceLabel()}.$proto.$base'.toLowerCase();
    }
    return DnsNames.absolute(name, zone);
  }

  Map<DnsField, DnsFieldError> validate(String zone) {
    final e = <DnsField, DnsFieldError>{};
    final t = normalizedType;
    if (other && !DnsValidators.isRecordType(t)) e[DnsField.type] = DnsFieldError.type;

    final n = name.trim();
    if (n.isEmpty) {
      e[DnsField.name] = DnsFieldError.required;
    } else if (!DnsValidators.isRecordName(n)) {
      e[DnsField.name] = DnsFieldError.recordName;
    } else if (fullName(zone).length > 253) {
      e[DnsField.name] = DnsFieldError.tooLong;
    }

    void required(DnsField f, String v) {
      if (v.trim().isEmpty) e[f] = DnsFieldError.required;
    }

    void host(DnsField f, String v, {bool allowApex = true, bool allowRoot = false}) {
      final s = v.trim();
      if (s.isEmpty) {
        e[f] = DnsFieldError.required;
      } else if ((allowApex && s == '@') || (allowRoot && s == '.')) {
        return;
      } else if (!DnsValidators.isHostname(s)) {
        e[f] = DnsFieldError.hostname;
      }
    }

    void u16(DnsField f, String v) {
      if (v.trim().isEmpty) {
        e[f] = DnsFieldError.required;
      } else if (DnsValidators.uint16(v) == null) {
        e[f] = DnsFieldError.range;
      }
    }

    if (other) {
      if (!keepsData) required(DnsField.content, content);
      return e;
    }
    switch (t) {
      case 'A':
        if (content.trim().isEmpty) {
          e[DnsField.content] = DnsFieldError.required;
        } else if (!DnsValidators.isIPv4(content)) {
          e[DnsField.content] = DnsFieldError.ipv4;
        }
      case 'AAAA':
        if (content.trim().isEmpty) {
          e[DnsField.content] = DnsFieldError.required;
        } else if (!DnsValidators.isIPv6(content)) {
          e[DnsField.content] = DnsFieldError.ipv6;
        }
      case 'CNAME' || 'NS' || 'PTR':
        host(DnsField.content, content);
      case 'MX':
        host(DnsField.content, content);
        u16(DnsField.priority, priority);
      case 'TXT':
        required(DnsField.content, content);
        if (!e.containsKey(DnsField.content) && !DnsValidators.balancedQuotes(content)) {
          e[DnsField.content] = DnsFieldError.quotes;
        }
      case 'SRV':
        final s = service.trim().replaceFirst(RegExp('^_'), '');
        if (s.isEmpty) {
          e[DnsField.service] = DnsFieldError.required;
        } else if (!DnsValidators.isHostname('_$s') || s.contains('.')) {
          e[DnsField.service] = DnsFieldError.hostname;
        }
        u16(DnsField.priority, priority);
        u16(DnsField.weight, weight);
        u16(DnsField.port, port);
        host(DnsField.target, target, allowRoot: true);
      case 'CAA':
        final f = int.tryParse(flags.trim());
        if (f == null || f < 0 || f > 255) e[DnsField.flags] = DnsFieldError.flags;
        required(DnsField.value, value);
      case 'HTTPS':
        u16(DnsField.priority, priority);
        host(DnsField.target, target, allowRoot: true);
      case 'URI':
        u16(DnsField.priority, priority);
        u16(DnsField.weight, weight);
        required(DnsField.target, target);
    }
    return e;
  }

  bool isValid(String zone) => validate(zone).isEmpty;

  /// Request body for `POST /dns_records`, a batch `posts` entry, or
  /// `PATCH /dns_records/{id}`. [clearComment] sends an empty comment so an
  /// edit can remove one.
  Map<String, dynamic> toBody(String zone, {bool clearComment = false}) {
    final t = normalizedType;
    final body = <String, dynamic>{'type': t, 'name': fullName(zone)};
    int n(String v) => DnsValidators.uint16(v) ?? 0;
    if (other) {
      if (!keepsData) body['content'] = content.trim();
    } else {
      switch (t) {
        case 'SRV':
          body['data'] = {
            'priority': n(priority),
            'weight': n(weight),
            'port': n(port),
            'target': DnsNames.target(target, zone),
          };
        case 'CAA':
          body['data'] = {'flags': int.tryParse(flags.trim()) ?? 0, 'tag': tag, 'value': value.trim()};
        case 'HTTPS':
          body['data'] = {'priority': n(priority), 'target': DnsNames.target(target, zone), 'value': value.trim()};
        case 'URI':
          body['data'] = {'target': target.trim(), 'weight': n(weight)};
          body['priority'] = n(priority);
        case 'MX':
          body['content'] = DnsNames.target(content, zone);
          body['priority'] = n(priority);
        case 'CNAME' || 'NS' || 'PTR':
          body['content'] = DnsNames.target(content, zone);
        case 'TXT':
          body['content'] = content.trim();
        default:
          body['content'] = content.trim();
      }
    }
    body['ttl'] = effectiveTtl;
    if (isProxiable) body['proxied'] = proxied;
    final c = comment.trim();
    if (c.isNotEmpty) {
      body['comment'] = c;
    } else if (clearComment) {
      body['comment'] = '';
    }
    return body;
  }

  static void _parseSrvContent(DnsDraft d, String content) {
    // Legacy content: "weight port target", priority in the top-level field.
    final p = content.trim().split(RegExp(r'\s+'));
    if (p.length == 3) {
      d
        ..weight = p[0]
        ..port = p[1]
        ..target = p[2];
    } else if (p.length == 4) {
      d
        ..priority = p[0]
        ..weight = p[1]
        ..port = p[2]
        ..target = p[3];
    }
  }
}
