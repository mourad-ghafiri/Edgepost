import 'dart:ui' show Locale;

import 'package:edgepost/core/providers.dart';
import 'package:edgepost/features/mail/data/contacts.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_domains.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/data/recipient_suggestions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_cache.dart';

final _now = DateTime.utc(2026, 10, 13, 12);

MailContact _c(String address, {String? name, int count = 1, int daysAgo = 1}) => MailContact(
  address: address,
  name: name,
  count: count,
  lastSent: _now.subtract(Duration(days: daysAgo)),
);

final _contacts = [
  _c('lena.berg@gmail.com', name: 'Lena Berg', count: 6, daysAgo: 2),
  _c('helene.martin@orange.fr', name: 'Hélène Martin', count: 2, daysAgo: 1),
  _c('sam@clientco.example', name: 'Sam Okafor', count: 30, daysAgo: 400),
  _c('ops@kestrel-labs.dev', count: 1, daysAgo: 0),
];

RecipientSuggestions _s({
  List<MailContact>? contacts,
  List<Locale> locales = const [Locale('en', 'US')],
  Set<String> exclude = const {},
}) => RecipientSuggestions(contacts: contacts ?? _contacts, locales: locales, exclude: exclude, now: _now);

List<String> _addresses(List<RecipientSuggestion> s) => [for (final x in s) x.address.address];

class _Client extends MailClient {
  _Client() : super(baseUrl: 'https://x.workers.dev', apiKey: 'k', accountId: 'a1');
  @override
  Future<List<MailContact>> contacts() async => [_c('lena.berg@gmail.com', name: 'Lena Berg', count: 2)];
}

void main() {
  group('quick picks', () {
    test('the people written to most, recent sends weighing more, minus the message', () {
      expect(_s().quickPicks().map((a) => a.address), [
        'lena.berg@gmail.com',
        'helene.martin@orange.fr',
        'ops@kestrel-labs.dev',
        'sam@clientco.example', // 30 sends, but over a year ago
      ]);
      expect(_s().quickPicks().first.name, 'Lena Berg');
      expect(
        _s(exclude: {'Lena.Berg@gmail.com'}).quickPicks().map((a) => a.address),
        isNot(contains('lena.berg@gmail.com')),
      );
      expect(_s().quickPicks(limit: 2), hasLength(2));
    });
  });

  group('while typing', () {
    test('matches a name from its start, any word, accents or not', () {
      expect(_addresses(_s().forInput('hele')), ['helene.martin@orange.fr']);
      expect(_addresses(_s().forInput('Martin')), ['helene.martin@orange.fr']);
      expect(_addresses(_s().forInput('oka')), ['sam@clientco.example']);
    });

    test('matches an address from its start, then a part of it, then inside it', () {
      expect(_addresses(_s().forInput('lena')).first, 'lena.berg@gmail.com');
      expect(_addresses(_s().forInput('berg')), ['lena.berg@gmail.com'], reason: 'a part of the name before @');
      expect(_addresses(_s().forInput('kestrel')), ['ops@kestrel-labs.dev'], reason: 'the domain');
      expect(_s().forInput('zz'), isEmpty);
    });

    test('completes the domain after @: yours first, then the big ones, three at most', () {
      final s = _s().forInput('jo@');
      expect(_addresses(s), ['jo@gmail.com', 'jo@orange.fr', 'jo@kestrel-labs.dev']);
      expect(s.every((x) => x.kind == SuggestionKind.domain), isTrue);
      expect(_addresses(_s(contacts: const []).forInput('jo@')), ['jo@gmail.com', 'jo@outlook.com', 'jo@hotmail.com']);
    });

    test('ranks the providers common where you are, after the five giants', () {
      List<String> complete(String typed, List<Locale> locales) =>
          _addresses(_s(contacts: const [], locales: locales).forInput(typed));
      expect(complete('a@o', const [Locale('fr', 'FR')]), ['a@outlook.com', 'a@orange.fr', 'a@outlook.fr']);
      expect(complete('a@l', const [Locale('fr', 'FR')]).take(3), ['a@laposte.net', 'a@live.fr', 'a@live.com']);
      expect(complete('a@w', const [Locale('de')]).first, 'a@web.de', reason: 'language alone picks the country');
      expect(complete('a@y', const [Locale('ja', 'JP')]).take(2), ['a@yahoo.com', 'a@yahoo.co.jp']);
      expect(complete('a@gmail.co', const [Locale('en', 'US')]), ['a@gmail.com'], reason: '.co for .com');
      expect(complete('a@gmail.com', const [Locale('en', 'US')]), isEmpty, reason: 'nothing left to complete');
    });

    test('keeps what was typed before @ as typed', () {
      expect(_addresses(_s(contacts: const []).forInput('Jo.Doe@gma')), ['Jo.Doe@gmail.com']);
    });

    test('people come first, with room left for completions', () {
      final many = [for (var i = 0; i < 8; i++) _c('jo$i@gmail.com', count: 8 - i)];
      final s = _s(contacts: many).forInput('jo');
      expect(s, hasLength(4), reason: 'a short list');
      expect(s.every((x) => x.kind == SuggestionKind.contact), isTrue);
      final at = _s(contacts: [...many, _c('jo@gmx.net', count: 1)]).forInput('jo@gm');
      expect(_addresses(at), ['jo@gmx.net', 'jo@gmail.com', 'jo@gmx.com'], reason: 'a person, then the rest');
      final crowd = [for (var i = 0; i < 8; i++) _c('jo@team$i.example', count: 8 - i)];
      expect(_s(contacts: crowd).forInput('jo@').map((x) => x.kind), [
        SuggestionKind.contact,
        SuggestionKind.contact,
        SuggestionKind.domain,
        SuggestionKind.domain,
      ]);
    });

    test('offers a fix for a mistyped provider, never for a real or unknown domain', () {
      final s = _s(contacts: const []).forInput('kim@gmial.com');
      expect(_addresses(s), ['kim@gmail.com']);
      expect(s.single.kind, SuggestionKind.correction);
      expect(s.single.typedDomain, 'gmial.com');
      expect(_addresses(_s(contacts: const []).forInput('kim@hotmial.fr')), ['kim@hotmail.fr']);
      expect(_addresses(_s(contacts: const []).forInput('kim@yahooo.com')), ['kim@yahoo.com']);
      expect(_s(contacts: const []).forInput('kim@web.de'), isEmpty, reason: 'a real provider elsewhere');
      expect(_s(contacts: const []).forInput('kim@acme-studio.io'), isEmpty, reason: 'not close to any');
      expect(_s().forInput('kim@kestrel-lab.dev').single.address.address, 'kim@kestrel-labs.dev', reason: 'yours too');
    });

    test('never offers what is already on the message', () {
      expect(_s(exclude: {'jo@gmail.com'}).forInput('jo@gma'), isEmpty);
      expect(_s(exclude: {'helene.martin@orange.fr'}).forInput('hel'), isEmpty);
    });

    test('completes nothing it cannot make an address of (people still match)', () {
      for (final typed in ['@gm', 'a b@gm', 'a@b@gm']) {
        expect(_s().forInput(typed).where((x) => x.kind != SuggestionKind.contact), isEmpty, reason: typed);
      }
      expect(_addresses(_s().forInput('@gm')), ['lena.berg@gmail.com'], reason: 'people at gmail');
    });
  });

  test('edit distance counts a swap of neighbours as one edit', () {
    expect(editDistance('gmial.com', 'gmail.com'), 1);
    expect(editDistance('gmai.com', 'gmail.com'), 1);
    expect(editDistance('gmail.con', 'gmail.com'), 1);
    expect(editDistance('abc', 'abc'), 0);
    expect(editDistance('', 'abc'), 3);
  });

  test('accents fold to plain letters, one for one', () {
    expect(foldDiacritics('hélène çà ñ ł'), 'helene ca n l');
  });

  test('the catalogue has no duplicates or upper case', () {
    for (final list in [kGlobalMailDomains, ...kCountryMailDomains.values]) {
      expect(list.toSet(), hasLength(list.length));
      expect(list.every((d) => d == d.toLowerCase() && d.contains('.')), isTrue);
    }
  });

  test('a sent message counts its recipients at once, and is cached', () async {
    final container = ProviderContainer(
      overrides: [
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        mailClientProvider.overrideWith((ref, accountId) => _Client()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(contactsProvider('a1').future);
    container.read(contactsProvider('a1').notifier).noteSent(const [
      MailAddress('Lena.Berg@gmail.com'),
      MailAddress('new@x.io', 'New'),
    ], at: _now);
    final data = container.read(contactsProvider('a1')).value!.data;
    final lena = data.firstWhere((c) => c.address == 'lena.berg@gmail.com');
    expect((lena.count, lena.name, lena.lastSent), (3, 'Lena Berg', _now), reason: 'name kept when none given');
    expect(data.firstWhere((c) => c.address == 'new@x.io').name, 'New');
    final cached = await container.read(cacheStoreProvider).read('a1', 'mail:contacts');
    expect((cached!.value as List), hasLength(2));
  });
}
