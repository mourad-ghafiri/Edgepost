import 'dart:convert';

/// Email Sending's limit applies to the whole message as sent, attachments
/// included (https://developers.cloudflare.com/email-service/api/send-emails/workers-api/).
const int kMaxOutboundBytes = 5 * 1024 * 1024;

/// Size of one attachment once base64-encoded with line breaks, plus its MIME
/// part headers. Mirrors the mail Worker's estimate so both refuse the same
/// messages.
int encodedAttachmentBytes(int rawBytes) => ((rawBytes + 2) ~/ 3 * 4 * 1.027).ceil() + 300;

/// Estimated size of the message as sent: headers, text and HTML bodies
/// (quoted-printable headroom) and every attachment encoded.
int estimateMessageBytes({
  required String text,
  String? html,
  Iterable<int> attachmentRawSizes = const [],
}) {
  int body(String? s) => s == null ? 0 : (utf8.encode(s).length * 1.03).ceil();
  return 2048 + body(text) + body(html) + attachmentRawSizes.fold(0, (sum, n) => sum + encodedAttachmentBytes(n));
}

/// Largest raw file that still fits next to what's already in the message.
int remainingRawBytes(int currentEstimate) {
  final room = kMaxOutboundBytes - currentEstimate;
  if (room <= encodedAttachmentBytes(0)) return 0;
  var n = ((room - 300) / 1.027 / 4 * 3).floor();
  // The estimate rounds up, so the inverse can overshoot by a few bytes.
  while (n > 0 && encodedAttachmentBytes(n) > room) {
    n--;
  }
  return n;
}
