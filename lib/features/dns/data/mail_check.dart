import 'dns_record.dart';

enum MailCheckKind { mx, spf, dmarc, dkim }

enum MailCheckStatus { ok, warn, missing }

/// The specific finding, so the screen can give plain-language advice.
enum MailCheckFinding {
  mxOk,
  mxEmailRouting,
  mxNull,
  mxMissing,
  spfOk,
  spfMultiple,
  spfPassAll,
  spfMissing,
  dmarcOk,
  dmarcMonitorOnly,
  dmarcMultiple,
  dmarcMissing,
  dkimOk,
  dkimMissing,
}

class MailCheckItem {
  const MailCheckItem(this.kind, this.status, this.finding, this.records);
  final MailCheckKind kind;
  final MailCheckStatus status;
  final MailCheckFinding finding;
  final List<DnsRecord> records;
}

/// Reads the zone's records and reports MX, SPF, DMARC and DKIM, without any
/// extra API call. SPF and DMARC are looked up as TXT values; DKIM as TXT or
/// CNAME records under `_domainkey`.
List<MailCheckItem> checkMailRecords(List<DnsRecord> records, String zone) {
  final apex = zone.toLowerCase();
  String n(DnsRecord r) => r.name.toLowerCase();
  bool txtStarts(DnsRecord r, String prefix) =>
      r.type == 'TXT' && txtValue(r.content).trimLeft().toLowerCase().startsWith(prefix);

  // MX
  final mx = records.where((r) => r.type == 'MX' && n(r) == apex).toList()
    ..sort((a, b) => (a.priority ?? 0).compareTo(b.priority ?? 0));
  final MailCheckItem mxItem;
  if (mx.isEmpty) {
    mxItem = MailCheckItem(MailCheckKind.mx, MailCheckStatus.missing, MailCheckFinding.mxMissing, mx);
  } else if (mx.length == 1 && (mx.first.content.trim() == '.' || mx.first.content.trim().isEmpty)) {
    mxItem = MailCheckItem(MailCheckKind.mx, MailCheckStatus.warn, MailCheckFinding.mxNull, mx);
  } else if (mx.every((r) => r.content.toLowerCase().endsWith('.mx.cloudflare.net'))) {
    mxItem = MailCheckItem(MailCheckKind.mx, MailCheckStatus.ok, MailCheckFinding.mxEmailRouting, mx);
  } else {
    mxItem = MailCheckItem(MailCheckKind.mx, MailCheckStatus.ok, MailCheckFinding.mxOk, mx);
  }

  // SPF
  final spf = records.where((r) => n(r) == apex && txtStarts(r, 'v=spf1')).toList();
  final MailCheckItem spfItem;
  if (spf.isEmpty) {
    spfItem = MailCheckItem(MailCheckKind.spf, MailCheckStatus.missing, MailCheckFinding.spfMissing, spf);
  } else if (spf.length > 1) {
    spfItem = MailCheckItem(MailCheckKind.spf, MailCheckStatus.warn, MailCheckFinding.spfMultiple, spf);
  } else if (RegExp(r'(^|\s)\+?all(\s|$)').hasMatch(txtValue(spf.first.content).toLowerCase())) {
    spfItem = MailCheckItem(MailCheckKind.spf, MailCheckStatus.warn, MailCheckFinding.spfPassAll, spf);
  } else {
    spfItem = MailCheckItem(MailCheckKind.spf, MailCheckStatus.ok, MailCheckFinding.spfOk, spf);
  }

  // DMARC
  final dmarc = records.where((r) => n(r) == '_dmarc.$apex' && txtStarts(r, 'v=dmarc1')).toList();
  final MailCheckItem dmarcItem;
  if (dmarc.isEmpty) {
    dmarcItem = MailCheckItem(MailCheckKind.dmarc, MailCheckStatus.missing, MailCheckFinding.dmarcMissing, dmarc);
  } else if (dmarc.length > 1) {
    dmarcItem = MailCheckItem(MailCheckKind.dmarc, MailCheckStatus.warn, MailCheckFinding.dmarcMultiple, dmarc);
  } else if (RegExp(r'(^|;)\s*p\s*=\s*none\s*(;|$)').hasMatch(txtValue(dmarc.first.content).toLowerCase())) {
    dmarcItem = MailCheckItem(MailCheckKind.dmarc, MailCheckStatus.warn, MailCheckFinding.dmarcMonitorOnly, dmarc);
  } else {
    dmarcItem = MailCheckItem(MailCheckKind.dmarc, MailCheckStatus.ok, MailCheckFinding.dmarcOk, dmarc);
  }

  // DKIM
  final dkim = records
      .where((r) => (r.type == 'TXT' || r.type == 'CNAME') && n(r).endsWith('._domainkey.$apex'))
      .toList();
  final dkimItem = dkim.isEmpty
      ? MailCheckItem(MailCheckKind.dkim, MailCheckStatus.missing, MailCheckFinding.dkimMissing, dkim)
      : MailCheckItem(MailCheckKind.dkim, MailCheckStatus.ok, MailCheckFinding.dkimOk, dkim);

  return [mxItem, spfItem, dmarcItem, dkimItem];
}
