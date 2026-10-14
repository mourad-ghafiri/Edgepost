// Fixtures shaped like the examples in the official Cloudflare API reference
// (https://developers.cloudflare.com/api/resources/workers/,
// https://developers.cloudflare.com/api/resources/pages/,
// https://developers.cloudflare.com/api/resources/registrar/), with IDs and
// names made up for the tests.
import 'package:edgepost/core/accounts/account.dart';
import 'package:edgepost/core/accounts/credential.dart';

import '../../support/accounts.dart';

/// A token reaching [accounts], granted exactly [caps] there (everything
/// else denied).
Credential token(
  String id, {
  List<Account> accounts = const [testAccount],
  TokenKind kind = TokenKind.user,
  Set<Capability> caps = const {Capability.workers, Capability.pages, Capability.registrar},
}) =>
    fakeToken(id: id, label: id, kind: kind, accounts: accounts, caps: {for (final c in Capability.values) c: caps.contains(c)});

Map<String, dynamic> scriptJson(String name, {String modified = '2026-10-10T08:00:00Z', int routes = 1}) => {
  'id': name,
  'created_on': '2026-01-05T10:00:00Z',
  'modified_on': modified,
  'compatibility_date': '2026-09-01',
  'compatibility_flags': ['nodejs_compat'],
  'etag': 'ea95132c15732412d22c1476fa83f27a',
  'handlers': ['fetch', 'scheduled'],
  'has_assets': false,
  'has_modules': true,
  'last_deployed_from': 'wrangler',
  'logpush': false,
  'placement': {'mode': 'smart'},
  'tail_consumers': [
    {'service': 'my-log-consumer'},
  ],
  'usage_model': 'standard',
  'routes': [
    for (var i = 0; i < routes; i++)
      {'id': '023e105f4ecef8ad9ca31a8372d0c35$i', 'pattern': 'example.com/api$i/*', 'script': name},
  ],
};

Map<String, dynamic> pagesDeploymentJson({
  String id = 'f64788e9-fccd-4d4a-a28a-cb84f88f6f1d',
  String shortId = 'f64788e9',
  String branch = 'main',
  String environment = 'production',
  String stage = 'deploy',
  String status = 'success',
  String created = '2026-10-12T07:00:00Z',
  String ended = '2026-10-12T07:02:30Z',
  String message = 'Update index.html\n\nLonger body',
}) => {
  'id': id,
  'short_id': shortId,
  'project_id': '7b162ea7-7367-4d67-bcde-1160995d5',
  'project_name': 'docs-site',
  'environment': environment,
  'url': 'https://$shortId.docs-site.pages.dev',
  'created_on': created,
  'modified_on': ended,
  'aliases': ['https://$branch.docs-site.pages.dev'],
  'latest_stage': {'name': stage, 'started_on': created, 'ended_on': ended, 'status': status},
  'env_vars': {
    'API_KEY': {'type': 'secret_text', 'value': ''},
  },
  'deployment_trigger': {
    'type': 'github:push',
    'metadata': {
      'branch': branch,
      'commit_hash': 'ad9ccd918a81025731e10e40267e11273a263421',
      'commit_message': message,
      'commit_dirty': false,
    },
  },
  'stages': [
    {'name': 'queued', 'started_on': created, 'ended_on': created, 'status': 'success'},
    {'name': 'initialize', 'started_on': created, 'ended_on': created, 'status': 'success'},
    {'name': 'clone_repo', 'started_on': created, 'ended_on': created, 'status': 'success'},
    {'name': 'build', 'started_on': created, 'ended_on': ended, 'status': stage == 'build' ? status : 'success'},
    {'name': 'deploy', 'started_on': ended, 'ended_on': ended, 'status': stage == 'deploy' ? status : 'idle'},
  ],
  'build_config': {
    'build_caching': true,
    'build_command': 'npm run build',
    'destination_dir': 'build',
    'root_dir': '/',
    'web_analytics_tag': 'cee1c73f6e4743d0b5a6bb1e5f3cb4ef',
    'web_analytics_token': '021e1057c18547eca7b79f2516f06o7x',
  },
  'source': {
    'type': 'github',
    'config': {'owner': 'example', 'repo_name': 'docs', 'production_branch': 'main'},
  },
  'is_skipped': false,
};

Map<String, dynamic> pagesProjectJson(String name, {Map<String, dynamic>? latest, Map<String, dynamic>? canonical}) => {
  'id': '7b162ea7-7367-4d67-bcde-1160995d5',
  'name': name,
  'subdomain': '$name.pages.dev',
  'domains': ['$name.example.com'],
  'production_branch': 'main',
  'created_on': '2025-04-20T19:35:29Z',
  'canonical_deployment': canonical ?? pagesDeploymentJson(),
  'latest_deployment': latest ?? pagesDeploymentJson(),
  'source': {
    'type': 'github',
    'config': {'owner': 'example', 'repo_name': name, 'production_branch': 'main'},
  },
  'build_config': {'build_command': 'npm run build', 'destination_dir': 'build'},
  'uses_functions': false,
};

Map<String, dynamic> registrationJson(
  String domain, {
  required String expires,
  bool autoRenew = false,
  String status = 'active',
}) => {
  'domain_name': domain,
  'status': status,
  'created_at': '2025-10-27T10:00:00Z',
  'expires_at': expires,
  'auto_renew': autoRenew,
  'privacy_mode': 'redaction',
  'locked': true,
};

Map<String, dynamic> resultInfo({int page = 1, int totalPages = 1, int count = 1}) => {
  'page': page,
  'per_page': 10,
  'total_pages': totalPages,
  'count': count,
  'total_count': count,
};
