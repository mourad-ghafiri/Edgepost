export '../../support/memory_cache.dart';

/// Shapes copied from the examples in the official API reference
/// (https://developers.cloudflare.com/api/resources/email_routing/), with ids
/// kept and zone-specific values adapted to example.com.
Map<String, dynamic> settingsJson({bool enabled = true, String status = 'ready'}) => {
      'id': '75610dab9e69410a82cf7e400a09ecec',
      'enabled': enabled,
      'name': 'example.com',
      'created': '2014-01-02T02:20:00Z',
      'modified': '2014-01-02T02:20:00Z',
      'skip_wizard': true,
      'status': status,
      'support_subaddress': true,
      'tag': '75610dab9e69410a82cf7e400a09ecec',
    };

Map<String, dynamic> forwardRuleJson({
  String id = 'a7e6fb77503c41d8a7f3113c6918f10c',
  String to = 'test@example.com',
  String dest = 'destinationaddress@example.net',
  bool enabled = true,
}) =>
    {
      'id': id,
      'actions': [
        {
          'type': 'forward',
          'value': [dest],
        },
      ],
      'enabled': enabled,
      'matchers': [
        {'type': 'literal', 'field': 'to', 'value': to},
      ],
      'name': 'Send to user@example.net rule.',
      'priority': 0,
      'source': 'api',
      'tag': id,
    };

Map<String, dynamic> workerRuleJson({required String id, required String to, String worker = 'edgepost-mail'}) => {
      'id': id,
      'actions': [
        {
          'type': 'worker',
          'value': [worker],
        },
      ],
      'enabled': true,
      'matchers': [
        {'type': 'literal', 'field': 'to', 'value': to},
      ],
      'name': '',
      'priority': 0,
      'source': 'api',
    };

Map<String, dynamic> catchAllJson({String type = 'forward', String? value = 'destinationaddress@example.net', bool enabled = true}) => {
      'id': 'a7e6fb77503c41d8a7f3113c6918f10c',
      'actions': [
        {
          'type': type,
          'value': ?(value == null ? null : [value]),
        },
      ],
      'enabled': enabled,
      'matchers': [
        {'type': 'all'},
      ],
      'name': 'Send to user@example.net rule.',
      'source': 'api',
      'tag': 'a7e6fb77503c41d8a7f3113c6918f10c',
    };

Map<String, dynamic> addressJson({
  String id = 'ea95132c15732412d22c1476fa83f27a',
  String email = 'user@example.com',
  String? verified = '2014-01-02T02:20:00Z',
}) =>
    {
      'id': id,
      'created': '2014-01-02T02:20:00Z',
      'email': email,
      'modified': '2014-01-02T02:20:00Z',
      'tag': id,
      'verified': verified,
    };

List<Map<String, dynamic>> routingDnsJson() => [
      {'content': 'route1.mx.cloudflare.net', 'name': 'example.com', 'priority': 12, 'ttl': 1, 'type': 'MX'},
      {'content': 'route2.mx.cloudflare.net', 'name': 'example.com', 'priority': 40, 'ttl': 1, 'type': 'MX'},
      {'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all', 'name': 'example.com', 'ttl': 1, 'type': 'TXT'},
    ];

Map<String, dynamic> pageInfo(int count) =>
    {'page': 1, 'per_page': 50, 'count': count, 'total_count': count, 'total_pages': 1};
