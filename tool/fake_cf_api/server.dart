// Local stand-in for the Cloudflare v4 API and the Edgepost mail Worker,
// for running the app in a simulator/emulator without any real account.
//
//   dart run tool/fake_cf_api/server.dart            # listens on 127.0.0.1:8789
//   flutter run --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 \
//               --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
//   (Android emulator: use 10.0.2.2 instead of 127.0.0.1)
//
// Every name, address and number here is synthetic demo data. Any token is
// accepted; its text picks the accounts it reaches: one containing "ember"
// reaches Studio Ember, "agency" or "both" reaches both accounts, anything
// else Atelier Nord. Each account has its own zones, Workers, Pages, billing
// and mailbox (the mail Worker tells them apart by the API key uploaded with
// it). State lives in memory and resets on restart, except the mail API keys
// it learned (.dart_tool/fake_cf_api_mail_keys.json), so mailboxes the app
// already set up keep working.
//
//   curl -X POST 'http://127.0.0.1:8789/_demo/arrive?account=ember'   # new mail
//   curl -X POST 'http://127.0.0.1:8789/_demo/remove-mail?account=ember'  # as if its
//     Worker, database and bucket were deleted in the dashboard: bare 404s until
//     the app sets the mail service up again
import 'dart:convert';
import 'dart:io';

final _now = DateTime.now().toUtc();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

const _acc = {'id': 'acc0000000000000000000000000001', 'name': 'Atelier Nord'};
const _ember = {'id': 'acc0000000000000000000000000002', 'name': 'Studio Ember'};
const _accounts = [_acc, _ember];

/// The accounts a token reaches (see the header).
List<Map<String, String>> _reach(HttpRequest req) {
  final token = (req.headers.value('authorization') ?? '').toLowerCase();
  if (token.contains('agency') || token.contains('both')) return _accounts;
  if (token.contains('ember')) return const [_ember];
  return const [_acc];
}

bool _isEmber(String accountId) => accountId == _ember['id'];

Map<String, dynamic> _zone(String id, String name,
        {String status = 'active', bool paused = false, int dev = 0, String plan = 'Free Website', Map<String, String> account = _acc}) =>
    {
      'id': id,
      'name': name,
      'status': status,
      'paused': paused,
      'type': 'full',
      'development_mode': dev,
      'name_servers': ['ada.ns.cloudflare.com', 'rex.ns.cloudflare.com'],
      'original_name_servers': ['ns1.registrar.example', 'ns2.registrar.example'],
      'original_registrar': 'example registrar',
      'account': account,
      'plan': {'name': plan},
      'created_on': _ago(const Duration(days: 420)),
      'activated_on': status == 'active' ? _ago(const Duration(days: 418)) : null,
    };

final zones = [
  _zone('z1', 'atelier-nord.dev', plan: 'Pro Website'),
  _zone('z2', 'nordlight.app', status: 'pending'),
  _zone('z3', 'quietharbor.io', dev: 7400),
  _zone('z5', 'fieldnotes.blog'),
  _zone('z6', 'kestrel-labs.dev'),
  _zone('z4', 'studio-ember.com', paused: true, account: _ember),
  _zone('z7', 'ember-kiln.shop', account: _ember),
];

final dns = <String, List<Map<String, dynamic>>>{
  for (final z in zones)
    z['id'] as String: [
      {'id': '${z['id']}-a', 'type': 'A', 'name': z['name'], 'content': '203.0.113.24', 'proxied': true, 'proxiable': true, 'ttl': 1, 'comment': null, 'tags': <String>[]},
      {'id': '${z['id']}-w', 'type': 'CNAME', 'name': 'www.${z['name']}', 'content': z['name'], 'proxied': true, 'proxiable': true, 'ttl': 1, 'tags': <String>[]},
      {'id': '${z['id']}-mx1', 'type': 'MX', 'name': z['name'], 'content': 'route1.mx.cloudflare.net', 'priority': 12, 'proxied': false, 'proxiable': false, 'ttl': 1, 'tags': <String>[]},
      {'id': '${z['id']}-mx2', 'type': 'MX', 'name': z['name'], 'content': 'route2.mx.cloudflare.net', 'priority': 37, 'proxied': false, 'proxiable': false, 'ttl': 1, 'tags': <String>[]},
      {'id': '${z['id']}-spf', 'type': 'TXT', 'name': z['name'], 'content': '"v=spf1 include:_spf.mx.cloudflare.net ~all"', 'proxied': false, 'proxiable': false, 'ttl': 1, 'tags': <String>[]},
      {'id': '${z['id']}-dmarc', 'type': 'TXT', 'name': '_dmarc.${z['name']}', 'content': '"v=DMARC1; p=none; rua=mailto:dmarc@${z['name']}"', 'proxied': false, 'proxiable': false, 'ttl': 3600, 'tags': <String>[]},
    ],
};

final settings = <String, Map<String, dynamic>>{
  for (final z in zones)
    z['id'] as String: {
      'ssl': 'full',
      'always_use_https': 'on',
      'automatic_https_rewrites': 'on',
      'min_tls_version': '1.2',
      'tls_1_3': 'on',
      'development_mode': (z['development_mode'] as int) > 0 ? 'on' : 'off',
      'security_level': 'medium',
    },
};

// ---------------------------------------------------------------- mail ----

/// One account's mail Worker: its messages, sending budget and domains.
/// As the Worker's makeSnippet: whitespace collapsed, at most 160 characters.
String _snippet(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > 160 ? t.substring(0, 160).trimRight() : t;
}

/// The demo's mail service runs the Worker the app bundles: never "Update
/// available" in the demo.
final String _bundleVersion =
    (jsonDecode(File('assets/worker/manifest.json').readAsStringSync()) as Map<String, dynamic>)['version'] as String;

/// A one-page PDF any viewer opens, for the demo's seeded attachments.
final List<int> _demoPdf = () {
  const text = 'BT /F1 24 Tf 72 760 Td (Invoice 2026-118 - demo data) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${text.length} >>\nstream\n$text\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, body) in objects.indexed) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n$body\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return ascii.encode(out.toString());
}();

class _Mailbox {
  _Mailbox(this.owner, this.domains, {required this.sentInWindow});

  /// Display name on outgoing mail.
  final String owner;
  final List<String> domains;
  int seq = 100;
  int arrivals = 0;
  int sendLimit = 3000;
  int sentInWindow;
  final sentByClientId = <String, Map<String, dynamic>>{};

  /// Its Worker was deleted (`/_demo/remove-mail`): the next upload brings
  /// it back, empty.
  bool removed = false;
  final mail = <Map<String, dynamic>>[];
  final bodies = <String, Map<String, dynamic>>{};

  /// Domain → signature and logo (PNG bytes and its size).
  final brands = <String, ({String signature, List<int>? logo, int width, int height, String updatedAt})>{};

  /// Bytes of attachments the demo serves for real (files sent, the inline
  /// logo), with their type.
  final attachmentBytes = <String, ({List<int> bytes, String type})>{};

  Map<String, dynamic> brandJson(String domain) {
    final b = brands[domain];
    return {
      'domain': domain,
      'signature': b?.signature ?? '',
      'logo': b?.logo == null
          ? null
          : {'type': 'image/png', 'size': b!.logo!.length, 'width': b.width, 'height': b.height, 'updatedAt': b.updatedAt},
    };
  }

  void add(String id, String thread, String from, String fromName, String mailbox, String subject, String text,
      {Duration ago = Duration.zero, bool read = false, bool out = false, String folder = 'inbox', List<Map<String, dynamic>> att = const [], String? html}) {
    final domain = mailbox.split('@').last;
    mail.add({
      'id': id,
      'threadId': thread,
      'folder': out ? 'sent' : folder,
      'direction': out ? 'out' : 'in',
      'mailbox': mailbox,
      'domain': domain,
      'from': out ? {'name': owner, 'address': mailbox} : {'name': fromName, 'address': from},
      'to': out ? [{'name': fromName, 'address': from}] : [{'name': null, 'address': mailbox}],
      'cc': <Object>[],
      'replyTo': <Object>[],
      'subject': subject,
      'snippet': _snippet(text),
      'date': _ago(ago),
      'inReplyTo': null,
      'read': read || out,
      'starred': false,
      'hasAttachments': att.isNotEmpty,
      'size': 3000 + text.length,
      'seq': ++seq,
    });
    bodies[id] = {'text': text, 'html': html, 'attachments': att};
  }
}

/// Atelier Nord's sending budget is 82% used, so the Budget strip shows its
/// caution state; Studio Ember's is nearly untouched.
final _mailboxes = {
  _acc['id']!: _Mailbox('Atelier Nord', ['atelier-nord.dev', 'fieldnotes.blog', 'kestrel-labs.dev'], sentInWindow: 2460),
  _ember['id']!: _Mailbox('Studio Ember', ['studio-ember.com', 'ember-kiln.shop'], sentInWindow: 140),
};

/// Mail API key → account, learned when the app uploads the mail Worker.
final _mailKeysFile = File('.dart_tool/fake_cf_api_mail_keys.json');
final _mailKeys = <String, String>{
  if (_mailKeysFile.existsSync()) ...(jsonDecode(_mailKeysFile.readAsStringSync()) as Map).cast<String, String>(),
};

void _learnMailKey(String key, String accountId) {
  _mailKeys[key] = accountId;
  _mailKeysFile.writeAsStringSync(jsonEncode(_mailKeys));
}

/// The mailbox an API key belongs to (unknown keys, e.g. from a previous
/// run of this server: Atelier Nord's).
_Mailbox _mailboxFor(HttpRequest req) {
  final key = (req.headers.value('authorization') ?? '').replaceFirst('Bearer ', '');
  return _mailboxes[_mailKeys[key] ?? _acc['id']]!;
}

void _seedMail() {
  final nord = _mailboxes[_acc['id']]!;
  // The demo studio's own logo (rendered by sample_logo_test.dart), so a
  // logo shows without a picker, and never Edgepost's mark.
  final demoLogo = File('tool/fake_cf_api/sample_logo.png');
  if (demoLogo.existsSync()) {
    nord.brands['atelier-nord.dev'] = (
      signature: 'Atelier Nord\nDesign and development studio\natelier-nord.dev',
      logo: demoLogo.readAsBytesSync(),
      width: 340,
      height: 96,
      updatedAt: _now.toIso8601String(),
    );
  }
  nord.add('m1', 't1', 'lena@varga-design.example', 'Lena Varga', 'contact@atelier-nord.dev', 'Invoice 2026-118 for October',
      'Hi,\n\nPlease find the October invoice attached. Payment terms as usual, 30 days.\n\nThanks for the smooth launch!\nLena',
      ago: const Duration(minutes: 18),
      att: [
        {'id': 'a1', 'filename': 'invoice-2026-118.pdf', 'mimeType': 'application/pdf', 'size': _demoPdf.length, 'contentId': null, 'inline': false},
      ]);
  nord.add('m2', 't2', 'sam@clientco.example', 'Sam Okafor', 'projects@atelier-nord.dev', 'Kick-off next Tuesday?',
      'Hey team,\n\nCould we move the kick-off to Tuesday 10:00? I have a conflict on Monday.\n\nBest,\nSam',
      ago: const Duration(hours: 2),
      html: '<p>Hey team,</p><p>Could we move the kick-off to <b>Tuesday 10:00</b>? I have a conflict on Monday.</p><p>Best,<br>Sam</p><img src="https://tracker.example/p.gif" width="1" height="1">');
  nord.add('m3', 't3', 'noreply@status.example', 'Uptime Monitor', 'ops@kestrel-labs.dev', 'kestrel-labs.dev recovered after 4 min',
      'Your check "Homepage" is up again. Downtime: 4 minutes.', ago: const Duration(hours: 5));
  nord.add('m4', 't4', 'maya@fieldnotes-readers.example', 'Maya Chen', 'letters@fieldnotes.blog', 'Loved the post on night trains',
      'Hello!\n\nJust wanted to say your piece on night trains made my week. Are you planning a follow-up on the Baltic routes?\n\nMaya',
      ago: const Duration(days: 1), read: true);
  nord.add('m5', 't2', 'sam@clientco.example', 'Sam Okafor', 'projects@atelier-nord.dev', 'Re: Kick-off next Tuesday?',
      'Tuesday 10:00 works for us. See you there.', ago: const Duration(minutes: 50), out: true);
  // Earlier sends: who the compose screen suggests.
  nord.add('m7', 't7', 'lena.berg@gmail.com', 'Lena Berg', 'projects@atelier-nord.dev', 'Wireframes, round 2',
      'Hi Lena,\n\nRound 2 of the wireframes is attached. Notes inline.', ago: const Duration(days: 2), out: true);
  nord.add('m8', 't8', 'lena.berg@gmail.com', 'Lena Berg', 'projects@atelier-nord.dev', 'Invoice 2026-117',
      'Hi Lena,\n\nHere is the invoice for September.', ago: const Duration(days: 9), out: true);
  nord.add('m9', 't9', 'helene.martin@orange.fr', 'Hélène Martin', 'contact@atelier-nord.dev', 'Devis pour le site',
      'Bonjour Hélène,\n\nVoici le devis comme convenu.', ago: const Duration(days: 4), out: true);
  nord.add('m10', 't4', 'maya@fieldnotes-readers.example', 'Maya Chen', 'letters@fieldnotes.blog', 'Re: Loved the post on night trains',
      'Thank you Maya! The Baltic piece is next.', ago: const Duration(hours: 20), out: true);
  nord.add('m6', 't6', 'billing@hosting.example', 'Hosting Billing', 'billing@atelier-nord.dev', 'Receipt for your renewal',
      'Thanks for renewing. Amount charged: €18.00.', ago: const Duration(days: 3), read: true, folder: 'archive');

  final ember = _mailboxes[_ember['id']]!;
  ember.add('e1', 'et1', 'ines@duarte-photo.example', 'Ines Duarte', 'hello@studio-ember.com', 'Gallery photos for the kiln shop',
      'Hi!\n\nThe edited gallery is ready: 42 photos, web and print sizes. Want me to upload them to the shop directly?\n\nInes',
      ago: const Duration(minutes: 35));
  ember.add('e2', 'et2', 'orders@ember-kiln.shop', 'Kiln Shop Orders', 'orders@ember-kiln.shop', 'New order #1042',
      'Order #1042: 2 × Speckled mug, 1 × Serving bowl. Ship by Friday.', ago: const Duration(hours: 6), read: true);
}

// ---------------------------------------------------------------- http ----

Map<String, dynamic> _ok(Object? result, {Map<String, dynamic>? info}) =>
    {'success': true, 'errors': <Object>[], 'messages': <Object>[], 'result': result, 'result_info': ?info};

Map<String, dynamic> _page(List<Object?> all, Map<String, String> q) {
  final per = int.tryParse(q['per_page'] ?? '') ?? 50;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final start = (page - 1) * per;
  final slice = all.skip(start).take(per).toList();
  return _ok(slice, info: {'page': page, 'per_page': per, 'count': slice.length, 'total_count': all.length, 'total_pages': (all.length / per).ceil().clamp(1, 9999)});
}

Future<void> main(List<String> args) async {
  _seedMail();
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8789;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Fake Cloudflare API + mail Worker on http://127.0.0.1:$port');
  await for (final req in server) {
    try {
      await _handle(req);
    } on Object catch (e) {
      req.response.statusCode = 500;
      req.response.write(jsonEncode({'success': false, 'errors': [{'code': 1, 'message': '$e'}]}));
      await req.response.close();
    }
  }
}

Future<void> _handle(HttpRequest req) async {
  final path = req.uri.path;
  final q = req.uri.queryParameters;
  final m = req.method;
  final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  final raw = utf8.decode(bytes, allowMalformed: true);
  Object? body;
  try {
    body = raw.isEmpty ? null : jsonDecode(raw);
  } on FormatException {
    body = null; // multipart uploads
  }
  stdout.writeln('$m $path');

  Object? out;
  var status = 200;
  final cf = path.startsWith('/client/v4') ? path.substring('/client/v4'.length) : null;

  if (cf != null) {
    final seg = cf.split('/').where((s) => s.isNotEmpty).toList();
    final reach = _reach(req);
    switch ((m, seg)) {
      case ('GET', ['user', 'tokens', 'verify']):
        out = _ok({'id': 'tok1', 'status': 'active', 'expires_on': _now.add(const Duration(days: 180)).toIso8601String()});
      case ('GET', ['accounts']):
        out = _page(reach, q);
      case ('GET', ['zones']):
        final reached = {for (final a in reach) a['id']};
        out = _page([
          for (final z in zones)
            if (reached.contains((z['account'] as Map)['id']) && (q['account.id'] == null || (z['account'] as Map)['id'] == q['account.id'])) z,
        ], q);
      case ('GET', ['zones', final id]):
        out = _ok(zones.firstWhere((z) => z['id'] == id));
      case ('PATCH', ['zones', final id]):
        final z = zones.firstWhere((z) => z['id'] == id);
        if (body is Map && body.containsKey('paused')) z['paused'] = body['paused'];
        out = _ok(z);
      case ('GET', ['zones', final id, 'dns_records']):
        var list = dns[id] ?? [];
        if (q['type'] != null) list = list.where((r) => r['type'] == q['type']).toList();
        out = _page(list, q);
      case ('POST', ['zones', final id, 'dns_records']):
        final r = {...(body as Map<String, dynamic>), 'id': 'r${DateTime.now().microsecondsSinceEpoch}', 'proxiable': ['A', 'AAAA', 'CNAME'].contains(body['type'])};
        dns[id]!.add(r);
        out = _ok(r);
      case ('PATCH', ['zones', final id, 'dns_records', final rid]):
        final r = dns[id]!.firstWhere((x) => x['id'] == rid)..addAll(body as Map<String, dynamic>);
        out = _ok(r);
      case ('DELETE', ['zones', final id, 'dns_records', final rid]):
        dns[id]!.removeWhere((x) => x['id'] == rid);
        out = _ok({'id': rid});
      case ('POST', ['zones', final id, 'dns_records', 'batch']):
        final b = body as Map<String, dynamic>;
        for (final d in (b['deletes'] as List? ?? const [])) {
          dns[id]!.removeWhere((x) => x['id'] == (d as Map)['id']);
        }
        final posts = [
          for (final p in (b['posts'] as List? ?? const []))
            {...(p as Map<String, dynamic>), 'id': 'r${DateTime.now().microsecondsSinceEpoch}${p.hashCode}'},
        ];
        dns[id]!.addAll(posts);
        out = _ok({'deletes': b['deletes'] ?? [], 'posts': posts, 'patches': [], 'puts': []});
      case ('GET', ['zones', final id, 'dns_records', 'export']):
        req.response.headers.contentType = ContentType.text;
        req.response.write([for (final r in dns[id]!) '${r['name']}.\t${r['ttl']}\tIN\t${r['type']}\t${r['priority'] ?? ''} ${r['content']}'].join('\n'));
        await req.response.close();
        return;
      case ('GET', ['zones', final id, 'settings', final sid]):
        out = _ok({'id': sid, 'value': settings[id]![sid] ?? 'off', 'editable': true, if (sid == 'development_mode') 'time_remaining': (zones.firstWhere((z) => z['id'] == id)['development_mode'])});
      case ('PATCH', ['zones', final id, 'settings', final sid]):
        settings[id]![sid] = (body as Map)['value'];
        out = _ok({'id': sid, 'value': body['value'], 'editable': true});
      case ('POST', ['zones', _, 'purge_cache']):
        out = _ok({'id': 'purge1'});
      case ('GET', ['zones', _, 'dnssec']):
        out = _ok({'status': 'active', 'algorithm': '13', 'digest_type': '2', 'ds': 'example.com. 3600 IN DS 2371 13 2 1F987C…', 'key_tag': 2371});
      case ('GET', ['zones', final id, 'email', 'routing']):
        out = _ok({'id': id, 'name': zones.firstWhere((z) => z['id'] == id)['name'], 'enabled': id != 'z2', 'status': id == 'z2' ? 'unconfigured' : 'ready'});
      case ('GET', ['zones', _, 'email', 'routing', 'dns']):
        out = _ok([
          {'type': 'MX', 'name': '@', 'content': 'route1.mx.cloudflare.net', 'priority': 12, 'ttl': 1},
          {'type': 'TXT', 'name': '@', 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all', 'ttl': 1},
        ]);
      case ('POST' || 'PATCH' || 'DELETE', ['zones', _, 'email', 'routing', 'dns']):
        out = _ok({'enabled': m != 'DELETE', 'status': m == 'DELETE' ? 'unconfigured' : 'ready'});
      case ('GET', ['zones', final id, 'email', 'routing', 'rules']):
        final name = zones.firstWhere((z) => z['id'] == id)['name'];
        out = _page([
          {'id': 'rule1', 'tag': 'rule1', 'name': 'contact', 'enabled': true, 'priority': 0, 'matchers': [{'type': 'literal', 'field': 'to', 'value': 'contact@$name'}], 'actions': [{'type': 'worker', 'value': ['edgepost-mail']}]},
          {'id': 'rule2', 'tag': 'rule2', 'name': 'personal', 'enabled': true, 'priority': 1, 'matchers': [{'type': 'literal', 'field': 'to', 'value': 'me@$name'}], 'actions': [{'type': 'forward', 'value': ['owner@personal-mail.example']}]},
        ], q);
      case ('GET', ['zones', _, 'email', 'routing', 'rules', 'catch_all']):
        out = _ok({'id': 'ca', 'tag': 'ca', 'enabled': true, 'matchers': [{'type': 'all'}], 'actions': [{'type': 'worker', 'value': ['edgepost-mail']}]});
      case ('PUT' || 'POST', ['zones', _, 'email', 'routing', 'rules', ...]):
        out = _ok({...?(body as Map<String, dynamic>?), 'id': 'rule${DateTime.now().millisecondsSinceEpoch}'});
      case ('GET', ['accounts', _, 'email', 'routing', 'addresses']):
        out = _page([
          {'id': 'dest1', 'email': 'owner@personal-mail.example', 'verified': _ago(const Duration(days: 300)), 'created': _ago(const Duration(days: 301))},
          {'id': 'dest2', 'email': 'backup@other-mail.example', 'verified': null, 'created': _ago(const Duration(hours: 3))},
        ], q);
      case ('GET', ['zones', _, 'email', 'auth', 'spf', 'inspect']):
        out = _ok({'record': 'v=spf1 include:_spf.mx.cloudflare.net ~all', 'lookups': 2});
      case ('GET', ['zones', _, 'email', 'auth', 'dmarc-reports']):
        out = _ok({'enabled': false, 'status': 'missing-dmarc-rua'});
      case ('GET', ['zones', final id, 'workers', 'routes']):
        out = _ok([
          if (id == 'z1') {'id': 'wr1', 'pattern': 'atelier-nord.dev/api/*', 'script': 'contact-form'},
          if (id == 'z7') {'id': 'wr2', 'pattern': 'ember-kiln.shop/api/*', 'script': 'kiln-shop-api'},
        ]);
      case ('GET', ['accounts', final acc, 'workers', 'scripts']):
        out = _ok([
          if (_isEmber(acc))
            {'id': 'kiln-shop-api', 'created_on': _ago(const Duration(days: 60)), 'modified_on': _ago(const Duration(hours: 20)), 'compatibility_date': '2026-09-15', 'handlers': ['fetch']}
          else ...[
            {'id': 'contact-form', 'created_on': _ago(const Duration(days: 90)), 'modified_on': _ago(const Duration(days: 2)), 'compatibility_date': '2026-08-01', 'usage_model': 'standard', 'handlers': ['fetch']},
            {'id': 'og-image', 'created_on': _ago(const Duration(days: 200)), 'modified_on': _ago(const Duration(days: 40)), 'compatibility_date': '2026-03-10', 'handlers': ['fetch']},
          ],
          {'id': 'edgepost-mail', 'created_on': _ago(const Duration(days: 10)), 'modified_on': _ago(const Duration(days: 10)), 'compatibility_date': '2026-09-01', 'handlers': ['fetch', 'email', 'scheduled']},
        ]);
      case ('GET', ['accounts', final acc, 'pages', 'projects']):
        out = _page([
          if (!_isEmber(acc)) {
            'name': 'fieldnotes-site',
            'subdomain': 'fieldnotes-site.pages.dev',
            'domains': ['fieldnotes.blog'],
            'production_branch': 'main',
            'created_on': _ago(const Duration(days: 300)),
            'latest_deployment': {
              'id': 'dep-ok-1', 'short_id': 'a1b2c3d4', 'environment': 'production', 'url': 'https://a1b2c3d4.fieldnotes-site.pages.dev',
              'created_on': _ago(const Duration(hours: 3)), 'modified_on': _ago(const Duration(hours: 3)),
              'latest_stage': {'name': 'deploy', 'status': 'success', 'started_on': _ago(const Duration(hours: 3)), 'ended_on': _ago(const Duration(hours: 3))},
              'deployment_trigger': {'type': 'github:push', 'metadata': {'branch': 'main', 'commit_hash': 'a1b2c3d', 'commit_message': 'Night trains, part 2'}},
            },
          },
          if (_isEmber(acc)) {
            'name': 'ember-portfolio',
            'subdomain': 'ember-portfolio.pages.dev',
            'domains': ['studio-ember.com'],
            'production_branch': 'main',
            'created_on': _ago(const Duration(days: 120)),
            'latest_deployment': {
              'id': 'dep-fail-1', 'short_id': 'e9f8d7c6', 'environment': 'production', 'url': 'https://e9f8d7c6.ember-portfolio.pages.dev',
              'created_on': _ago(const Duration(hours: 2)), 'modified_on': _ago(const Duration(hours: 2)),
              'latest_stage': {'name': 'build', 'status': 'failure', 'started_on': _ago(const Duration(hours: 2)), 'ended_on': _ago(const Duration(hours: 2))},
              'deployment_trigger': {'type': 'github:push', 'metadata': {'branch': 'main', 'commit_hash': 'e9f8d7c', 'commit_message': 'Update gallery'}},
            },
          },
        ], q);
      case ('GET', ['accounts', final acc, 'registrar', 'registrations']):
        out = _ok([
          if (_isEmber(acc))
            {'domain_name': 'ember-kiln.shop', 'expires_at': _now.add(const Duration(days: 9)).toIso8601String(), 'auto_renew': false, 'locked': true, 'status': 'active'}
          else ...[
            {'domain_name': 'atelier-nord.dev', 'expires_at': _now.add(const Duration(days: 210)).toIso8601String(), 'auto_renew': true, 'locked': true, 'status': 'active'},
            {'domain_name': 'kestrel-labs.dev', 'expires_at': _now.add(const Duration(days: 12)).toIso8601String(), 'auto_renew': false, 'locked': true, 'status': 'active'},
          ],
        ]);
      case ('GET', ['accounts', _, 'd1', 'database']):
        out = _page([], q);
      case ('POST', ['accounts', _, 'd1', 'database']):
        out = _ok({'uuid': 'd1-demo-uuid', 'name': 'edgepost-mail'});
      case ('GET', ['accounts', _, 'r2', 'buckets']):
        out = _ok({'buckets': <Object>[]});
      case ('POST', ['accounts', _, 'r2', 'buckets']):
        out = _ok({'name': 'edgepost-mail'});
      case ('PUT', ['accounts', final acc, 'workers', 'scripts', final name]):
        // The mail Worker's upload carries its API key: mail calls with that
        // key go to this account's mailbox.
        final key = RegExp(r'"name"\s*:\s*"MAIL_API_KEY"\s*,\s*"text"\s*:\s*"([^"]+)"').firstMatch(raw)?.group(1);
        if (key != null) _learnMailKey(key, acc);
        _mailboxes[acc]?.removed = false;
        out = _ok({'id': name});
      case ('GET', ['accounts', final acc, 'workers', 'subdomain']):
        out = _ok({'subdomain': _isEmber(acc) ? 'studio-ember' : 'atelier-nord'});
      case ('POST', ['accounts', _, 'workers', 'scripts', _, 'subdomain']):
        out = _ok({'enabled': true, 'previews_enabled': false});
      case ('PUT', ['accounts', _, 'workers', 'scripts', _, 'schedules']):
        out = _ok({'schedules': body});
      case ('GET', ['zones', _, 'email', 'sending', 'subdomains']):
        out = _page([], q);
      case ('POST', ['zones', _, 'email', 'sending', 'subdomains']):
        out = _ok({'enabled': true, 'name': (body as Map)['name'], 'tag': 'send1'});
      case ('GET', ['zones', _, 'email', 'sending', 'subdomains', _, 'dns']):
        out = _ok(<Object>[]);
      case ('GET', ['accounts', _, 'billable-usage', 'info']):
        out = _ok({'available': true});
      case ('GET', ['accounts', final acc, 'billable-usage']):
        final start = DateTime.utc(_now.year, _now.month).toIso8601String();
        final box = _mailboxes[acc] ?? _mailboxes[_acc['id']]!;
        out = _ok([
          for (final (name, qty, unit, cost) in [
            ('Workers Paid', 1.0, 'subscription', 5.0),
            ('Workers Requests', _isEmber(acc) ? 38000.0 : 412000.0, 'requests', 0.0),
            ('Email Sending', box.sentInWindow.toDouble(), 'emails', 0.0),
            ('D1 Rows Read', 1830000.0, 'rows', 0.0),
            ('R2 Storage', 0.4, 'GB-month', 0.0),
          ])
            {
              'ServiceName': name,
              'ConsumedQuantity': qty,
              'ConsumedUnit': unit,
              'BilledCost': name == 'Workers Paid' ? 0.0 : cost,
              'BillingCurrency': 'USD',
              'BillingPeriodStart': start,
              'ChargePeriodStart': start,
              'ChargePeriodEnd': _now.toIso8601String(),
            },
        ]);
      case ('POST', ['graphql']):
        out = _graphql(body as Map<String, dynamic>);
      default:
        status = 404;
        out = {'success': false, 'errors': [{'code': 7003, 'message': 'Fake API has no route for $m $cf'}], 'messages': <Object>[], 'result': null};
    }
  } else if (path.startsWith('/v1/') && _mailboxFor(req).removed) {
    // What Cloudflare answers where a deleted Worker was: not the Worker's JSON.
    stdout.writeln('  → ${_mailboxFor(req).owner}: removed, 404');
    (status, out) = (404, _Binary(utf8.encode('There is nothing here yet'), 'text/plain'));
  } else {
    (status, out) = _mailApi(_mailboxFor(req), m, path, q, body, bytes);
  }

  req.response.statusCode = status;
  if (out is _Binary) {
    req.response.headers.contentType = ContentType.parse(out.type);
    req.response.add(out.bytes);
  } else {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(out));
  }
  await req.response.close();
}

Map<String, dynamic> _graphql(Map<String, dynamic> body) {
  final vars = (body['variables'] as Map?) ?? const {};
  final tags = <String>[
    ...((vars['tags'] ?? vars['zoneTags'] ?? const []) as List).map((e) => '$e'),
    if (vars['z'] != null) '${vars['z']}',
    if (vars['zoneTag'] != null) '${vars['zoneTag']}',
  ];
  final query = '${body['query']}';
  if (query.contains('emailSendingAdaptiveGroups')) {
    return {
      'data': {
        'viewer': {
          'zones': [
            {
              'emailSendingAdaptiveGroups': [
                {'count': 46, 'dimensions': {'date': _now.toIso8601String().substring(0, 10), 'status': 'delivered'}},
                {'count': 1, 'dimensions': {'date': _now.toIso8601String().substring(0, 10), 'status': 'deliveryFailed'}},
              ],
            },
          ],
        },
      },
      'errors': null,
    };
  }
  if (query.contains('emailSendingAdaptive')) {
    return {
      'data': {
        'viewer': {
          'zones': [
            {
              'emailSendingAdaptive': [
                for (var i = 0; i < 6; i++)
                  {
                    'datetime': _now.subtract(Duration(hours: i * 7)).toIso8601String(),
                    'from': 'contact@atelier-nord.dev',
                    'to': i == 3 ? 'old-address@gone.example' : 'client$i@clientco.example',
                    'subject': i == 3 ? 'Quote for the spring campaign' : 'Project update #${12 - i}',
                    'status': i == 3 ? 'deliveryFailed' : 'delivered',
                    'errorCause': i == 3 ? 'mailbox_unavailable' : null,
                    'errorDetail': i == 3 ? '550 5.1.1 User unknown' : null,
                    'spf': 'pass',
                    'dkim': 'pass',
                    'dmarc': 'pass',
                    'isSpam': false,
                  },
              ],
            },
          ],
        },
      },
      'errors': null,
    };
  }
  final hourly = query.contains('1hGroups');
  final points = hourly ? 24 : (query.contains('30') ? 30 : 7);
  List<Map<String, dynamic>> groups(String tag) => [
        for (var i = points - 1; i >= 0; i--)
          {
            'dimensions': hourly
                ? {'datetime': _now.subtract(Duration(hours: i)).toIso8601String()}
                : {'date': _now.subtract(Duration(days: i)).toIso8601String().substring(0, 10)},
            'sum': {
              'requests': 1200 * (tag.hashCode % 7 + 1) + i * 37,
              'bytes': 52000000 * (tag.hashCode % 5 + 1),
              'cachedRequests': 800 * (tag.hashCode % 7 + 1),
              'cachedBytes': 31000000 * (tag.hashCode % 5 + 1),
              'threats': i % 3,
              'pageViews': 400 + i * 11,
            },
            'uniq': {'uniques': 140 + i * 3},
          },
      ];
  return {
    'data': {
      'viewer': {
        'zones': [
          for (final t in (tags.isEmpty ? zones.map((z) => '${z['id']}') : tags))
            {'zoneTag': t, 'httpRequests1dGroups': hourly ? null : groups(t), 'httpRequests1hGroups': hourly ? groups(t) : null},
        ],
      },
    },
    'errors': null,
  };
}

/// A binary response body.
class _Binary {
  const _Binary(this.bytes, this.type);
  final List<int> bytes;
  final String type;
}

(int, Object?) _mailApi(_Mailbox box, String m, String path, Map<String, String> q, Object? body, List<int> bytes) {
  final mail = box.mail;
  final bodies = box.bodies;
  final seg = path.split('/').where((s) => s.isNotEmpty).toList();
  Map<String, dynamic> withBody(Map<String, dynamic> s) => {...s, ...bodies[s['id']]!};
  List<Map<String, dynamic>> listed(Iterable<Map<String, dynamic>> it) =>
      it.toList()..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
  switch ((m, seg)) {
    case ('GET', ['v1', 'health']):
      return (200, {'version': _bundleVersion, 'time': _now.toIso8601String(), 'domains': box.domains, 'sendingConfigured': true});
    case ('PUT', ['v1', 'config']):
      final limit = (body as Map)['monthlySendLimit'];
      if (limit is int) box.sendLimit = limit;
      return (200, body);
    case ('GET', ['v1', 'mailboxes']):
      final boxes = <String, Map<String, dynamic>>{};
      for (final x in mail) {
        final b = boxes.putIfAbsent(x['mailbox'] as String, () => {'address': x['mailbox'], 'domain': x['domain'], 'unread': 0, 'total': 0});
        b['total'] = (b['total'] as int) + 1;
        if (x['read'] != true && x['folder'] == 'inbox') b['unread'] = (b['unread'] as int) + 1;
      }
      return (200, {'mailboxes': boxes.values.toList()});
    case ('GET', ['v1', 'messages']):
      var it = mail.where((x) => x['folder'] == (q['folder'] ?? 'inbox'));
      if (q['mailbox'] != null) it = it.where((x) => x['mailbox'] == q['mailbox']);
      if (q['domain'] != null) it = it.where((x) => x['domain'] == q['domain']);
      if (q['q'] != null) {
        final s = q['q']!.toLowerCase();
        it = it.where((x) => '${x['subject']} ${x['snippet']} ${x['from']}'.toLowerCase().contains(s));
      }
      return (200, {'messages': listed(it), 'nextCursor': null});
    case ('GET', ['v1', 'threads', final t]):
      return (200, {'messages': listed(mail.where((x) => x['threadId'] == t)).reversed.toList()});
    case ('GET', ['v1', 'messages', final id]):
      return (200, withBody(mail.firstWhere((x) => x['id'] == id)));
    case ('PATCH', ['v1', 'messages', final id]):
      final x = mail.firstWhere((x) => x['id'] == id);
      (body as Map).forEach((k, v) => x[k] = v);
      x['seq'] = ++box.seq;
      return (200, x);
    case ('DELETE', ['v1', 'messages', final id]):
      final x = mail.firstWhere((x) => x['id'] == id);
      if (x['folder'] == 'trash') {
        mail.remove(x);
        return (200, {'result': 'purged'});
      }
      x['folder'] = 'trash';
      return (200, {'result': 'trashed'});
    case ('GET', ['v1', 'attachments', final id]):
      final stored = box.attachmentBytes[id];
      if (stored != null) return (200, _Binary(stored.bytes, stored.type));
      return (200, _Binary(_demoPdf, 'application/pdf'));
    case ('GET', ['v1', 'contacts']):
      // As the Worker: To and Cc of outgoing mail, most often then most recent.
      final byAddress = <String, Map<String, dynamic>>{};
      for (final x in listed(mail.where((x) => x['direction'] == 'out'))) {
        final seen = <String>{};
        for (final r in [...?(x['to'] as List?), ...?(x['cc'] as List?)].cast<Map>()) {
          final address = '${r['address']}'.toLowerCase();
          final name = r['name'] is String && (r['name'] as String).trim().isNotEmpty ? (r['name'] as String).trim() : null;
          final c = byAddress.putIfAbsent(address, () => {'address': address, 'name': name, 'count': 0, 'lastSent': x['date']});
          if (seen.add(address)) c['count'] = (c['count'] as int) + 1;
          c['name'] ??= name;
        }
      }
      final contacts = byAddress.values.toList()
        ..sort((a, b) => (b['count'] as int) != (a['count'] as int)
            ? (b['count'] as int).compareTo(a['count'] as int)
            : '${b['lastSent']}'.compareTo('${a['lastSent']}'));
      return (200, {'contacts': contacts});
    case ('GET', ['v1', 'brands']):
      return (200, {'brands': [for (final d in box.domains) box.brandJson(d)]});
    case ('PUT', ['v1', 'brands', final domain]):
      final prev = box.brands[domain];
      box.brands[domain] = (
        signature: '${(body as Map)['signature']}'.trim(),
        logo: prev?.logo,
        width: prev?.width ?? 0,
        height: prev?.height ?? 0,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      return (200, box.brandJson(domain));
    case ('PUT', ['v1', 'brands', final domain, 'logo']):
      // Width and height from the PNG's IHDR chunk.
      int be(int at) => (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
      if (bytes.length < 24 || bytes[1] != 0x50) return (400, {'error': {'code': 'invalid_logo', 'message': 'The logo must be a PNG image'}});
      box.brands[domain] = (
        signature: box.brands[domain]?.signature ?? '',
        logo: bytes,
        width: be(16),
        height: be(20),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      return (200, box.brandJson(domain));
    case ('GET', ['v1', 'brands', final domain, 'logo']):
      final logo = box.brands[domain]?.logo;
      return logo == null ? (404, {'error': {'code': 'not_found', 'message': 'No logo'}}) : (200, _Binary(logo, 'image/png'));
    case ('DELETE', ['v1', 'brands', final domain, 'logo']):
      final prev = box.brands[domain];
      if (prev != null) {
        box.brands[domain] = (signature: prev.signature, logo: null, width: 0, height: 0, updatedAt: DateTime.now().toUtc().toIso8601String());
      }
      return (200, box.brandJson(domain));
    case ('GET', ['v1', 'sync']):
      final since = int.tryParse(q['since'] ?? '') ?? box.seq;
      return (200, {
        'messages': mail.where((x) => (x['seq'] as int) > since).toList(),
        'deleted': <String>[],
        'cursor': '${box.seq}',
        'sendUsage': {'used': box.sentInWindow, 'limit': box.sendLimit, 'resetsAt': _now.add(const Duration(days: 9)).toIso8601String()},
        'unread': {'total': mail.where((x) => x['read'] != true && x['folder'] == 'inbox').length},
      });
    case ('GET', ['v1', 'config']):
      return (200, {'monthlySendLimit': box.sendLimit});
    case ('POST', ['_demo', 'remove-mail']):
      final gone = _mailboxes[q['account'] == 'ember' ? _ember['id'] : _acc['id']]!
        ..removed = true
        ..mail.clear()
        ..bodies.clear()
        ..brands.clear()
        ..attachmentBytes.clear();
      return (200, {'removed': gone.owner});
    case ('POST', ['_demo', 'arrive']):
      // Simulates a message landing (for live refresh and badge checks);
      // `?account=ember` lands it in Studio Ember's mailbox.
      final ember = q['account'] == 'ember';
      final to = ember ? _mailboxes[_ember['id']]! : _mailboxes[_acc['id']]!;
      final n = ++to.arrivals;
      if (ember) {
        to.add('elive$n', 'elive$n', 'jun@kiln-collective.example', 'Jun Park', 'hello@studio-ember.com', 'Stocking your mugs in our shop',
            'Hello Studio Ember,\n\nWe would love to stock the speckled mugs. Could you share wholesale prices?\n\nJun');
      } else {
        to.add('live$n', 'live$n', 'nadia@northwind.example', 'Nadia Petrova', 'contact@atelier-nord.dev', 'Quick question about the quote',
            'Hi! Does the quote include hosting for the first year?\n\nNadia');
      }
      return (200, {'ok': true});
    case ('POST', ['v1', 'send']):
      final b = body as Map<String, dynamic>;
      final cid = b['clientMessageId'] as String?;
      if (cid != null && box.sentByClientId.containsKey(cid)) {
        return (200, {...box.sentByClientId[cid]!, 'duplicate': true});
      }
      final recipients = [...?(b['to'] as List?), ...?(b['cc'] as List?), ...?(b['bcc'] as List?)].length;
      if (box.sendLimit > 0 && box.sentInWindow + recipients > box.sendLimit) {
        return (429, {'error': {'code': 'monthly_send_limit', 'message': 'Sending limit reached', 'used': box.sentInWindow, 'limit': box.sendLimit}});
      }
      // Sent files keep their own bytes, so opening one from Sent shows it.
      final atts = <Map<String, dynamic>>[];
      for (final (i, a) in (b['attachments'] as List? ?? const []).cast<Map<String, dynamic>>().indexed) {
        final attId = 'att${box.seq + 1}-$i';
        final bytes = base64Decode('${a['contentBase64']}');
        box.attachmentBytes[attId] = (bytes: bytes, type: '${a['mimeType']}');
        atts.add({'id': attId, 'filename': a['filename'], 'mimeType': a['mimeType'], 'size': bytes.length, 'contentId': null, 'inline': false});
      }
      // The sender domain's logo, inline, as the real Worker does.
      if (b['brandLogo'] == true) {
        final logo = box.brands['${(b['from'] as Map)['address']}'.split('@').last]?.logo;
        if (logo == null) return (400, {'error': {'code': 'brand_logo_missing', 'message': "The sender's domain has no logo"}});
        final attId = 'att${box.seq + 1}-logo';
        box.attachmentBytes[attId] = (bytes: logo, type: 'image/png');
        atts.add({'id': attId, 'filename': 'logo.png', 'mimeType': 'image/png', 'size': logo.length, 'contentId': 'logo@edgepost', 'inline': true});
      }
      final parent = b['inReplyTo'] == null ? null : mail.firstWhere((x) => x['id'] == b['inReplyTo']);
      final id = 's${++box.seq}';
      final sent = {
        'id': id,
        'threadId': parent?['threadId'] ?? id,
        'folder': 'sent',
        'direction': 'out',
        'mailbox': (b['from'] as Map)['address'],
        'domain': '${(b['from'] as Map)['address']}'.split('@').last,
        'from': b['from'],
        'to': b['to'],
        'cc': b['cc'] ?? [],
        'replyTo': <Object>[],
        'subject': b['subject'],
        'snippet': _snippet('${b['text']}'),
        'date': DateTime.now().toUtc().toIso8601String(),
        'inReplyTo': parent == null ? null : '<${parent['id']}@demo.invalid>',
        'read': true,
        'starred': false,
        'hasAttachments': (b['attachments'] as List? ?? const []).isNotEmpty,
        'size': '${b['text']}'.length,
        'seq': box.seq,
      };
      mail.add(sent);
      bodies[id] = {'text': b['text'], 'html': b['html'], 'attachments': atts};
      box.sentInWindow += recipients;
      final result = {'message': sent, 'providerMessageId': '<$id@demo.invalid>'};
      if (cid != null) box.sentByClientId[cid] = result;
      return (200, result);
    default:
      return (404, {'error': {'code': 'not_found', 'message': 'Fake mail Worker has no route for $m $path'}});
  }
}
