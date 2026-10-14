import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One cached JSON value and when it was written.
class CacheHit {
  const CacheHit(this.value, this.savedAt);
  final Object? value;
  final DateTime savedAt;
}

/// Small on-device JSON cache that lets every list render instantly from the
/// last sync while a fresh copy loads (stale-while-revalidate). Holds API
/// responses and drafts only, never tokens. Every entry belongs to one
/// Cloudflare account (its own directory), so removing an account removes
/// everything the app kept for it.
class CacheStore {
  CacheStore({Future<Directory> Function()? root}) : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  Future<Directory> _accountDir(String account) async {
    final base = await _root();
    final d = Directory('${base.path}/edgepost-cache/${_safe(account)}');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String _safe(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');

  Future<File> _file(String account, String key) async =>
      File('${(await _accountDir(account)).path}/${_safe(key)}.json');

  Future<CacheHit?> read(String account, String key) async {
    try {
      final f = await _file(account, key);
      if (!f.existsSync()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return CacheHit(m['v'], DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()));
    } on FormatException {
      return null; // a corrupt file (e.g. an interrupted write) is a miss, never a crash
    }
  }

  Future<void> write(String account, String key, Object? value) async {
    try {
      final f = await _file(account, key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'v': value}));
      await tmp.rename(f.path);
    } on FileSystemException {
      // Cache writes are best-effort.
    }
  }

  Future<void> remove(String account, String key) async {
    final f = await _file(account, key);
    if (f.existsSync()) await f.delete();
  }

  /// The entries of one account whose key [test] picks (e.g. all its mail,
  /// once its mail service is gone). File names encode their key.
  Future<void> removeWhere(String account, bool Function(String key) test) async {
    final dir = await _accountDir(account);
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      final String key;
      try {
        key = utf8.decode(base64Url.decode(base64Url.normalize(name.substring(0, name.length - 5))));
      } on FormatException {
        continue;
      }
      if (!test(key)) continue;
      try {
        await f.delete();
      } on FileSystemException {
        // Already gone: it's only a cache.
      }
    }
  }

  /// Everything kept for one account (it was removed from the app). Best
  /// effort: a write still in flight for it can race the delete.
  Future<void> clearAccount(String account) async {
    final d = Directory('${(await _root()).path}/edgepost-cache/${_safe(account)}');
    try {
      if (d.existsSync()) await d.delete(recursive: true);
    } on FileSystemException {
      // Already gone, or a late write got in the way: it's only a cache.
    }
  }
}
