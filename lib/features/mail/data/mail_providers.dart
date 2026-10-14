import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'mail_client.dart';
import 'mail_models.dart';

/// Mail services set up on this device, by account id (at most one per
/// added Cloudflare account).
final mailServicesProvider = AsyncNotifierProvider<MailServicesNotifier, Map<String, MailService>>(
  MailServicesNotifier.new,
);

class MailServicesNotifier extends AsyncNotifier<Map<String, MailService>> {
  @override
  Future<Map<String, MailService>> build() async {
    final ids = ref.watch(accountsProvider.select((a) => [for (final x in a) x.id].join(','))).split(',');
    final store = ref.read(secureStoreProvider);
    final out = <String, MailService>{};
    for (final id in ids.where((i) => i.isNotEmpty)) {
      final j = await store.readMailService(id);
      if (j != null) out[id] = MailService.fromJson(j);
    }
    return out;
  }

  Future<void> save(MailService s) async {
    await ref.read(secureStoreProvider).writeMailService(s.accountId, s.toJson());
    state = AsyncData({...?state.value, s.accountId: s});
  }

  /// Drops the account's mail service from this device, with everything
  /// cached from it (its mail is not the next service's).
  Future<void> forget(String accountId) async {
    final store = ref.read(secureStoreProvider);
    await store.deleteMailService(accountId);
    // Its sync cursor counts the old Worker's changes, not the next one's.
    await store.updateSettings((s) {
      final cursors = Map<String, dynamic>.from((s['mail_sync_cursors'] as Map?) ?? const {})..remove(accountId);
      s['mail_sync_cursors'] = cursors;
    });
    await ref.read(cacheStoreProvider).removeWhere(accountId, (k) => k.startsWith('mail:'));
    state = AsyncData({...?state.value}..remove(accountId));
  }
}

/// The account's mail service, or null when it has none (or it's loading).
final mailServiceProvider = Provider.family<MailService?, String>(
  (ref, accountId) => ref.watch(mailServicesProvider).value?[accountId],
);

final mailClientProvider = Provider.family<MailClient, String>((ref, accountId) {
  final s = ref.watch(mailServiceProvider(accountId));
  if (s == null) throw StateError('No mail service for account $accountId');
  return MailClient(baseUrl: s.workerUrl, apiKey: s.apiKey, accountId: accountId);
});

/// The account's mailboxes (addresses that received or sent mail).
final mailboxesProvider = FutureProvider.family<List<Mailbox>, String>((ref, accountId) async {
  if (await ref.watch(mailServicesProvider.selectAsync((s) => s[accountId])) == null) return const [];
  final list = await ref.read(mailClientProvider(accountId)).mailboxes();
  return list..sort((a, b) => a.address.compareTo(b.address));
});

/// Per-address display name, stored with the app settings. (Signatures and
/// logos belong to the domain: see `branding.dart`.)
class Identity {
  const Identity(this.address, {this.name});
  final String address;
  final String? name;
  MailAddress get mail => MailAddress(address, name);
}

/// Saved display names of one account's addresses.
final identitySettingsProvider = AsyncNotifierProvider.family<IdentitySettings, Map<String, Identity>, String>(
  IdentitySettings.new,
);

class IdentitySettings extends AsyncNotifier<Map<String, Identity>> {
  IdentitySettings(this.accountId);
  final String accountId;

  @override
  Future<Map<String, Identity>> build() async {
    final s = await ref.read(secureStoreProvider).readSettings();
    final m = ((s['mail_identities'] as Map?)?[accountId] as Map<String, dynamic>?) ?? const {};
    return {
      for (final e in m.entries) e.key: Identity(e.key, name: (e.value as Map)['name'] as String?),
    };
  }

  Future<void> put(Identity i) async {
    await ref.read(secureStoreProvider).updateSettings((s) {
      final all = Map<String, dynamic>.from((s['mail_identities'] as Map?) ?? const {});
      final m = Map<String, dynamic>.from((all[accountId] as Map?) ?? const {});
      m[i.address.toLowerCase()] = {'name': i.name};
      all[accountId] = m;
      s['mail_identities'] = all;
    });
    state = AsyncData({...?state.value, i.address.toLowerCase(): i});
  }
}

/// Every address the account can send from: known mailboxes on its domains
/// plus saved identities. (Any other local part on one of its domains can be
/// typed in compose.)
final identitiesProvider = Provider.family<List<Identity>, String>((ref, accountId) {
  final saved = ref.watch(identitySettingsProvider(accountId)).value ?? const <String, Identity>{};
  final boxes = ref.watch(mailboxesProvider(accountId)).value ?? const <Mailbox>[];
  final domains = {...?ref.watch(mailServiceProvider(accountId))?.domains.map((d) => d.toLowerCase())};
  final out = <String, Identity>{};
  for (final b in boxes) {
    if (domains.contains(b.domain.toLowerCase())) {
      out[b.address.toLowerCase()] = saved[b.address.toLowerCase()] ?? Identity(b.address);
    }
  }
  for (final i in saved.values) {
    out.putIfAbsent(i.address.toLowerCase(), () => i);
  }
  return out.values.toList()..sort((a, b) => a.address.compareTo(b.address));
});

/// What a message list shows.
class MailQuery {
  const MailQuery({this.folder = MailFolder.inbox, this.mailbox, this.domain, this.search});

  final MailFolder folder;
  final String? mailbox;
  final String? domain;
  final String? search;

  String get key => '${folder.name}|${mailbox ?? ''}|${domain ?? ''}|${search ?? ''}';

  @override
  bool operator ==(Object other) => other is MailQuery && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class MailListState {
  const MailListState({
    required this.messages,
    this.cursor,
    this.loadingMore = false,
    this.refreshError,
    this.syncedAt,
    this.fromCache = false,
  });

  final List<MessageSummary> messages;

  /// Next page, or null when the list is complete.
  final String? cursor;
  final bool loadingMore;

  /// The last refresh failed; [messages] are the previous copy.
  final Object? refreshError;
  final DateTime? syncedAt;
  final bool fromCache;

  bool get hasMore => cursor != null;
}

typedef MailListKey = (String accountId, MailQuery query);

/// One account's messages for a query, newest first, with cursor paging and
/// an on-device copy of the first page for instant opening.
final mailListProvider = AsyncNotifierProvider.autoDispose.family<MailListNotifier, MailListState, MailListKey>(
  MailListNotifier.new,
);

class MailListNotifier extends AsyncNotifier<MailListState> {
  MailListNotifier(this.key);
  final MailListKey key;

  String get _account => key.$1;
  MailQuery get _query => key.$2;
  String get _cacheKey => 'mail:list:${_query.key}';
  bool get _cached => _query.search == null || _query.search!.isEmpty;

  @override
  Future<MailListState> build() async {
    // A replaced service starts the list over.
    ref.watch(mailServiceProvider(_account));
    if (_cached) {
      final hit = await ref.read(cacheStoreProvider).read(_account, _cacheKey);
      if (hit != null) {
        final cached = (hit.value as List)
            .cast<Map<String, dynamic>>()
            .map((m) => MessageSummary.fromJson(m, accountId: _account))
            .toList();
        unawaited(Future<void>.microtask(refresh));
        return MailListState(messages: cached, syncedAt: hit.savedAt, fromCache: true);
      }
    }
    return _loadFirst();
  }

  Future<MailListState> _loadFirst() async {
    final page = await _page(null);
    if (_cached) {
      unawaited(
        ref.read(cacheStoreProvider).write(_account, _cacheKey, page.messages.take(60).map((m) => m.toJson()).toList()),
      );
    }
    return MailListState(messages: page.messages, cursor: page.nextCursor, syncedAt: DateTime.now());
  }

  Future<MessagePage> _page(String? cursor) => ref
      .read(mailClientProvider(_account))
      .messages(
        folder: _query.folder,
        mailbox: _query.mailbox,
        domain: _query.domain,
        query: _query.search,
        cursor: cursor,
      );

  Future<void> refresh() async {
    try {
      final fresh = await _loadFirst();
      if (ref.mounted) state = AsyncData(fresh);
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      final cur = state.value;
      state = cur == null
          ? AsyncError(e, st)
          : AsyncData(
              MailListState(
                messages: cur.messages,
                cursor: cur.cursor,
                refreshError: e,
                syncedAt: cur.syncedAt,
                fromCache: true,
              ),
            );
    }
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.loadingMore || !cur.hasMore) return;
    state = AsyncData(
      MailListState(messages: cur.messages, cursor: cur.cursor, loadingMore: true, syncedAt: cur.syncedAt),
    );
    try {
      final page = await _page(cur.cursor);
      if (!ref.mounted) return;
      final seen = {for (final m in cur.messages) m.key};
      state = AsyncData(
        MailListState(
          messages: [...cur.messages, ...page.messages.where((m) => seen.add(m.key))],
          cursor: page.nextCursor,
          syncedAt: cur.syncedAt,
        ),
      );
    } on MailException {
      // Keep the cursor; the next scroll retries.
      if (ref.mounted) {
        state = AsyncData(MailListState(messages: cur.messages, cursor: cur.cursor, syncedAt: cur.syncedAt));
      }
    }
  }
}

/// Local overrides after flag/folder changes, applied by every list so the
/// UI updates instantly across views while the Worker catches up.
final mailPatchesProvider = NotifierProvider<MailPatches, Map<String, MessageSummary>>(MailPatches.new);

class MailPatches extends Notifier<Map<String, MessageSummary>> {
  @override
  Map<String, MessageSummary> build() => const {};

  void put(MessageSummary m) => state = {...state, m.key: m};
  void drop(String key) => state = {...state}..remove(key);
}

/// [messages] with local patches applied and items that left [folder] removed.
List<MessageSummary> applyPatches(
  List<MessageSummary> messages,
  Map<String, MessageSummary> patches,
  MailFolder folder,
) => [
  for (final m in messages)
    if ((patches[m.key] ?? m).folder == folder) patches[m.key] ?? m,
];

final messageDetailProvider = FutureProvider.family<MessageDetail, (String, String)>((ref, args) async {
  final (accountId, id) = args;
  final cache = ref.read(cacheStoreProvider);
  final key = 'mail:msg:$id';
  try {
    final d = await ref.read(mailClientProvider(accountId)).message(id);
    unawaited(
      cache.write(accountId, key, {
        ...d.summary.toJson(),
        'text': d.text,
        'html': d.html,
        'attachments': [
          for (final a in d.attachments)
            {
              'id': a.id,
              'filename': a.filename,
              'mimeType': a.mimeType,
              'size': a.size,
              'contentId': a.contentId,
              'inline': a.inline,
            },
        ],
      }),
    );
    return d;
  } on MailException catch (e) {
    if (!e.isNetwork) rethrow;
    final hit = await cache.read(accountId, key);
    if (hit == null) rethrow;
    return MessageDetail.fromJson(hit.value! as Map<String, dynamic>, accountId: accountId);
  }
});

final threadProvider = FutureProvider.family<List<MessageSummary>, (String, String)>((ref, args) async {
  final (accountId, threadId) = args;
  return ref.read(mailClientProvider(accountId)).thread(threadId);
});

/// Flag and folder changes with optimistic UI and rollback.
class MailActions {
  MailActions(this.ref);
  final Ref ref;

  MailClient _client(MessageSummary m) => ref.read(mailClientProvider(m.accountId));
  MailPatches get _patches => ref.read(mailPatchesProvider.notifier);

  Future<void> setRead(MessageSummary m, bool read) =>
      _apply(m, m.copyWith(read: read), () => _client(m).update(m.id, read: read));

  Future<void> setStarred(MessageSummary m, bool starred) =>
      _apply(m, m.copyWith(starred: starred), () => _client(m).update(m.id, starred: starred));

  Future<void> move(MessageSummary m, MailFolder folder) =>
      _apply(m, m.copyWith(folder: folder), () => _client(m).update(m.id, folder: folder));

  /// Trash, or purge when already in trash. Returns the Worker's result.
  Future<String> delete(MessageSummary m) async {
    final r = await _client(m).delete(m.id);
    _patches.put(m.copyWith(folder: MailFolder.trash));
    if (r == 'purged') _invalidateLists();
    return r;
  }

  Future<void> _apply(MessageSummary before, MessageSummary after, Future<MessageSummary> Function() call) async {
    _patches.put(after);
    try {
      final server = await call();
      _patches.put(server);
    } on Object {
      _patches.put(before);
      rethrow;
    }
  }

  void _invalidateLists() => ref.invalidate(mailListProvider);
}

final mailActionsProvider = Provider<MailActions>(MailActions.new);

/// The images a message's HTML shows by `cid:` (logos in signatures, pasted
/// pictures), as `data:` URIs: the reader's sandbox loads nothing else. At
/// most 2 MB per message.
final inlineImagesProvider = FutureProvider.family<Map<String, String>, (String, String)>((ref, args) async {
  final d = await ref.watch(messageDetailProvider(args).future);
  final html = d.html ?? '';
  if (!html.contains('cid:')) return const {};
  final client = ref.read(mailClientProvider(args.$1));
  var room = 2 * 1024 * 1024;
  final out = <String, String>{};
  for (final a in d.attachments) {
    final cid = a.contentId?.replaceAll(RegExp(r'^<|>$'), '');
    if (cid == null || !a.mimeType.startsWith('image/') || !html.contains('cid:$cid') || a.size > room) continue;
    final bytes = await client.attachment(a.id);
    room -= bytes.length;
    out[cid] = 'data:${a.mimeType};base64,${base64Encode(bytes)}';
  }
  return out;
});

/// [html] with each `cid:` source found in [images] replaced by its image.
String resolveInlineImages(String html, Map<String, String> images) => images.isEmpty
    ? html
    : html.replaceAllMapped(
        RegExp(r"""cid:([^"'\s>)]+)""", caseSensitive: false),
        (m) => images[m.group(1)] ?? m.group(0)!,
      );
