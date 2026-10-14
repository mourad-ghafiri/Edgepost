import 'package:edgepost/core/adaptive/ep_icons.dart';
import 'package:edgepost/features/dns/presentation/dns_editor_screen.dart';
import 'package:edgepost/features/dns/presentation/dns_list_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'dns_fixtures.dart';
import 'dns_widget_harness.dart';

const _base = '/zones/z1/dns_records';

FakeCfAdapter _api() =>
    FakeCfAdapter()..reply('GET', _base, [aRecordJson(), cnameJson(), mxJson(), txtJson()], resultInfo: onePage(4));

void main() {
  group('DNS list', () {
    testBothPlatforms('groups records by type with proxy, TTL and priority labels', (tester, platform) async {
      await pumpDns(tester, api: _api(), location: '/domains/z1/dns');
      expect(find.byType(DnsListScreen), findsOneWidget);
      expect(find.text('DNS records'), findsWidgets);
      for (final header in ['A · 1', 'CNAME · 1', 'MX · 1', 'TXT · 1']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(find.text('www'), findsOneWidget);
      expect(find.text('@'), findsNWidgets(3), reason: 'apex shown as @');
      expect(find.text('198.51.100.4'), findsOneWidget);
      expect(find.text('Proxied'), findsOneWidget);
      expect(find.text('DNS only'), findsOneWidget);
      expect(find.text('Priority 10'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('1 h'), findsOneWidget);
      expect(addButton(platform), findsOneWidget);
    });

    testBothPlatforms('search and type filter narrow the list', (tester, platform) async {
      await pumpDns(tester, api: _api(), location: '/domains/z1/dns');
      final field = platform == TargetPlatform.iOS ? find.byType(CupertinoSearchTextField) : find.byType(SearchBar);
      await tester.enterText(field, 'spf');
      await tester.pumpAndSettle();
      expect(find.text('TXT · 1'), findsOneWidget);
      expect(find.text('A · 1'), findsNothing);

      await tester.enterText(field, 'nothing-like-this');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches “nothing-like-this”.'), findsOneWidget);

      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('MX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MX'));
      await tester.pumpAndSettle();
      expect(find.text('MX · 1'), findsOneWidget);
      expect(find.text('CNAME · 1'), findsNothing);
    });

    testBothPlatforms('the type filter scrolls under a finger to the last type', (tester, platform) async {
      final api = FakeCfAdapter()
        ..reply('GET', _base, [aRecordJson(), cnameJson(), mxJson(), txtJson(), srvJson()], resultInfo: onePage(5));
      await pumpDns(tester, api: api, location: '/domains/z1/dns');
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final other = find.text('Other');
      expect(tester.getRect(other).right, greaterThan(width), reason: 'six types overflow a phone');

      // A real drag, as a finger does it: every type can be reached.
      await tester.drag(find.text('CNAME'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(other).right, lessThanOrEqualTo(width));
      await tester.tap(other);
      await tester.pumpAndSettle();
      expect(find.text('SRV · 1'), findsOneWidget);
      expect(find.text('A · 1'), findsNothing);
      expect(
        tester.getSemantics(other),
        isSemantics(
          label: 'Other',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
    });

    testBothPlatforms('long-press delete removes the record and Undo re-creates it', (tester, platform) async {
      final api = _api()
        ..reply('DELETE', '$_base/rec-www', {'id': 'rec-www'})
        ..on(
          'POST',
          _base,
          (call) => FakeReply.ok({...(call.body as Map<String, dynamic>), 'id': 'rec-www-2', 'proxiable': true}),
        );
      await pumpDns(tester, api: api, location: '/domains/z1/dns');

      await tester.longPress(find.text('www'));
      await tester.pumpAndSettle();
      expect(find.text('Copy name'), findsOneWidget);
      expect(find.text('Copy value'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this record?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await settle(tester);

      expect(api.calls.where((c) => c.method == 'DELETE').single.path, '$_base/rec-www');
      expect(find.text('www'), findsNothing);
      expect(find.text('Record deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      final post = api.calls.lastWhere((c) => c.method == 'POST');
      expect(post.body, {
        'type': 'CNAME',
        'name': 'www.example.com',
        'content': 'example.com',
        'ttl': 300,
        'proxied': false,
        'settings': {'flatten_cname': false},
      });
      expect(find.text('www'), findsOneWidget);
      await drainToasts(tester);
    });

    testBothPlatforms('empty zone explains what to do', (tester, platform) async {
      final api = FakeCfAdapter()..reply('GET', _base, <Object>[], resultInfo: onePage(0));
      await pumpDns(tester, api: api, location: '/domains/z1/dns');
      expect(find.text('No DNS records yet'), findsOneWidget);
      expect(find.text('Add record'), findsWidgets);
    });

    testBothPlatforms('permission error names the missing permission', (tester, platform) async {
      final api = FakeCfAdapter()..on('GET', _base, (_) => FakeReply.error(403, 10000, 'Authentication error'));
      await pumpDns(tester, api: api, location: '/domains/z1/dns');
      expect(find.textContaining('Zone · DNS · Edit'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testBothPlatforms('a token without DNS access shows the permission state without calling the API', (
      tester,
      platform,
    ) async {
      final api = _api();
      await pumpDns(tester, api: api, location: '/domains/z1/dns', credential: testCredential(dns: false));
      expect(find.textContaining('Zone · DNS · Edit'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testBothPlatforms('tapping a record opens the editor', (tester, platform) async {
      await pumpDns(tester, api: _api(), location: '/domains/z1/dns');
      await tester.tap(find.text('www'));
      await settle(tester);
      expect(find.byType(DnsEditorScreen), findsOneWidget);
      expect(find.text('Edit record'), findsWidgets);
    });
  });

  group('DNS editor', () {
    testBothPlatforms('new A record: validates, then POSTs and returns to the list', (tester, platform) async {
      final api = _api()
        ..on(
          'POST',
          _base,
          (call) => FakeReply.ok({...(call.body as Map<String, dynamic>), 'id': 'rec-new', 'proxiable': true}),
        );
      await pumpDns(tester, api: api, location: '/domains/z1/dns/new');
      expect(find.text('New record'), findsWidgets);
      final save = toolbarButton(platform, EpIcon.check);
      expect(isEnabled(tester, save), isFalse, reason: 'empty IPv4');

      final input = fieldInput('IPv4 address');
      await tester.enterText(input, '300.1.1.1');
      await tester.pumpAndSettle();
      expect(find.text('Enter an IPv4 address such as 203.0.113.10.'), findsOneWidget);
      expect(isEnabled(tester, save), isFalse);

      await tester.enterText(input, '203.0.113.10');
      await tester.pumpAndSettle();
      expect(find.text('Enter an IPv4 address such as 203.0.113.10.'), findsNothing);
      expect(isEnabled(tester, save), isTrue);

      await tester.tap(save);
      await settle(tester);
      final post = api.calls.lastWhere((c) => c.method == 'POST');
      expect(post.path, _base);
      expect(post.body, {'type': 'A', 'name': 'example.com', 'content': '203.0.113.10', 'ttl': 1, 'proxied': true});
      expect(find.byType(DnsEditorScreen), findsNothing);
      expect(find.byType(DnsListScreen), findsOneWidget);
      await drainToasts(tester);
    });

    testBothPlatforms('MX form shows priority; changing type saves through the batch endpoint', (
      tester,
      platform,
    ) async {
      final api = _api()
        ..on('POST', '$_base/batch', (call) {
          final post = ((call.body as Map)['posts'] as List).single as Map<String, dynamic>;
          return FakeReply.ok({
            'deletes': [mxJson()],
            'posts': [
              {...post, 'id': 'rec-txt'},
            ],
          });
        });
      await pumpDns(tester, api: api, location: '/domains/z1/dns/rec-mx');
      expect(find.text('Mail server'), findsOneWidget);
      expect(fieldText(tester, 'Mail server'), 'route1.mx.cloudflare.net');
      expect(fieldText(tester, 'Priority'), '10');
      expect(find.text('Delete record'), findsOneWidget);

      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TXT').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('the MX record is deleted'), findsOneWidget);

      final content = fieldInput('Content');
      await tester.enterText(content, 'v=spf1 include:_spf.mx.cloudflare.net ~all');
      await tester.pumpAndSettle();
      await tester.tap(toolbarButton(platform, EpIcon.check));
      await settle(tester);

      final batch = api.calls.lastWhere((c) => c.path == '$_base/batch');
      expect(batch.body, {
        'deletes': [
          {'id': 'rec-mx'},
        ],
        'posts': [
          {'type': 'TXT', 'name': 'example.com', 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all', 'ttl': 3600},
        ],
      });
      expect(api.calls.where((c) => c.method == 'PATCH' || c.method == 'PUT'), isEmpty);
      await drainToasts(tester);
    });

    testBothPlatforms('proxied records lock TTL to Auto', (tester, platform) async {
      await pumpDns(tester, api: _api(), location: '/domains/z1/dns/023e105f4ecef8ad9ca31a8372d0c353');
      expect(find.text('Proxy through Cloudflare'), findsOneWidget);
      expect(find.textContaining('Proxied records always use Auto TTL.'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      await tester.tap(find.text('Proxy through Cloudflare'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Proxied records always use Auto TTL.'), findsNothing);
      expect(find.textContaining('DNS only:'), findsOneWidget);
    });

    testBothPlatforms('delete from the editor returns to the list with Undo', (tester, platform) async {
      final api = _api()..reply('DELETE', '$_base/rec-mx', {'id': 'rec-mx'});
      await pumpDns(tester, api: api, location: '/domains/z1/dns');
      await tester.tap(find.text('route1.mx.cloudflare.net'));
      await settle(tester);
      final delete = find.text('Delete record');
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(find.byType(DnsEditorScreen), findsNothing);
      expect(api.calls.where((c) => c.method == 'DELETE').single.path, '$_base/rec-mx');
      expect(find.text('MX · 1'), findsNothing);
      expect(find.text('Record deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await drainToasts(tester);
    });

    testBothPlatforms('unknown record id shows a recovery message', (tester, platform) async {
      await pumpDns(tester, api: _api(), location: '/domains/z1/dns/gone');
      expect(find.text('Record not found'), findsOneWidget);
    });
  });
}
