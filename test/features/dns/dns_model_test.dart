import 'package:edgepost/features/dns/data/dns_draft.dart';
import 'package:edgepost/features/dns/data/dns_record.dart';
import 'package:edgepost/features/dns/data/mail_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dns_fixtures.dart';

void main() {
  group('DnsRecord', () {
    test('parses an official-example-shaped A record', () {
      final r = DnsRecord.fromJson(aRecordJson());
      expect(r.id, '023e105f4ecef8ad9ca31a8372d0c353');
      expect(r.type, 'A');
      expect(r.name, 'example.com');
      expect(r.content, '198.51.100.4');
      expect(r.proxied, isTrue);
      expect(r.proxiable, isTrue);
      expect(r.ttl, DnsTypes.autoTtl);
      expect(r.comment, 'Domain verification record');
      expect(r.tags, ['owner:dns-team']);
      expect(r.createdOn, DateTime.utc(2014, 1, 1, 5, 20, 0, 123, 450));
      expect(r.modifiedOn, isNotNull);
      expect(r.priority, isNull);
      expect(r.data, isNull);
    });

    test('parses MX priority and SRV data', () {
      final mx = DnsRecord.fromJson(mxJson());
      expect(mx.priority, 10);
      expect(mx.ttl, 3600);
      expect(mx.canProxy, isFalse);
      final srv = DnsRecord.fromJson(srvJson());
      expect(srv.data, {'priority': 10, 'weight': 5, 'port': 5060, 'target': 'sip.example.com'});
    });

    test('null comment and empty tags are tolerated', () {
      final r = DnsRecord.fromJson(cnameJson());
      expect(r.comment, isNull);
      expect(r.tags, isEmpty);
      expect(r.settings, {'flatten_cname': false});
    });

    test('toJson round-trips through the cache', () {
      final r = DnsRecord.fromJson(srvJson());
      final back = DnsRecord.fromJson(r.toJson());
      expect(back.id, r.id);
      expect(back.data, r.data);
      expect(back.priority, r.priority);
      expect(back.createdOn, r.createdOn);
    });

    test('re-create body keeps type, name, value, TTL, proxy, comment, tags', () {
      final body = DnsRecord.fromJson(aRecordJson()).toCreateBody();
      expect(body, {
        'type': 'A',
        'name': 'example.com',
        'content': '198.51.100.4',
        'ttl': 1,
        'proxied': true,
        'comment': 'Domain verification record',
        'tags': ['owner:dns-team'],
      });
    });

    test('re-create body sends structured data instead of content', () {
      final body = DnsRecord.fromJson(srvJson()).toCreateBody();
      expect(body.containsKey('content'), isFalse);
      expect(body['data'], {'priority': 10, 'weight': 5, 'port': 5060, 'target': 'sip.example.com'});
      expect(body.containsKey('priority'), isFalse, reason: 'top-level priority is only for MX and URI');
      expect(body.containsKey('proxied'), isFalse);
    });

    test('import result reads recs_added and total_records_parsed', () {
      final r = DnsImportResult.fromJson({'recs_added': 5, 'total_records_parsed': 7});
      expect((r.added, r.parsed), (5, 7));
    });
  });

  group('DnsNames', () {
    test('relative and absolute names', () {
      expect(DnsNames.relative('example.com', 'example.com'), '@');
      expect(DnsNames.relative('www.example.com', 'example.com'), 'www');
      expect(DnsNames.relative('WWW.Example.com.', 'example.com'), 'www');
      expect(DnsNames.absolute('@', 'example.com'), 'example.com');
      expect(DnsNames.absolute('', 'example.com'), 'example.com');
      expect(DnsNames.absolute('www', 'example.com'), 'www.example.com');
      expect(DnsNames.absolute('www.example.com', 'example.com'), 'www.example.com');
      expect(DnsNames.target('@', 'example.com'), 'example.com');
      expect(DnsNames.target('mail.example.net.', 'example.com'), 'mail.example.net');
    });

    test('txtValue joins quoted strings', () {
      expect(txtValue('"v=spf1 " "-all"'), 'v=spf1 -all');
      expect(txtValue('v=spf1 -all'), 'v=spf1 -all');
      expect(txtValue(r'"a \"quoted\" word"'), 'a "quoted" word');
    });
  });

  group('validators', () {
    test('IPv4', () {
      for (final ok in ['203.0.113.10', '0.0.0.0', '255.255.255.255', ' 198.51.100.4 ']) {
        expect(DnsValidators.isIPv4(ok), isTrue, reason: ok);
      }
      for (final bad in ['256.1.1.1', '1.2.3', '1.2.3.4.5', '01.2.3.4', 'a.b.c.d', '', '2001:db8::1']) {
        expect(DnsValidators.isIPv4(bad), isFalse, reason: bad);
      }
    });

    test('IPv6', () {
      for (final ok in ['2001:db8::1', '::1', '2001:0db8:0000:0000:0000:ff00:0042:8329', '::ffff:192.0.2.128']) {
        expect(DnsValidators.isIPv6(ok), isTrue, reason: ok);
      }
      for (final bad in ['203.0.113.10', '2001:db8::g', '1:2:3:4:5:6:7:8:9', 'fe80::1%en0', '[::1]', '']) {
        expect(DnsValidators.isIPv6(bad), isFalse, reason: bad);
      }
    });

    test('hostnames', () {
      for (final ok in ['example.com', 'mail.example.com.', '_dmarc.example.com', 'xn--bcher-kva.example', 'a-b.c']) {
        expect(DnsValidators.isHostname(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '-bad.com',
        'bad-.com',
        'two..dots',
        'bücher.example',
        'space here.com',
        '',
        '${'a' * 64}.com',
      ]) {
        expect(DnsValidators.isHostname(bad), isFalse, reason: bad);
      }
      expect(DnsValidators.isRecordName('@'), isTrue);
      expect(DnsValidators.isRecordName('*.dev'), isTrue);
      expect(DnsValidators.isRecordName('dev.*'), isFalse);
    });

    test('MX priority range', () {
      expect(DnsValidators.uint16('0'), 0);
      expect(DnsValidators.uint16('65535'), 65535);
      expect(DnsValidators.uint16('65536'), isNull);
      expect(DnsValidators.uint16('-1'), isNull);
      expect(DnsValidators.uint16('ten'), isNull);
      final mx = DnsDraft(type: 'MX')
        ..name = '@'
        ..content = 'mx1.example.net'
        ..priority = '70000';
      expect(mx.validate('example.com'), {DnsField.priority: DnsFieldError.range});
      mx.priority = '10';
      expect(mx.isValid('example.com'), isTrue);
    });

    test('TXT quotes must pair up', () {
      expect(DnsValidators.balancedQuotes('"a" "b"'), isTrue);
      expect(DnsValidators.balancedQuotes('say "hi'), isFalse);
      final txt = DnsDraft(type: 'TXT')
        ..name = '@'
        ..content = 'say "hi';
      expect(txt.validate('example.com')[DnsField.content], DnsFieldError.quotes);
    });
  });

  group('DnsDraft', () {
    test('A record body', () {
      final d = DnsDraft(type: 'A')
        ..name = 'www'
        ..content = '203.0.113.10'
        ..proxied = true
        ..ttl = 3600;
      expect(d.toBody('example.com'), {
        'type': 'A',
        'name': 'www.example.com',
        'content': '203.0.113.10',
        'ttl': 1, // proxied forces Auto
        'proxied': true,
      });
    });

    test('SRV body puts service and protocol in the name and values in data', () {
      final d = DnsDraft(type: 'SRV')
        ..service = 'sip'
        ..proto = '_udp'
        ..name = '@'
        ..priority = '10'
        ..weight = '5'
        ..port = '5060'
        ..target = 'sip.example.com';
      expect(d.isValid('example.com'), isTrue);
      expect(d.toBody('example.com'), {
        'type': 'SRV',
        'name': '_sip._udp.example.com',
        'data': {'priority': 10, 'weight': 5, 'port': 5060, 'target': 'sip.example.com'},
        'ttl': 1,
      });
    });

    test('SRV and CAA records load back into the form', () {
      final srv = DnsDraft.fromRecord(DnsRecord.fromJson(srvJson()), 'example.com');
      expect(
        (srv.service, srv.proto, srv.name, srv.port, srv.target),
        ('_sip', '_tcp', '@', '5060', 'sip.example.com'),
      );
      final caa = DnsDraft.fromRecord(DnsRecord.fromJson(caaJson()), 'example.com');
      expect((caa.flags, caa.tag, caa.value), ('0', 'issue', 'letsencrypt.org'));
      expect(caa.toBody('example.com')['data'], {'flags': 0, 'tag': 'issue', 'value': 'letsencrypt.org'});
    });

    test('an emptied comment is cleared on edit', () {
      final d = DnsDraft.fromRecord(DnsRecord.fromJson(aRecordJson()), 'example.com')..comment = '';
      expect(d.toBody('example.com', clearComment: true)['comment'], '');
      expect(d.toBody('example.com').containsKey('comment'), isFalse);
    });

    test('raw form validates the type', () {
      final d = DnsDraft(type: 'tlsa?', other: true)
        ..name = '_443._tcp'
        ..content = '3 1 1 abcd';
      expect(d.validate('example.com')[DnsField.type], DnsFieldError.type);
      d.type = 'TLSA';
      expect(d.isValid('example.com'), isTrue);
    });
  });

  group('mail check', () {
    test('reports Email Routing MX, SPF, missing DMARC and DKIM', () {
      final records = [mxJson(), txtJson()].map(DnsRecord.fromJson).toList();
      final items = checkMailRecords(records, 'example.com');
      expect(items.map((i) => i.finding), [
        MailCheckFinding.mxEmailRouting,
        MailCheckFinding.spfOk,
        MailCheckFinding.dmarcMissing,
        MailCheckFinding.dkimMissing,
      ]);
    });

    test('flags duplicate SPF, p=none and finds DKIM keys', () {
      final records = [
        txtJson(id: 's1', content: 'v=spf1 -all'),
        txtJson(id: 's2', content: 'v=spf1 include:example.net ~all'),
        txtJson(id: 'd1', name: '_dmarc.example.com', content: '"v=DMARC1; p=none; rua=mailto:dmarc@example.com"'),
        txtJson(id: 'k1', name: 'cf2024-1._domainkey.example.com', content: 'v=DKIM1; k=rsa; p=MIGf'),
      ].map(DnsRecord.fromJson).toList();
      final items = checkMailRecords(records, 'example.com');
      expect(items[0].status, MailCheckStatus.missing);
      expect(items[1].finding, MailCheckFinding.spfMultiple);
      expect(items[2].finding, MailCheckFinding.dmarcMonitorOnly);
      expect(items[3].finding, MailCheckFinding.dkimOk);
      expect(items[3].records.single.id, 'k1');
    });

    test('+all is a pass-everything SPF', () {
      final items = checkMailRecords([DnsRecord.fromJson(txtJson(content: 'v=spf1 +all'))], 'example.com');
      expect(items[1].finding, MailCheckFinding.spfPassAll);
    });
  });
}
