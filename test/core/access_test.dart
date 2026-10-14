import 'package:edgepost/core/accounts/access.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounts.dart';

/// A token checked in a1 with exactly [states].
Credential _token(String id, Map<Capability, CapState> states, {TokenKind kind = TokenKind.user, bool both = false}) =>
    fakeToken(id: id, kind: kind, accounts: both ? const [testAccount, otherAccount] : const [testAccount])
        .copyWith(capabilities: {testAccount.id: states});

String? _picked(Access a) => switch (a) {
      Granted(:final token) => token.id,
      NoAccess() => null,
    };

void main() {
  const workers = Capability.workers;

  test('a confirmed grant beats "turn on", which beats "not checked yet"', () {
    final r = AccessResolver([
      _token('unknown', {workers: CapState.unknown}),
      _token('off', {workers: CapState.notEnabled}),
      _token('ok', {workers: CapState.granted}),
    ]);
    expect(r.account('a1', workers), Granted(r.tokens[2], CapState.granted));
    expect(_picked(AccessResolver(r.tokens.take(2).toList()).account('a1', workers)), 'off');
  });

  test('ties go to the token added first', () {
    final r = AccessResolver([
      _token('first', {workers: CapState.granted}),
      _token('second', {workers: CapState.granted}),
    ]);
    expect(_picked(r.account('a1', workers)), 'first');
  });

  test('a refused token is never used; all refused is "denied", none reaching is "no token"', () {
    final denied = _token('no', {workers: CapState.denied});
    expect(_picked(AccessResolver([denied, _token('maybe', const {})]).account('a1', workers)), 'maybe');
    expect(AccessResolver([denied]).account('a1', workers), const NoAccess(NoAccessKind.denied));
    expect(AccessResolver([denied]).account('a2', workers), const NoAccess(NoAccessKind.noToken));
  });

  test('permissions in one account say nothing about another', () {
    final t = _token('t', {workers: CapState.denied}, both: true);
    expect(AccessResolver([t]).account('a1', workers), const NoAccess(NoAccessKind.denied));
    expect(AccessResolver([t]).account('a2', workers), Granted(t, CapState.unknown));
  });

  test('Registrar needs a user token', () {
    final acct = _token('acct', {Capability.registrar: CapState.granted}, kind: TokenKind.account);
    expect(AccessResolver([acct]).account('a1', Capability.registrar), const NoAccess(NoAccessKind.needsUserToken));
    final user = _token('user', const {});
    expect(_picked(AccessResolver([acct, user]).account('a1', Capability.registrar)), 'user');
  });

  test('a zone is only reached through the tokens that listed it', () {
    final wide = _token('wide', {Capability.dns: CapState.granted});
    final scoped = _token('scoped', {Capability.dns: CapState.unknown});
    final r = AccessResolver([wide, scoped]);
    expect(_picked(r.zone(fakeZone(reach: ['scoped']), Capability.dns)), 'scoped');
    expect(_picked(r.zone(fakeZone(reach: ['scoped', 'wide']), Capability.dns)), 'wide');
    expect(r.zone(fakeZone(reach: const []), Capability.dns), const NoAccess(NoAccessKind.noToken));
  });

  test('mail setup needs one token holding every permission', () {
    const caps = {Capability.workers, Capability.d1, Capability.r2};
    final partial = _token('partial', {Capability.workers: CapState.granted, Capability.d1: CapState.denied});
    final full = _token('full', {for (final c in caps) c: CapState.granted});
    expect(AccessResolver([partial]).all('a1', caps), const NoAccess(NoAccessKind.denied));
    expect(AccessResolver([partial, full]).all('a1', caps), Granted(full, CapState.granted));
    final unsure = _token('unsure', {Capability.workers: CapState.granted});
    expect(AccessResolver([unsure]).all('a1', caps), Granted(unsure, CapState.unknown));
  });

  test('UI gating: no token is "unknown" (tried, then explained), refused is "denied"', () {
    expect(const AccessResolver([]).best('a1', workers), CapState.unknown);
    expect(AccessResolver([_token('no', {workers: CapState.denied})]).best('a1', workers), CapState.denied);
    expect(AccessResolver([_token('ok', {workers: CapState.granted})]).best('a1', workers), CapState.granted);
  });
}
