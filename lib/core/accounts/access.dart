import '../cloudflare/cf_errors.dart';
import '../cloudflare/models.dart';
import 'credential.dart';

export '../cloudflare/cf_errors.dart' show NoAccessKind;

/// Which token to use for something, or why there is none.
sealed class Access {
  const Access();
}

final class Granted extends Access {
  const Granted(this.token, this.state);
  final Credential token;

  /// How sure the last permission check was (granted, or not checked yet).
  final CapState state;

  @override
  bool operator ==(Object other) => other is Granted && other.token.id == token.id && other.state == state;

  @override
  int get hashCode => Object.hash(token.id, state);
}

final class NoAccess extends Access {
  const NoAccess(this.reason);
  final NoAccessKind reason;

  @override
  bool operator ==(Object other) => other is NoAccess && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// Picks a token for an (account, capability) pair. A capability a token was
/// refused is never used; among the rest, a confirmed grant wins over "turn on
/// in the dashboard", which wins over "not checked yet". Ties go to the
/// earliest-added token, so the choice is stable.
class AccessResolver {
  const AccessResolver(this.tokens);

  /// Every stored token, in the order they were added.
  final List<Credential> tokens;

  static const _rank = {CapState.granted: 0, CapState.notEnabled: 1, CapState.unknown: 2};

  Access account(String accountId, Capability c) => _pick(tokens.where((t) => t.reaches(accountId)), accountId, c);

  /// Only tokens that listed the zone: a token can be limited to some zones.
  Access zone(Zone z, Capability c) =>
      _pick(tokens.where((t) => z.reach.contains(t.id) && t.reaches(z.account.id)), z.account.id, c);

  /// One token holding every capability in [caps] (mail setup deploys with a
  /// single token).
  Access all(String accountId, Set<Capability> caps) {
    final reaching = tokens.where((t) => t.reaches(accountId)).toList();
    if (reaching.isEmpty) return const NoAccess(NoAccessKind.noToken);
    for (final t in reaching) {
      if (caps.every((c) => t.can(accountId, c))) {
        final sure = caps.every((c) => t.stateOf(accountId, c) == CapState.granted);
        return Granted(t, sure ? CapState.granted : CapState.unknown);
      }
    }
    return const NoAccess(NoAccessKind.denied);
  }

  /// The best state any token has for this capability, for gating UI.
  CapState best(String accountId, Capability c) => switch (account(accountId, c)) {
        Granted(:final state) => state,
        NoAccess(reason: NoAccessKind.noToken) => CapState.unknown,
        NoAccess() => CapState.denied,
      };

  Access _pick(Iterable<Credential> candidates, String accountId, Capability c) {
    final list = candidates.toList();
    if (list.isEmpty) return const NoAccess(NoAccessKind.noToken);
    // Cloudflare Registrar refuses account-owned tokens.
    final usable = c == Capability.registrar ? list.where((t) => t.kind == TokenKind.user).toList() : list;
    if (usable.isEmpty) return const NoAccess(NoAccessKind.needsUserToken);
    Credential? best;
    for (final t in usable) {
      final s = t.stateOf(accountId, c);
      if (s == CapState.denied) continue;
      if (best == null || _rank[s]! < _rank[best.stateOf(accountId, c)]!) best = t;
    }
    return best == null ? const NoAccess(NoAccessKind.denied) : Granted(best, best.stateOf(accountId, c));
  }
}
