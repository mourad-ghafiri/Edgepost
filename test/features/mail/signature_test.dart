import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/data/reply_builder.dart';
import 'package:edgepost/features/mail/data/signature.dart';
import 'package:flutter_test/flutter_test.dart';

const _logo = BrandLogo(width: 480, height: 96, size: 2048, updatedAt: '2026-10-13T00:00:00Z');
const _me = MailAddress('contact@atelier-nord.dev', 'Atelier Nord');
const _carol = MailAddress('carol@client.example');

void main() {
  group('signature', () {
    test('the text part uses the standard "-- " delimiter; an empty one adds nothing', () {
      expect(signatureText(const SignatureBlock(text: '  Mourad\nAtelier Nord  ')), '-- \nMourad\nAtelier Nord');
      expect(signatureText(const SignatureBlock(text: '   ', logo: _logo)), '');
    });

    test('the HTML part escapes the text and links web and email addresses', () {
      final html = signatureHtml(const SignatureBlock(text: 'Mourad <founder>\natelier-nord.dev · www.atelier-nord.dev\nhello@atelier-nord.dev'));
      expect(html, contains('Mourad &lt;founder&gt;'));
      expect(html, contains('<a href="https://www.atelier-nord.dev"'));
      expect(html, contains('<a href="mailto:hello@atelier-nord.dev"'));
      expect(html, isNot(contains('<img')));
      expect(linkify('see https://example.com/a?b=1.'), contains('href="https://example.com/a?b=1"'), reason: 'trailing dot stays text');
    });

    test('the logo is the inline image, at half its pixels within 240 × 48', () {
      final html = signatureHtml(const SignatureBlock(text: 'Mourad', logo: _logo));
      expect(html, contains('src="cid:$kBrandLogoCid" width="240" height="48"'));
      expect(const BrandLogo(width: 100, height: 40, size: 1, updatedAt: '').shown, (50.0, 20.0));
      expect(const BrandLogo(width: 2000, height: 100, size: 1, updatedAt: '').shown, (240.0, 12.0));
      expect(signatureHtml(const SignatureBlock(text: 'x', logo: _logo), logoSrc: 'data:image/png;base64,AA'), contains('src="data:image/png;base64,AA"'));
    });
  });

  group('the message', () {
    const draft = ComposeDraft(
      mode: ComposeMode.reply,
      accountId: 'a1',
      from: _me,
      quotedText: 'On Mon, Lena wrote:\n> Hi',
      quotedHtml: '<blockquote>Hi</blockquote>',
    );

    SendRequest build(SignatureBlock s, {bool quote = true}) => draft.toRequest(
          from: _me,
          to: const [_carol],
          cc: const [],
          bcc: const [],
          subject: 'Re: Hi',
          body: 'Paid today.\n',
          signature: s,
          includeQuote: quote,
        );

    test('the signature sits between the reply and the quoted original, in both parts', () {
      final r = build(const SignatureBlock(text: 'Mourad', logo: _logo));
      expect(r.text, 'Paid today.\n\n-- \nMourad\n\nOn Mon, Lena wrote:\n> Hi');
      final html = r.html!;
      expect(html.indexOf('Paid today.'), lessThan(html.indexOf('cid:$kBrandLogoCid')));
      expect(html.indexOf('cid:$kBrandLogoCid'), lessThan(html.indexOf('<blockquote>')));
      expect(r.brandLogo, isTrue, reason: 'the service attaches the logo');
    });

    test('a signature makes a new message HTML too; no signature keeps it plain text', () {
      const plain = ComposeDraft(mode: ComposeMode.compose, accountId: 'a1', from: _me);
      SendRequest send(SignatureBlock s) =>
          plain.toRequest(from: _me, to: const [_carol], cc: const [], bcc: const [], subject: 'Hi', body: 'Hello', signature: s);
      expect(send(const SignatureBlock()).html, isNull);
      expect(send(const SignatureBlock()).brandLogo, isFalse);
      final signed = send(const SignatureBlock(text: 'Mourad'));
      expect(signed.html, contains('Mourad'));
      expect(signed.brandLogo, isFalse, reason: 'no logo, nothing to attach');
    });

    test('without the quote, nothing of the original goes', () {
      final r = build(const SignatureBlock(text: 'Mourad'), quote: false);
      expect(r.text, 'Paid today.\n\n-- \nMourad');
      expect(r.html, isNot(contains('blockquote')));
    });
  });

  test('cid: images become the data URIs the reader can show', () {
    const html = '<p>Hi</p><img src="cid:logo@edgepost"><img src="cid:other@x">';
    final out = resolveInlineImages(html, {'logo@edgepost': 'data:image/png;base64,AA'});
    expect(out, contains('src="data:image/png;base64,AA"'));
    expect(out, contains('src="cid:other@x"'), reason: 'unknown ids stay as they are');
    expect(resolveInlineImages(html, const {}), html);
  });
}
