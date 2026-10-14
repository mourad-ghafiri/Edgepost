import '../cloudflare/cf_client.dart';
import '../cloudflare/cf_errors.dart';
import '../cloudflare/models.dart';
import 'credential.dart';

class TokenCheck {
  const TokenCheck({required this.kind, required this.accounts, this.expiresOn});
  final TokenKind kind;
  final List<CfAccount> accounts;
  final DateTime? expiresOn;
}

/// Verifies a pasted token and discovers which accounts it reaches.
///
/// User tokens answer `GET /user/tokens/verify`; account-owned tokens answer
/// `GET /accounts/{id}/tokens/verify` instead
/// (https://developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/verify/).
class TokenVerifier {
  const TokenVerifier(this.client);
  final CfClient client;

  Future<TokenCheck> verify() async {
    DateTime? expiresOn;
    var kind = TokenKind.user;
    Map<String, dynamic>? userResult;
    try {
      userResult = (await client.get('/user/tokens/verify')).map;
    } on CfAuthException {
      kind = TokenKind.account;
    } on CfApiException catch (e) {
      if (e.statusCode >= 500) rethrow;
      kind = TokenKind.account;
    }
    if (userResult != null) {
      _ensureActive(userResult);
      expiresOn = parseCfDate(userResult['expires_on']);
    }

    var accounts = (await client.getAll('/accounts')).map(CfAccount.fromJson).toList();
    // A token limited to zones lists no accounts; its zones name them.
    if (accounts.isEmpty) {
      accounts = {
        for (final z in await client.getAll('/zones')) CfAccount.fromJson(z['account'] as Map<String, dynamic>),
      }.toList();
    }

    if (kind == TokenKind.account) {
      if (accounts.isEmpty) throw const CfAuthException();
      final res = await client.get('/accounts/${accounts.first.id}/tokens/verify');
      _ensureActive(res.map);
      expiresOn = parseCfDate(res.map['expires_on']);
    }
    return TokenCheck(kind: kind, accounts: accounts, expiresOn: expiresOn);
  }

  /// Current expiry date of a token already added (null = no expiry): one
  /// verify call, so a date changed in the dashboard shows up in the app.
  Future<DateTime?> expiry(TokenKind kind, List<CfAccount> accounts) async {
    final path = kind == TokenKind.user || accounts.isEmpty
        ? '/user/tokens/verify'
        : '/accounts/${accounts.first.id}/tokens/verify';
    return parseCfDate((await client.get(path)).map['expires_on']);
  }

  static void _ensureActive(Map<String, dynamic> result) {
    final status = result['status'];
    if (status != null && status != 'active') {
      throw CfAuthException('This token is $status.');
    }
  }
}
