import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/models.dart';

enum MailDnsIssueKind { duplicateDmarc, duplicateSpf }

/// More than one DMARC or SPF record at one name: receivers then treat the
/// policy as invalid (one DMARC record per domain, one SPF record per name).
class MailDnsIssue {
  const MailDnsIssue({required this.zone, required this.kind, required this.name, required this.records});

  final Zone zone;
  final MailDnsIssueKind kind;

  /// Record name holding the duplicates (e.g. `_dmarc.example.com`).
  final String name;

  /// The duplicate records as returned by the API (id, content, created_on…).
  final List<Map<String, dynamic>> records;
}

/// Scans a zone's TXT records for duplicate DMARC and SPF policies. One read
/// per zone (DNS reads are free; they only count toward the API rate limit).
Future<List<MailDnsIssue>> checkMailDns(CfClient client, Zone zone) async {
  final txt = await client.getAll('/zones/${zone.id}/dns_records', query: {'type': 'TXT'}, perPage: 100);
  String content(Map<String, dynamic> r) => '${r['content']}'.replaceAll('"', '').trim().toLowerCase();
  String name(Map<String, dynamic> r) => '${r['name']}'.toLowerCase();

  final issues = <MailDnsIssue>[];
  final dmarcName = '_dmarc.${zone.name}'.toLowerCase();
  final dmarc = txt.where((r) => name(r) == dmarcName && content(r).startsWith('v=dmarc1')).toList();
  if (dmarc.length > 1) {
    issues.add(MailDnsIssue(zone: zone, kind: MailDnsIssueKind.duplicateDmarc, name: dmarcName, records: dmarc));
  }
  final spfByName = <String, List<Map<String, dynamic>>>{};
  for (final r in txt.where((r) => content(r).startsWith('v=spf1'))) {
    spfByName.putIfAbsent(name(r), () => []).add(r);
  }
  for (final e in spfByName.entries.where((e) => e.value.length > 1)) {
    issues.add(MailDnsIssue(zone: zone, kind: MailDnsIssueKind.duplicateSpf, name: e.key, records: e.value));
  }
  return issues;
}
