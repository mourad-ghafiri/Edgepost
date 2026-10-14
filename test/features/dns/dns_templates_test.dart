import 'package:edgepost/core/adaptive/ep_icons.dart';
import 'package:edgepost/features/dns/presentation/dns_editor_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'dns_fixtures.dart';
import 'dns_widget_harness.dart';

const _base = '/zones/z1/dns_records';

/// Section headers render uppercase on iOS (grouped-list style); match either case.
Finder _header(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.data?.toLowerCase() == text.toLowerCase());

void main() {
  testBothPlatforms('Point to an IP replaces apex and www address records in one batch', (tester, platform) async {
    final api = FakeCfAdapter()
      ..reply('GET', _base, [aRecordJson(), cnameJson(), mxJson()], resultInfo: onePage(3))
      ..on('POST', '$_base/batch', (call) {
        final posts = ((call.body as Map)['posts'] as List).cast<Map<String, dynamic>>();
        return FakeReply.ok({
          'deletes': [aRecordJson(), cnameJson()],
          'posts': [
            for (var i = 0; i < posts.length; i++) {...posts[i], 'id': 'p$i', 'proxiable': true},
          ],
        });
      });
    await pumpDns(tester, api: api, location: '/domains/z1/dns/template/point');
    expect(find.text('Point to an IP'), findsWidgets);
    final save = toolbarButton(platform, EpIcon.check);
    expect(isEnabled(tester, save), isFalse);

    await tester.enterText(fieldInput('Server IP address'), '203.0.113.10');
    await tester.pumpAndSettle();
    expect(_header('Creates'), findsOneWidget);
    expect(_header('Replaces'), findsOneWidget);
    expect(isEnabled(tester, save), isTrue);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Replace 2 records?'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await settle(tester);

    final batch = api.calls.lastWhere((c) => c.path == '$_base/batch');
    expect(batch.body, {
      'deletes': [
        {'id': '023e105f4ecef8ad9ca31a8372d0c353'},
        {'id': 'rec-www'},
      ],
      'posts': [
        {'type': 'A', 'name': 'example.com', 'content': '203.0.113.10', 'ttl': 1, 'proxied': true},
        {'type': 'CNAME', 'name': 'www.example.com', 'content': 'example.com', 'ttl': 1, 'proxied': true},
      ],
    });
    await drainToasts(tester);
  });

  testBothPlatforms('Verification TXT creates one TXT record', (tester, platform) async {
    final api = FakeCfAdapter()
      ..reply('GET', _base, [mxJson()], resultInfo: onePage(1))
      ..on('POST', _base, (call) => FakeReply.ok({...(call.body as Map<String, dynamic>), 'id': 'txt1'}));
    await pumpDns(tester, api: api, location: '/domains/z1/dns/template/verify');
    await tester.enterText(fieldInput('Value'), 'google-site-verification=abc123');
    await tester.pumpAndSettle();
    await tester.tap(toolbarButton(platform, EpIcon.check));
    await settle(tester);
    expect(api.calls.lastWhere((c) => c.method == 'POST').body, {
      'type': 'TXT',
      'name': 'example.com',
      'content': 'google-site-verification=abc123',
      'ttl': 1,
    });
    await drainToasts(tester);
  });

  testBothPlatforms('mail check reports each record family and offers a DMARC start', (tester, platform) async {
    final api = FakeCfAdapter()..reply('GET', _base, [mxJson(), txtJson()], resultInfo: onePage(2));
    await pumpDns(tester, api: api, location: '/domains/z1/dns/mail-check');
    expect(_header('Receiving (MX)'), findsOneWidget);
    expect(find.text('Cloudflare Email Routing receives mail for example.com.'), findsOneWidget);
    expect(_header('Allowed senders (SPF)'), findsOneWidget);
    expect(find.text('Present'), findsNWidgets(2));
    expect(find.text('Missing'), findsWidgets, reason: 'DMARC (and DKIM below the fold)');

    final addDmarc = find.text('Add a monitoring DMARC record');
    await tester.ensureVisible(addDmarc);
    await tester.pumpAndSettle();
    await tester.tap(addDmarc);
    await settle(tester);
    expect(find.byType(DnsEditorScreen), findsOneWidget);
    expect(fieldText(tester, 'Name'), '_dmarc');
    expect(fieldText(tester, 'Content'), 'v=DMARC1; p=none');
  });
}
