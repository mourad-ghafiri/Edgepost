import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/features/mail/data/mail_dns_check.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

final _zone = Zone.fromJson({
  'id': 'z1',
  'name': 'example.com',
  'status': 'active',
  'paused': false,
  'account': {'id': 'a1', 'name': 'Personal'},
}, reach: const ['c1']);

void main() {
  test('flags a second DMARC record and duplicate SPF at the same name', () async {
    final api = FakeCfAdapter()
      ..reply('GET', '/zones/z1/dns_records', [
        {'id': 'd1', 'type': 'TXT', 'name': '_dmarc.example.com', 'content': '"v=DMARC1; p=quarantine"', 'created_on': '2025-01-01T00:00:00Z'},
        {'id': 'd2', 'type': 'TXT', 'name': '_dmarc.example.com', 'content': '"v=DMARC1; p=none"', 'created_on': '2026-10-12T10:00:00Z'},
        {'id': 's1', 'type': 'TXT', 'name': 'example.com', 'content': '"v=spf1 include:_spf.mx.cloudflare.net ~all"'},
        {'id': 's2', 'type': 'TXT', 'name': 'cf-bounce.example.com', 'content': '"v=spf1 include:_spf.mx.cloudflare.net ~all"'},
        {'id': 's3', 'type': 'TXT', 'name': 'cf-bounce.example.com', 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all'},
        {'id': 'v1', 'type': 'TXT', 'name': 'example.com', 'content': 'google-site-verification=abc'},
      ], resultInfo: {'page': 1, 'total_pages': 1});
    final issues = await checkMailDns(fakeClient(api), _zone);
    expect(issues.map((i) => i.kind), [MailDnsIssueKind.duplicateDmarc, MailDnsIssueKind.duplicateSpf]);
    expect(issues.first.records.map((r) => r['id']), ['d1', 'd2']);
    expect(issues.last.name, 'cf-bounce.example.com');
    expect(api.calls.single.query['type'], 'TXT');
  });

  test('a clean zone has no issues', () async {
    final api = FakeCfAdapter()
      ..reply('GET', '/zones/z1/dns_records', [
        {'id': 'd1', 'type': 'TXT', 'name': '_dmarc.example.com', 'content': 'v=DMARC1; p=none'},
        {'id': 's1', 'type': 'TXT', 'name': 'example.com', 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all'},
      ], resultInfo: {'page': 1, 'total_pages': 1});
    expect(await checkMailDns(fakeClient(api), _zone), isEmpty);
  });
}
