import 'package:edgepost/features/mail/data/message_size.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mib = 1024 * 1024;

  test('attachments are counted as sent: base64 with line breaks, about +37%', () {
    final encoded = encodedAttachmentBytes(3 * mib);
    expect(encoded, greaterThan(4 * mib));
    expect(encoded / (3 * mib), closeTo(1.37, 0.01));
  });

  test('a 3 MiB file fits; a 3.8 MiB file does not, though its raw size is under 5 MiB', () {
    expect(estimateMessageBytes(text: 'hi', attachmentRawSizes: [3 * mib]), lessThan(kMaxOutboundBytes));
    expect(estimateMessageBytes(text: 'hi', attachmentRawSizes: [(3.8 * mib).round()]), greaterThan(kMaxOutboundBytes));
  });

  test('remainingRawBytes is the largest raw file that still fits', () {
    final base = estimateMessageBytes(text: 'hello');
    final room = remainingRawBytes(base);
    expect(estimateMessageBytes(text: 'hello', attachmentRawSizes: [room]), lessThanOrEqualTo(kMaxOutboundBytes));
    expect(estimateMessageBytes(text: 'hello', attachmentRawSizes: [room + 4096]), greaterThan(kMaxOutboundBytes));
    expect(remainingRawBytes(kMaxOutboundBytes), 0);
  });

  test('non-ASCII text gets quoted-printable headroom', () {
    final ascii = estimateMessageBytes(text: 'a' * 1000);
    final accented = estimateMessageBytes(text: 'é' * 1000);
    expect(accented, greaterThan(ascii));
  });
}
