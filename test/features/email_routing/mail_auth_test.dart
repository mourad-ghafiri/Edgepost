import 'package:edgepost/features/email_routing/data/email_routing_models.dart';
import 'package:edgepost/features/email_routing/data/mail_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

const zone = 'example.com';

AuthDnsRecord txt(String name, String content) => AuthDnsRecord(type: 'TXT', name: name, content: content);
AuthDnsRecord mx(String content, [int priority = 10]) =>
    AuthDnsRecord(type: 'MX', name: zone, content: content, priority: priority);

MailAuthHealth eval(
  List<AuthDnsRecord> records, {
  bool routing = true,
  SpfInspection? spf,
  String? dmarcStatus,
  bool emailAuth = false,
  List<RoutingDnsRecord> required = const [],
}) =>
    evaluateMailAuth(
      MailAuthInputs(records: records, spfInspection: spf, dmarcReportStatus: dmarcStatus, emailAuthAvailable: emailAuth),
      zoneName: zone,
      routingEnabled: routing,
      requiredRecords: required,
    );

void main() {
  group('SPF', () {
    test('one record with the Cloudflare include passes', () {
      final h = eval([txt(zone, '"v=spf1 include:_spf.mx.cloudflare.net ~all"')]);
      expect(h.spf.state, AuthState.ok);
      expect(h.spf.current, 'v=spf1 include:_spf.mx.cloudflare.net ~all');
    });

    test('missing: suggests Cloudflare record from the routing DNS list', () {
      final h = eval([], required: const [
        RoutingDnsRecord(type: 'TXT', name: zone, content: 'v=spf1 include:_spf.mx.cloudflare.net ~all'),
      ]);
      expect(h.spf.state, AuthState.missing);
      expect(h.spf.finding, AuthFinding.spfMissing);
      expect(h.spf.suggestion, 'v=spf1 include:_spf.mx.cloudflare.net ~all');
    });

    test('missing while routing is off: no suggestion', () {
      final h = eval([], routing: false);
      expect(h.spf.state, AuthState.missing);
      expect(h.spf.suggestion, isNull);
    });

    test('multiple SPF records are an error with a merged suggestion', () {
      final h = eval([
        txt(zone, 'v=spf1 include:_spf.google.com ~all'),
        txt(zone, 'v=spf1 include:_spf.mx.cloudflare.net -all'),
        txt('other.example.com', 'v=spf1 -all'),
      ]);
      expect(h.spf.state, AuthState.attention);
      expect(h.spf.finding, AuthFinding.spfMultiple);
      expect(h.spf.suggestion, 'v=spf1 include:_spf.google.com include:_spf.mx.cloudflare.net ~all');
    });

    test('routing on but no Cloudflare include: suggests the include before all', () {
      final h = eval([txt(zone, 'v=spf1 include:_spf.google.com ~all')]);
      expect(h.spf.finding, AuthFinding.spfNoCloudflare);
      expect(h.spf.suggestion, 'v=spf1 include:_spf.google.com include:_spf.mx.cloudflare.net ~all');
    });

    test('+all is flagged', () {
      final h = eval([txt(zone, 'v=spf1 include:_spf.mx.cloudflare.net +all')]);
      expect(h.spf.finding, AuthFinding.spfPassAll);
      expect(h.spf.suggestion, 'v=spf1 include:_spf.mx.cloudflare.net ~all');
    });

    test('more than 10 lookups from spf/inspect is a hard failure', () {
      final h = eval(
        [txt(zone, 'v=spf1 include:_spf.mx.cloudflare.net ~all')],
        spf: const SpfInspection(totalLookups: 12),
      );
      expect(h.spf.state, AuthState.attention);
      expect(h.spf.finding, AuthFinding.spfTooManyLookups);
      expect(h.spf.lookups, 12);
      final viaError = eval(
        [txt(zone, 'v=spf1 include:_spf.mx.cloudflare.net ~all')],
        spf: SpfInspection.fromJson({
          'total_lookups': 4,
          'errors': [
            {'code': 'max_lookups', 'domain': zone, 'message': 'too many'},
          ],
        }),
      );
      expect(viaError.spf.finding, AuthFinding.spfTooManyLookups);
    });

    test('lookup count is reported when healthy', () {
      final h = eval([txt(zone, 'v=spf1 include:_spf.mx.cloudflare.net ~all')], spf: const SpfInspection(totalLookups: 3));
      expect(h.spf.state, AuthState.ok);
      expect(h.spf.lookups, 3);
    });

    test('split TXT strings are joined', () {
      expect(normalizeTxt('"v=spf1 include:_spf.mx." "cloudflare.net ~all"'), 'v=spf1 include:_spf.mx.cloudflare.net ~all');
      expect(normalizeTxt('v=DMARC1; p=none'), 'v=DMARC1; p=none');
    });
  });

  group('DKIM', () {
    test('cf2024-1 selector present', () {
      final h = eval([txt('cf2024-1._domainkey.example.com', 'v=DKIM1; h=sha256; k=rsa; p=MIIB')]);
      expect(h.dkim.state, AuthState.ok);
    });

    test('missing while routing is on needs attention and offers the record', () {
      final h = eval([], required: const [
        RoutingDnsRecord(type: 'TXT', name: 'cf2024-1._domainkey.example.com', content: 'v=DKIM1; p=KEY'),
      ]);
      expect(h.dkim.state, AuthState.attention);
      expect(h.dkim.finding, AuthFinding.dkimMissing);
      expect(h.dkim.suggestion, 'v=DKIM1; p=KEY');
    });

    test('routing off with another provider key is fine', () {
      final h = eval([txt('google._domainkey.example.com', 'v=DKIM1; p=X')], routing: false);
      expect(h.dkim.state, AuthState.ok);
      expect(h.dkim.finding, AuthFinding.dkimOtherSelectors);
      expect(h.dkim.detail, 'google');
    });
  });

  group('DMARC', () {
    test('p=reject passes; p=quarantine passes', () {
      expect(eval([txt('_dmarc.example.com', 'v=DMARC1; p=reject; rua=mailto:a@example.com')]).dmarc.state, AuthState.ok);
      expect(eval([txt('_dmarc.example.com', 'v=DMARC1; p=quarantine')]).dmarc.finding, AuthFinding.dmarcOk);
    });

    test('p=none needs attention and suggests quarantine', () {
      final h = eval([txt('_dmarc.example.com', 'v=DMARC1; p=none; rua=mailto:a@example.com')]);
      expect(h.dmarc.finding, AuthFinding.dmarcPolicyNone);
      expect(h.dmarc.suggestion, 'v=DMARC1; p=quarantine; rua=mailto:a@example.com');
    });

    test('missing suggests a starter policy', () {
      final h = eval([]);
      expect(h.dmarc.state, AuthState.missing);
      expect(h.dmarc.suggestion, 'v=DMARC1; p=none');
    });

    test('two records, or no policy, need attention', () {
      expect(eval([txt('_dmarc.example.com', 'v=DMARC1; p=reject'), txt('_dmarc.example.com', 'v=DMARC1; p=none')]).dmarc.finding,
          AuthFinding.dmarcMultiple);
      expect(eval([txt('_dmarc.example.com', 'v=DMARC1; rua=mailto:a@b.c')]).dmarc.finding, AuthFinding.dmarcInvalid);
    });

    test('report status: missing-dmarc-rua is informational, others need attention', () {
      final noRua = eval([txt('_dmarc.example.com', 'v=DMARC1; p=reject')], emailAuth: true, dmarcStatus: 'missing-dmarc-rua');
      expect(noRua.dmarc.state, AuthState.ok);
      expect(noRua.dmarc.finding, AuthFinding.dmarcOkNoReports);
      final cname = eval([txt('_dmarc.example.com', 'v=DMARC1; p=reject')], emailAuth: true, dmarcStatus: 'cname-on-dmarc-record');
      expect(cname.dmarc.finding, AuthFinding.dmarcReportIssue);
    });

    test('no TXT but reports API says healthy: published through a CNAME', () {
      final h = eval([], emailAuth: true);
      expect(h.dmarc.finding, AuthFinding.dmarcViaCname);
    });
  });

  test('foreign MX hosts are listed while routing is on', () {
    final h = eval([mx('route1.mx.cloudflare.net'), mx('aspmx.l.google.com.', 1)]);
    expect(h.foreignMx, ['aspmx.l.google.com.']);
    expect(eval([mx('aspmx.l.google.com')], routing: false).foreignMx, isEmpty);
  });

  test('without DNS access every check is unknown', () {
    final h = evaluateMailAuth(const MailAuthInputs(dnsAvailable: false), zoneName: zone, routingEnabled: true);
    expect([h.spf.state, h.dkim.state, h.dmarc.state], everyElement(AuthState.unknown));
  });

  group('fetchMailAuthInputs', () {
    test('reads TXT + MX and email auth endpoints', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/zones/z/dns_records', (c) => FakeReply.ok(
              c.query['type'] == 'TXT'
                  ? [
                      {'type': 'TXT', 'name': zone, 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all'},
                    ]
                  : [
                      {'type': 'MX', 'name': zone, 'content': 'route1.mx.cloudflare.net', 'priority': 12},
                    ],
              resultInfo: {'page': 1, 'total_pages': 1},
            ))
        ..reply('GET', '/zones/z/email/auth/dmarc-reports', {'enabled': true, 'status': 'missing-dmarc-rua'})
        ..reply('GET', '/zones/z/email/auth/spf/inspect', {'domain': zone, 'record': 'v=spf1', 'total_lookups': 2, 'components': <Object>[]});
      final inputs = await fetchMailAuthInputs(fakeClient(api), 'z', canDns: true, canEmailAuth: true);
      expect(inputs.records.map((r) => r.type), ['TXT', 'MX']);
      expect(inputs.dmarcReportStatus, 'missing-dmarc-rua');
      expect(inputs.spfInspection!.totalLookups, 2);
      expect(inputs.emailAuthAvailable, isTrue);
      expect(api.calls.where((c) => c.path.endsWith('dns_records')).map((c) => c.query['type']), ['TXT', 'MX']);
    });

    test('degrades without DMARC Management or DNS permission', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/zones/z/dns_records', (_) => FakeReply.error(403, 10000, 'Authentication error'));
      final noDns = await fetchMailAuthInputs(fakeClient(api), 'z', canDns: true, canEmailAuth: false);
      expect(noDns.dnsAvailable, isFalse);
      expect(api.calls.any((c) => c.path.contains('/email/auth/')), isFalse);

      final skipped = await fetchMailAuthInputs(fakeClient(FakeCfAdapter()), 'z', canDns: false, canEmailAuth: false);
      expect(skipped.dnsAvailable, isFalse);
      expect(skipped.emailAuthAvailable, isFalse);
    });
  });
}
