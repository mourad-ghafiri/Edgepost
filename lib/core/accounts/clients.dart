import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloudflare/cf_client.dart';
import '../cloudflare/cf_errors.dart';
import '../cloudflare/models.dart';
import '../providers.dart';
import 'access.dart';
import 'credential.dart';

CfClient _clientOf(Access access, Capability c, CfClient Function(String tokenId) client) => switch (access) {
      Granted(:final token) => client(token.id),
      NoAccess(:final reason) => throw CfNoAccessException(c.permission, reason),
    };

/// The API client for a capability in one account or zone, or a
/// [CfNoAccessException] that says which permission is missing.
extension AccessClients on Ref {
  CfClient accountClient(String accountId, Capability c) =>
      _clientOf(read(accessProvider).account(accountId, c), c, (id) => read(cfClientProvider(id)));

  CfClient zoneClient(Zone zone, Capability c) =>
      _clientOf(read(accessProvider).zone(zone, c), c, (id) => read(cfClientProvider(id)));
}

extension WidgetAccessClients on WidgetRef {
  CfClient accountClient(String accountId, Capability c) =>
      _clientOf(read(accessProvider).account(accountId, c), c, (id) => read(cfClientProvider(id)));

  CfClient zoneClient(Zone zone, Capability c) =>
      _clientOf(read(accessProvider).zone(zone, c), c, (id) => read(cfClientProvider(id)));
}

/// Re-runs the permission check of the tokens that reach [accountId] (all of
/// them, or only [tokenIds]), e.g. after the user edited a token in the
/// dashboard.
Future<void> recheckAccess(WidgetRef ref, String accountId, {Iterable<String>? tokenIds}) async {
  final vault = ref.read(vaultProvider.notifier);
  final ids = tokenIds ?? [for (final t in ref.read(tokensProvider)) if (t.reaches(accountId)) t.id];
  for (final id in ids) {
    await vault.reprobe(id, accountId);
  }
}
