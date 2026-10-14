import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import 'dns_record.dart';

/// Result of `POST /zones/{zone_id}/dns_records/batch`.
class DnsBatchResult {
  const DnsBatchResult({this.deletes = const [], this.patches = const [], this.puts = const [], this.posts = const []});

  factory DnsBatchResult.fromJson(Map<String, dynamic> j) {
    List<DnsRecord> list(String k) =>
        (j[k] as List? ?? const []).whereType<Map<String, dynamic>>().map(DnsRecord.fromJson).toList();
    return DnsBatchResult(deletes: list('deletes'), patches: list('patches'), puts: list('puts'), posts: list('posts'));
  }

  final List<DnsRecord> deletes;
  final List<DnsRecord> patches;
  final List<DnsRecord> puts;
  final List<DnsRecord> posts;
}

/// DNS records of one zone, over the Cloudflare v4 API:
/// https://developers.cloudflare.com/api/resources/dns/subresources/records/
class DnsRepository {
  DnsRepository(this.client, this.zoneId);

  final CfClient client;
  final String zoneId;

  /// Cloudflare's zone file limit for imports: 256 KiB.
  /// https://developers.cloudflare.com/dns/manage-dns-records/how-to/import-and-export/
  static const int maxImportBytes = 262144;

  String get _base => '/zones/$zoneId/dns_records';

  Future<List<DnsRecord>> list() async {
    final rows = await client.getAll(_base, query: {'order': 'type', 'direction': 'asc'}, perPage: 100);
    return rows.map(DnsRecord.fromJson).toList();
  }

  Future<DnsRecord> create(Map<String, dynamic> body) async {
    final res = await client.post(_base, data: body);
    return DnsRecord.fromJson(res.map);
  }

  /// Same-type edit: `PATCH /dns_records/{id}`. A type change must not use
  /// PATCH or PUT (deprecated, removed after 2026-06-30); [update] routes it
  /// through [replace] instead.
  Future<DnsRecord> patch(String id, Map<String, dynamic> body) async {
    final res = await client.patch('$_base/$id', data: body);
    return DnsRecord.fromJson(res.map);
  }

  /// Edits [original] to match [body]. When the type changes, deletes and
  /// re-creates the record in one atomic batch.
  /// https://developers.cloudflare.com/fundamentals/api/reference/deprecations/
  Future<DnsRecord> update(DnsRecord original, Map<String, dynamic> body) {
    final newType = '${body['type']}'.toUpperCase();
    if (newType != original.type) return replace(original.id, body);
    return patch(original.id, body);
  }

  /// Atomic delete + create through the batch endpoint (deletes run before
  /// posts; if any step fails nothing is applied).
  /// https://developers.cloudflare.com/dns/manage-dns-records/how-to/batch-record-changes/
  Future<DnsRecord> replace(String id, Map<String, dynamic> body) async {
    final result = await batch(deletes: [id], posts: [body]);
    if (result.posts.isEmpty) throw const CfProtocolException('The batch answer had no new record.');
    return result.posts.first;
  }

  Future<DnsBatchResult> batch({
    List<String> deletes = const [],
    List<Map<String, dynamic>> patches = const [],
    List<Map<String, dynamic>> posts = const [],
  }) async {
    final res = await client.post(
      '$_base/batch',
      data: {
        if (deletes.isNotEmpty)
          'deletes': [
            for (final id in deletes) {'id': id},
          ],
        if (patches.isNotEmpty) 'patches': patches,
        if (posts.isNotEmpty) 'posts': posts,
      },
    );
    final r = res.result;
    return r is Map<String, dynamic> ? DnsBatchResult.fromJson(r) : const DnsBatchResult();
  }

  Future<void> delete(String id) async {
    await client.delete('$_base/$id');
  }

  /// Undo for a delete: creates the record again with its old settings. The
  /// new record gets a new id.
  Future<DnsRecord> recreate(DnsRecord deleted) => create(deleted.toCreateBody());

  /// BIND zone file of every record in the zone.
  Future<String> exportBind() => client.getText('$_base/export');

  /// Uploads a BIND zone file (multipart field `file`). [proxied] sets the
  /// proxy state of proxiable records that carry no `cf-proxied` tag.
  Future<DnsImportResult> importBind(Uint8List bytes, {required String filename, bool proxied = false}) async {
    if (bytes.length > maxImportBytes) {
      throw CfApiException(statusCode: 413, errors: const [], fallback: 'Zone file over 256 KiB');
    }
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename, contentType: DioMediaType('text', 'plain')),
      'proxied': proxied ? 'true' : 'false',
    });
    final res = await client.post('$_base/import', data: form);
    final r = res.result;
    return r is Map<String, dynamic> ? DnsImportResult.fromJson(r) : const DnsImportResult(added: 0, parsed: 0);
  }
}
