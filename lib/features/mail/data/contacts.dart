import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'mail_models.dart';
import 'mail_providers.dart';

/// The people this account's mail service has sent to, from the service (so
/// every device sees the same) and cached on the device.
final contactsProvider = AsyncNotifierProvider.family<ContactsNotifier, Synced<List<MailContact>>, String>(
  ContactsNotifier.new,
);

class ContactsNotifier extends SyncedNotifier<List<MailContact>> {
  ContactsNotifier(this.accountId);
  final String accountId;

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'mail:contacts';

  @override
  void prepare() => ref.watch(mailServiceProvider(accountId));

  @override
  Future<List<MailContact>> fetch() => ref.read(mailClientProvider(accountId)).contacts();

  @override
  Object? encode(List<MailContact> data) => data.map((c) => c.toJson()).toList();

  @override
  List<MailContact> decode(Object? json) =>
      (json as List).cast<Map<String, dynamic>>().map(MailContact.fromJson).toList();

  /// Counts a message just sent, so its recipients are suggested right away
  /// (the service has them too, from the next fetch on).
  void noteSent(Iterable<MailAddress> recipients, {DateTime? at}) {
    // Not loaded: the next fetch has them anyway.
    final current = state.value?.data;
    if (current == null) return;
    final now = at ?? DateTime.now();
    final byAddress = {for (final c in current) c.address: c};
    for (final a in recipients) {
      final key = a.address.toLowerCase();
      final known = byAddress[key];
      byAddress[key] = MailContact(
        address: key,
        name: a.name ?? known?.name,
        count: (known?.count ?? 0) + 1,
        lastSent: now,
      );
    }
    setData(byAddress.values.toList());
  }
}
