import 'mail_models.dart';

/// Content-ID of a domain's logo in outgoing HTML; the mail service attaches
/// the image inline under it (`SendRequest.brandLogo`).
const kBrandLogoCid = 'logo@edgepost';

/// One message's signature: its text (the domain's, possibly edited for this
/// message) and the domain's logo when it goes along.
class SignatureBlock {
  const SignatureBlock({this.text = '', this.logo});

  final String text;
  final BrandLogo? logo;

  bool get isEmpty => text.trim().isEmpty && logo == null;
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

final _link = RegExp(r'(https?://[^\s<]+[^\s<.,;:!?)\]]|www\.[^\s<]+[^\s<.,;:!?)\]]|[\w.+-]+@[\w-]+(\.[\w-]+)+)');

/// Escapes [line] and turns web addresses and email addresses into links.
String linkify(String line) {
  final out = StringBuffer();
  var at = 0;
  for (final m in _link.allMatches(line)) {
    out.write(_escape(line.substring(at, m.start)));
    final shown = m.group(0)!;
    final href = shown.contains('@') && !shown.contains('/')
        ? 'mailto:$shown'
        : (shown.startsWith('www.') ? 'https://$shown' : shown);
    out.write('<a href="${_escape(href)}" style="color:#2557d6;text-decoration:none">${_escape(shown)}</a>');
    at = m.end;
  }
  out.write(_escape(line.substring(at)));
  return out.toString();
}

/// The signature for the text part, after the standard "-- " delimiter
/// (RFC 3676), or empty.
String signatureText(SignatureBlock s) {
  final t = s.text.trim();
  return t.isEmpty ? '' : '-- \n$t';
}

/// The signature for the HTML part: the logo (inline, by Content-ID) above
/// the lines, in a presentation table mail clients render consistently.
/// [logoSrc] replaces the `cid:` source (a `data:` URI for previews).
String signatureHtml(SignatureBlock s, {String? logoSrc}) {
  if (s.isEmpty) return '';
  final lines = s.text.trim().isEmpty ? const <String>[] : s.text.trim().replaceAll('\r\n', '\n').split('\n');
  final logo = s.logo;
  final img = logo == null
      ? ''
      : '<img src="${logoSrc ?? 'cid:$kBrandLogoCid'}" width="${logo.shown.$1.toInt()}" height="${logo.shown.$2.toInt()}" alt="" '
            'style="display:block;border:0;outline:none;margin:0 0 ${lines.isEmpty ? 0 : 10}px">';
  final text = lines.map(linkify).join('<br>');
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:20px;border-collapse:collapse">'
      '<tr><td style="font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,Helvetica,Arial,sans-serif;'
      'font-size:14px;line-height:1.45;color:#5b606a">$img$text</td></tr></table>';
}
