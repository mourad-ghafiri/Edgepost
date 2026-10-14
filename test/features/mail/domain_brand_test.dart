import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/mail/data/branding.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/presentation/compose_screen.dart' show attachmentPickerProvider;
import 'package:edgepost/features/mail/presentation/domain_brand_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

const _domain = 'atelier-nord.dev';

final _service = MailService(
  accountId: testAccount.id,
  workerUrl: 'https://edgepost-mail.atelier.workers.dev',
  apiKey: 'k',
  workerVersion: '1.0.0',
  domains: const [_domain],
  sendingDomains: const [_domain],
  d1Id: 'd1',
  r2Bucket: 'edgepost-mail',
);

class _Services extends MailServicesNotifier {
  @override
  Future<Map<String, MailService>> build() async => {_service.accountId: _service};
}

/// A solid [w]×[h] PNG, drawn and encoded by the engine.
Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFF2672A));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

final class _MemFile extends PlatformFile {
  _MemFile(this._bytes);
  final Uint8List _bytes;
  @override
  String get name => 'logo.png';
  @override
  Future<Uint8List> readAsBytes() async => _bytes;
  @override
  Future<int?> length() async => _bytes.length;
  @override
  int? lengthSync() => _bytes.length;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
  @override
  Uri get uri => Uri.file('/tmp/logo.png');
  @override
  get xFile => throw UnimplementedError(); // unused by the screen
}

Map<String, dynamic> _brand({String signature = '', bool logo = false}) => {
      'domain': _domain,
      'signature': signature,
      'logo': logo ? {'type': 'image/png', 'size': 1200, 'width': 480, 'height': 96, 'updatedAt': '2026-10-13T00:00:00Z'} : null,
    };

Future<void> _pump(WidgetTester tester, FakeCfAdapter api, {List<PlatformFile> pick = const []}) async {
  final dio = Dio(BaseOptions(baseUrl: _service.workerUrl, validateStatus: (_) => true))..httpClientAdapter = api;
  final client = MailClient(baseUrl: _service.workerUrl, apiKey: 'k', accountId: testAccount.id, dio: dio);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => Scaffold(body: Center(child: TextButton(onPressed: () => c.push('/brand'), child: const Text('home')))),
      ),
      GoRoute(path: '/brand', builder: (c, s) => const DomainBrandScreen(domain: _domain)),
    ],
  );
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ...accountOverrides(),
      mailServicesProvider.overrideWith(_Services.new),
      mailClientProvider.overrideWith((ref, accountId) => client),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      attachmentPickerProvider.overrideWithValue((_) async => pick),
    ],
    child: MaterialApp.router(
      theme: buildEpTheme(TargetPlatform.iOS, Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a logo is scaled to fit 480 × 96, never up, and only images are accepted', (tester) async {
    await tester.runAsync(() async {
      final wide = await prepareLogo(await _png(1200, 300));
      expect((wide.width, wide.height), (384, 96));
      final small = await prepareLogo(await _png(100, 20));
      expect((small.width, small.height), (100, 20));
      expect(await _png(1, 1).then((b) => b.sublist(1, 4)), [0x50, 0x4E, 0x47], reason: 'PNG out');
      await expectLater(prepareLogo(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<LogoException>()));
    });
  });

  testWidgets('the signature and a new logo are saved together, then the screen closes', (tester) async {
    final api = FakeCfAdapter()
      ..on('GET', '/v1/brands', (_) => FakeReply(200, {'brands': [_brand(signature: 'Old')]}))
      ..on('PUT', '/v1/brands/$_domain', (c) => FakeReply(200, _brand(signature: '${(c.body as Map)['signature']}')))
      ..on('PUT', '/v1/brands/$_domain/logo', (_) => FakeReply(200, _brand(signature: 'Mourad', logo: true)));
    final png = (await tester.runAsync(() => _png(960, 192)))!;
    await _pump(tester, api, pick: [_MemFile(png)]);

    expect(find.text('Old'), findsWidgets, reason: 'the saved signature, in the field and the preview');
    await tester.enterText(find.byType(EditableText).first, 'Mourad\nhello@atelier-nord.dev');
    await tester.pump();

    // Choosing an image decodes it for real.
    await tester.runAsync(() async {
      await tester.tap(find.text('Choose image'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Replace image'), findsOneWidget);
    expect(api.calls.where((c) => c.method == 'PUT'), isEmpty, reason: 'nothing saved before Save');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final puts = api.calls.where((c) => c.method == 'PUT').toList();
    expect(puts.map((c) => c.path), ['/v1/brands/$_domain', '/v1/brands/$_domain/logo']);
    expect((puts.first.body as Map)['signature'], 'Mourad\nhello@atelier-nord.dev');
    expect(find.text('home'), findsOneWidget, reason: 'back where it was opened');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('removing the logo happens on Save', (tester) async {
    final api = FakeCfAdapter()
      ..on('GET', '/v1/brands', (_) => FakeReply(200, {'brands': [_brand(signature: 'Mourad', logo: true)]}))
      ..on('GET', '/v1/brands/$_domain/logo', (_) => const FakeReply(200, 'not-an-image'))
      ..on('DELETE', '/v1/brands/$_domain/logo', (_) => FakeReply(200, _brand(signature: 'Mourad')));
    await _pump(tester, api);

    await tester.tap(find.text('Remove logo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose image'), findsOneWidget);
    expect(api.calls.where((c) => c.method == 'DELETE'), isEmpty);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.method == 'DELETE').single.path, '/v1/brands/$_domain/logo');
    await tester.pump(const Duration(seconds: 4));
  });
}
