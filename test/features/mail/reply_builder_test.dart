import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/reply_builder.dart';
import 'package:flutter_test/flutter_test.dart';

MessageDetail _msg({
  bool outgoing = false,
  String mailbox = 'hello@atelier-nord.dev',
  Map<String, dynamic>? from,
  List<Map<String, dynamic>> to = const [
    {'name': null, 'address': 'hello@atelier-nord.dev'},
  ],
  List<Map<String, dynamic>> cc = const [],
  List<Map<String, dynamic>> replyTo = const [],
  String subject = 'Invoice 2026-118',
  String? text = 'Hi,\n\nPlease find the invoice attached.\n\nLena',
  String? html,
  List<Map<String, dynamic>> attachments = const [],
}) =>
    MessageDetail.fromJson({
      'id': 'm1',
      'threadId': 't1',
      'folder': outgoing ? 'sent' : 'inbox',
      'direction': outgoing ? 'out' : 'in',
      'mailbox': mailbox,
      'domain': 'atelier-nord.dev',
      'from': from ?? {'name': 'Lena Varga', 'address': 'lena@varga.studio'},
      'to': to,
      'cc': cc,
      'replyTo': replyTo,
      'subject': subject,
      'snippet': '',
      'date': '2026-10-12T07:42:00Z',
      'receivedAt': '2026-10-12T07:42:03Z',
      'messageId': '<abc@varga.studio>',
      'inReplyTo': null,
      'references': <String>[],
      'read': false,
      'starred': false,
      'hasAttachments': attachments.isNotEmpty,
      'size': 2048,
      'text': text,
      'html': html,
      'attachments': attachments,
    }, accountId: 'acc1');

void main() {
  const own = {'hello@atelier-nord.dev', 'billing@atelier-nord.dev'};

  group('reply', () {
    test('goes to the sender, from the address it landed on, threaded to the parent', () {
      final d = buildDraft(_msg(), mode: ComposeMode.reply, ownAddresses: own);
      expect(d.to.map((a) => a.address), ['lena@varga.studio']);
      expect(d.cc, isEmpty);
      expect(d.from.address, 'hello@atelier-nord.dev');
      expect(d.subject, 'Re: Invoice 2026-118');
      expect(d.inReplyTo, 'm1');
      expect(d.forwardOf, isNull);
    });

    test('honours Reply-To', () {
      final d = buildDraft(
        _msg(replyTo: [
          {'name': 'Accounts', 'address': 'accounts@varga.studio'},
        ]),
        mode: ComposeMode.reply,
        ownAddresses: own,
      );
      expect(d.to.single.address, 'accounts@varga.studio');
    });

    test('a catch-all address becomes the From identity', () {
      final d = buildDraft(
        _msg(mailbox: 'anything-goes@atelier-nord.dev', to: [
          {'name': null, 'address': 'anything-goes@atelier-nord.dev'},
        ]),
        mode: ComposeMode.reply,
        ownAddresses: own,
        identities: const [MailAddress('hello@atelier-nord.dev', 'Atelier Nord')],
      );
      expect(d.from.address, 'anything-goes@atelier-nord.dev');
    });

    test('uses the named identity when one matches', () {
      final d = buildDraft(_msg(), mode: ComposeMode.reply, ownAddresses: own, identities: const [MailAddress('hello@atelier-nord.dev', 'Atelier Nord')]);
      expect(d.from.name, 'Atelier Nord');
    });

    test('replying to my own sent message goes back to its recipients', () {
      final d = buildDraft(
        _msg(
          outgoing: true,
          from: {'name': 'Atelier Nord', 'address': 'hello@atelier-nord.dev'},
          to: [
            {'name': 'Lena Varga', 'address': 'lena@varga.studio'},
          ],
        ),
        mode: ComposeMode.reply,
        ownAddresses: own,
      );
      expect(d.to.single.address, 'lena@varga.studio');
      expect(d.from.address, 'hello@atelier-nord.dev');
    });

    test('does not stack Re: prefixes, including localized ones', () {
      expect(prefixSubject('Re: Invoice', 'Re:'), 'Re: Invoice');
      expect(prefixSubject('RE: Invoice', 'Re:'), 'RE: Invoice');
      expect(prefixSubject('AW: Rechnung', 'Re:'), 'AW: Rechnung');
      expect(prefixSubject('Re[2]: Invoice', 'Re:'), 'Re[2]: Invoice');
      expect(prefixSubject('', 'Re:'), 'Re:');
      expect(prefixSubject('Fwd: Invoice', 'Fwd:'), 'Fwd: Invoice');
      expect(prefixSubject('TR: Facture', 'Fwd:'), 'TR: Facture');
    });

    test('quotes the original under an attribution line', () {
      final d = buildDraft(_msg(), mode: ComposeMode.reply, ownAddresses: own);
      expect(d.quotedText, contains('Lena Varga <lena@varga.studio> wrote:'));
      expect(d.quotedText, contains('> Please find the invoice attached.'));
      expect(d.quotedText.split('\n').skip(1).every((l) => l.startsWith('>')), isTrue);
      expect(d.quotedHtml, isNull, reason: 'plain-text parent stays plain text');
    });

    test('HTML parent is quoted in a blockquote with active content removed', () {
      final d = buildDraft(
        _msg(html: '<p onclick="x()">Hello</p><script>alert(1)</script><img src="https://t.example/p.gif">'),
        mode: ComposeMode.reply,
        ownAddresses: own,
      );
      expect(d.quotedHtml, contains('<blockquote'));
      expect(d.quotedHtml, isNot(contains('<script')));
      expect(d.quotedHtml, isNot(contains('onclick')));
    });
  });

  group('reply all', () {
    test('copies To and Cc minus my own addresses and the sender', () {
      final d = buildDraft(
        _msg(
          to: [
            {'name': null, 'address': 'hello@atelier-nord.dev'},
            {'name': 'Sam', 'address': 'sam@client.co'},
          ],
          cc: [
            {'name': null, 'address': 'billing@atelier-nord.dev'},
            {'name': 'Lena Varga', 'address': 'LENA@varga.studio'},
            {'name': 'Ops', 'address': 'ops@client.co'},
          ],
        ),
        mode: ComposeMode.replyAll,
        ownAddresses: own,
      );
      expect(d.to.map((a) => a.address), ['lena@varga.studio']);
      expect(d.cc.map((a) => a.address), ['sam@client.co', 'ops@client.co']);
    });
  });

  group('forward', () {
    test('empty recipients, Fwd: subject, header block, originals re-attached', () {
      final d = buildDraft(
        _msg(attachments: [
          {'id': 'a1', 'filename': 'invoice.pdf', 'mimeType': 'application/pdf', 'size': 120000, 'contentId': null, 'inline': false},
        ]),
        mode: ComposeMode.forward,
        ownAddresses: own,
      );
      expect(d.to, isEmpty);
      expect(d.subject, 'Fwd: Invoice 2026-118');
      expect(d.quotedText, startsWith('---------- Forwarded message ---------'));
      expect(d.quotedText, contains('From: Lena Varga <lena@varga.studio>'));
      expect(d.forwardOf, 'm1');
      expect(d.inReplyTo, isNull);
      expect(d.includeOriginalAttachments, isTrue);
      expect(d.originalAttachmentBytes, 120000);
    });
  });

  group('toRequest', () {
    test('puts the user text above the quote, in text and HTML', () {
      final d = buildDraft(_msg(html: '<p>Hello</p>'), mode: ComposeMode.reply, ownAddresses: own);
      final r = d.toRequest(from: d.from, to: d.to, cc: d.cc, bcc: const [], subject: d.subject, body: 'Thanks <Lena>!\nPaid.');
      expect(r.text, startsWith('Thanks <Lena>!\nPaid.\n\nOn '));
      expect(r.html, startsWith('<div dir="auto">Thanks &lt;Lena&gt;!<br>Paid.</div><br><div>On '));
      expect(r.inReplyTo, 'm1');
    });

    test('quote can be dropped', () {
      final d = buildDraft(_msg(), mode: ComposeMode.reply, ownAddresses: own);
      final r = d.toRequest(from: d.from, to: d.to, cc: const [], bcc: const [], subject: d.subject, body: 'Ok', includeQuote: false);
      expect(r.text, 'Ok');
      expect(r.html, isNull);
    });
  });

  group('addresses', () {
    test('parses display-name forms', () {
      expect(MailAddress.tryParse('Lena Varga <lena@varga.studio>')!.name, 'Lena Varga');
      expect(MailAddress.tryParse('"Varga, Lena" <lena@varga.studio>')!.name, 'Varga, Lena');
      expect(MailAddress.tryParse('lena@varga.studio')!.address, 'lena@varga.studio');
      expect(MailAddress.tryParse('not an email'), isNull);
    });
  });

  test('htmlToText keeps structure', () {
    expect(htmlToText('<div>Hi<br>there</div><p>Next &amp; last</p><style>p{}</style>'), 'Hi\nthere\nNext & last');
  });
}
