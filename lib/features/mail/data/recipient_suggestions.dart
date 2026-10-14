import 'dart:math';
import 'dart:ui' show Locale;

import 'mail_models.dart';
import 'mail_domains.dart';

/// What a recipient suggestion offers.
enum SuggestionKind {
  /// Someone you've sent to.
  contact,

  /// What's typed, at a known mail domain ("lena@gm" → lena@gmail.com).
  domain,

  /// A likely typo, fixed ("lena@gmial.com" → lena@gmail.com).
  correction,
}

class RecipientSuggestion {
  const RecipientSuggestion(this.address, this.kind, {this.typedDomain});

  final MailAddress address;
  final SuggestionKind kind;

  /// For a [SuggestionKind.correction]: the domain as typed.
  final String? typedDomain;
}

/// How strongly a contact is suggested: messages sent to it, halving every
/// 60 days since the last one, so someone written to often long ago fades
/// behind someone written to this week.
double frecency(MailContact c, DateTime now) {
  final days = max(0, now.difference(c.lastSent).inMinutes) / (60 * 24);
  return c.count * pow(0.5, days / 60).toDouble();
}

/// Suggestions for one compose screen: the people sent to and the mail
/// domains worth completing, minus the addresses already on the message.
class RecipientSuggestions {
  RecipientSuggestions({
    required List<MailContact> contacts,
    required List<Locale> locales,
    required Set<String> exclude,
    DateTime? now,
  }) : _now = now ?? DateTime.now(),
       _exclude = {for (final e in exclude) e.toLowerCase()} {
    _contacts = [
      for (final c in contacts)
        if (!_exclude.contains(c.address)) c,
    ]..sort((a, b) => frecency(b, _now).compareTo(frecency(a, _now)));
    // Domains you've written to first, by how much; then the five giants,
    // then the ones common where you are, then the rest of the world's.
    final weight = <String, double>{};
    for (final c in contacts) {
      weight.update(c.domain, (w) => w + frecency(c, _now), ifAbsent: () => frecency(c, _now));
    }
    final yours = weight.keys.toList()..sort((a, b) => weight[b]!.compareTo(weight[a]!));
    _domains = {
      ...yours,
      ...kGlobalMailDomains.take(5),
      ...regionalMailDomains(locales),
      ...kGlobalMailDomains,
    }.toList();
    _known = {..._domains, ...kAllMailDomains};
  }

  final DateTime _now;
  final Set<String> _exclude;
  late final List<MailContact> _contacts;
  late final List<String> _domains;
  late final Set<String> _known;

  /// For an empty field: the people sent to most, for a tap.
  List<MailAddress> quickPicks({int limit = 8}) => [for (final c in _contacts.take(limit)) c.mail];

  /// For what's typed: matching people, then completions of the domain after
  /// "@" (three at most: a short list, not a directory), with a typo fix
  /// first when the domain looks mistyped.
  List<RecipientSuggestion> forInput(String input, {int limit = 4}) {
    final typed = input.trim();
    final q = typed.toLowerCase();
    if (q.isEmpty) return const [];

    final people = <(int, MailContact)>[
      for (final c in _contacts)
        if (_tier(c, q) case final int t) (t, c),
    ];
    // Stable: equal tiers keep frecency order.
    _stableSort(people, compare: (a, b) => a.$1.compareTo(b.$1));
    final contacts = [for (final (_, c) in people) RecipientSuggestion(c.mail, SuggestionKind.contact)];

    final at = q.indexOf('@');
    if (at <= 0 || q.indexOf('@', at + 1) >= 0) return contacts.take(limit).toList();
    final local = typed.substring(0, at);
    if (!MailAddress.isValidEmail('$local@x.io')) return contacts.take(limit).toList();
    final domain = q.substring(at + 1);
    final shown = {for (final c in contacts) c.address.address};

    final completions = <RecipientSuggestion>[
      for (final d in _domains)
        if (d.startsWith(domain) && d != domain && !_exclude.contains('$local@$d'.toLowerCase()))
          if (!shown.contains('$local@$d'.toLowerCase()))
            RecipientSuggestion(MailAddress('$local@$d'), SuggestionKind.domain),
    ];

    RecipientSuggestion? fix;
    if (completions.isEmpty && domain.contains('.') && !_known.contains(domain)) {
      final best = closestMailDomain(domain, _domains, _known);
      if (best != null && !_exclude.contains('$local@$best'.toLowerCase())) {
        fix = RecipientSuggestion(MailAddress('$local@$best'), SuggestionKind.correction, typedDomain: domain);
      }
    }

    // People first, but leave room for a couple of completions.
    final room = limit - (fix == null ? 0 : 1);
    final keepPeople = min(contacts.length, max(0, room - min(2, completions.length)).toInt());
    return [
      ?fix,
      ...contacts.take(keepPeople),
      ...completions.take(min(3, room - keepPeople)),
    ];
  }

  /// How well [c] matches [q] (lower-case): lower is better, null is no match.
  static int? _tier(MailContact c, String q) {
    if (c.address.startsWith(q)) return 0;
    final name = foldDiacritics(c.name?.toLowerCase() ?? '');
    final fq = foldDiacritics(q);
    if (name.startsWith(fq) || name.split(RegExp(r'[\s\-.]+')).any((w) => w.startsWith(fq))) return 1;
    final local = c.address.split('@').first;
    if (!q.contains('@') && local.split(RegExp(r'[._\-+]')).any((p) => p.startsWith(q))) return 2;
    if (q.length >= 3 && c.address.contains(q)) return 3;
    return null;
  }
}

/// The known domain [typed] most likely meant, within one edit (two for
/// longer ones), or null. Prefers [ordered] domains on a tie.
String? closestMailDomain(String typed, List<String> ordered, Set<String> known) {
  final limit = typed.length >= 9 ? 2 : 1;
  String? best;
  var bestDistance = limit + 1;
  for (final d in [...ordered, ...known.where((k) => !ordered.contains(k))]) {
    if ((d.length - typed.length).abs() > limit) continue;
    final distance = editDistance(typed, d);
    if (distance < bestDistance) {
      best = d;
      bestDistance = distance;
    }
  }
  return bestDistance <= limit ? best : null;
}

/// Edits (insert, delete, replace, swap two neighbours) from [a] to [b].
int editDistance(String a, String b) {
  final d = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      d[i][j] = min(min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return d[a.length][b.length];
}

// One to one, letter by letter.
const _accented = 'àáâãäåāçćčèéêëēěìíîïīñńňòóôõöøōùúûüūůýÿžźżšśłřďťğış';
const _plain = 'aaaaaaaccceeeeeeiiiiinnnooooooouuuuuuyyzzzsslrdtgis';

/// Lower-case Latin letters without their accents, so "helene" finds Hélène.
String foldDiacritics(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _accented.indexOf(ch);
    out.write(i < 0 ? ch : _plain[i]);
  }
  return out.toString();
}

/// Stable insertion sort (`List.sort` may reorder equals; lists here are
/// short).
void _stableSort<T>(List<T> list, {required int Function(T, T) compare}) {
  for (var i = 1; i < list.length; i++) {
    final x = list[i];
    var j = i - 1;
    while (j >= 0 && compare(list[j], x) > 0) {
      list[j + 1] = list[j];
      j--;
    }
    list[j + 1] = x;
  }
}
