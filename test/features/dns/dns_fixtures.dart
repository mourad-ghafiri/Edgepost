// Fixtures shaped like the official examples in
// https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/list/
// (record fields, `meta`, `settings`, timestamps) with realistic values.

Map<String, dynamic> aRecordJson({String id = '023e105f4ecef8ad9ca31a8372d0c353'}) => {
  'id': id,
  'name': 'example.com',
  'type': 'A',
  'content': '198.51.100.4',
  'proxiable': true,
  'proxied': true,
  'ttl': 1,
  'settings': <String, dynamic>{},
  'meta': <String, dynamic>{},
  'comment': 'Domain verification record',
  'tags': ['owner:dns-team'],
  'created_on': '2014-01-01T05:20:00.12345Z',
  'modified_on': '2014-01-01T05:20:00.12345Z',
  'comment_modified_on': '2024-01-01T05:20:00.12345Z',
  'tags_modified_on': '2025-01-01T05:20:00.12345Z',
};

Map<String, dynamic> cnameJson({String id = 'rec-www'}) => {
  'id': id,
  'name': 'www.example.com',
  'type': 'CNAME',
  'content': 'example.com',
  'proxiable': true,
  'proxied': false,
  'ttl': 300,
  'settings': {'flatten_cname': false},
  'meta': <String, dynamic>{},
  'comment': null,
  'tags': <String>[],
  'created_on': '2025-03-01T10:00:00Z',
  'modified_on': '2025-03-01T10:00:00Z',
};

Map<String, dynamic> mxJson({String id = 'rec-mx'}) => {
  'id': id,
  'name': 'example.com',
  'type': 'MX',
  'content': 'route1.mx.cloudflare.net',
  'priority': 10,
  'proxiable': false,
  'proxied': false,
  'ttl': 3600,
  'settings': <String, dynamic>{},
  'meta': <String, dynamic>{},
  'tags': <String>[],
  'created_on': '2025-03-01T10:00:00Z',
  'modified_on': '2025-03-01T10:00:00Z',
};

Map<String, dynamic> txtJson({
  String id = 'rec-spf',
  String name = 'example.com',
  String content = '"v=spf1 include:_spf.mx.cloudflare.net ~all"',
}) => {
  'id': id,
  'name': name,
  'type': 'TXT',
  'content': content,
  'proxiable': false,
  'proxied': false,
  'ttl': 1,
  'settings': <String, dynamic>{},
  'meta': <String, dynamic>{},
  'tags': <String>[],
  'created_on': '2025-03-01T10:00:00Z',
  'modified_on': '2025-03-01T10:00:00Z',
};

Map<String, dynamic> srvJson({String id = 'rec-srv'}) => {
  'id': id,
  'name': '_sip._tcp.example.com',
  'type': 'SRV',
  'content': '5 5060 sip.example.com',
  'priority': 10,
  'data': {'priority': 10, 'weight': 5, 'port': 5060, 'target': 'sip.example.com'},
  'proxiable': false,
  'proxied': false,
  'ttl': 3600,
  'settings': <String, dynamic>{},
  'meta': <String, dynamic>{},
  'tags': <String>[],
  'created_on': '2025-03-01T10:00:00Z',
  'modified_on': '2025-03-01T10:00:00Z',
};

Map<String, dynamic> caaJson({String id = 'rec-caa'}) => {
  'id': id,
  'name': 'example.com',
  'type': 'CAA',
  'content': '0 issue "letsencrypt.org"',
  'data': {'flags': 0, 'tag': 'issue', 'value': 'letsencrypt.org'},
  'proxiable': false,
  'proxied': false,
  'ttl': 1,
  'settings': <String, dynamic>{},
  'meta': <String, dynamic>{},
  'tags': <String>[],
  'created_on': '2025-03-01T10:00:00Z',
  'modified_on': '2025-03-01T10:00:00Z',
};

/// List envelope `result_info`, one page.
Map<String, dynamic> onePage(int count) => {
  'page': 1,
  'per_page': 100,
  'count': count,
  'total_count': count,
  'total_pages': 1,
};
