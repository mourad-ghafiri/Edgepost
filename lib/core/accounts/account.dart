import 'package:flutter/widgets.dart' show StringCharacters;

/// A Cloudflare account the user added to Edgepost: the unit the app shows
/// and switches between. API tokens are the keys that reach it.
class Account {
  const Account({required this.id, required this.cloudflareName, required this.colorIndex, this.nickname});

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        cloudflareName: j['cloudflareName'] as String,
        colorIndex: (j['colorIndex'] as num).toInt(),
        nickname: j['nickname'] as String?,
      );

  final String id;

  /// The name Cloudflare gives the account ("jane@example.com's Account").
  final String cloudflareName;

  /// The user's own name for it, when they set one.
  final String? nickname;

  /// Index into the account palette, fixed when the account is added.
  final int colorIndex;

  String get name => nickname ?? cloudflareName;
  String get initials => accountInitials(name);

  Account copyWith({String? cloudflareName, String? nickname, bool clearNickname = false}) => Account(
        id: id,
        cloudflareName: cloudflareName ?? this.cloudflareName,
        colorIndex: colorIndex,
        nickname: clearNickname ? null : (nickname ?? this.nickname),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cloudflareName': cloudflareName,
        'colorIndex': colorIndex,
        'nickname': nickname,
      };
}

/// One or two letters for an account's avatar. Cloudflare's default names
/// ("jane.doe@example.com's Account") become "JD"; "Atelier Nord" becomes "AN".
String accountInitials(String name) {
  var s = name.trim().replaceAll(RegExp(r"['’]s\s+account$", caseSensitive: false), '');
  if (s.contains('@')) s = s.split('@').first;
  // Words start at their first letter or digit ("(Old) Studio" → "OS").
  final words = [
    for (final w in s.split(RegExp(r'[\s._\-+]+')))
      if (w.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '') case final t when t.isNotEmpty) t,
  ];
  final letters = [for (final w in words.take(2)) w.characters.first.toUpperCase()].join();
  return letters.isEmpty ? '?' : letters;
}
