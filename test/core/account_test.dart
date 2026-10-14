import 'package:edgepost/core/accounts/account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initials', () {
    test('Cloudflare\'s default name gives the email\'s first letters', () {
      expect(accountInitials("jane.doe@example.com's Account"), 'JD');
      expect(accountInitials('jane@example.com’s account'), 'J');
    });

    test('names give the first letters of up to two words', () {
      expect(accountInitials('Atelier Nord'), 'AN');
      expect(accountInitials('Studio Ember Holdings Ltd'), 'SE');
      expect(accountInitials('personal'), 'P');
      expect(accountInitials('client-co'), 'CC');
    });

    test('punctuation and symbols are skipped; letters stay whole', () {
      expect(accountInitials('(Old) Studio'), 'OS');
      expect(accountInitials('🚀 Launch'), 'L');
      expect(accountInitials('Édition Ōkami'), 'ÉŌ');
    });

    test('nothing usable gives a placeholder', () {
      expect(accountInitials('   '), '?');
      expect(accountInitials('—'), '?');
    });
  });

  test('a nickname is shown instead of the Cloudflare name, and can be cleared', () {
    const a = Account(id: 'a1', cloudflareName: "jane@example.com's Account", colorIndex: 0);
    final named = a.copyWith(nickname: 'Clients');
    expect((named.name, named.initials), ('Clients', 'C'));
    expect(named.copyWith(clearNickname: true).name, a.cloudflareName);
    expect(Account.fromJson(named.toJson()).nickname, 'Clients');
  });
}
