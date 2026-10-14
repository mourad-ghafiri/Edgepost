import 'package:edgepost/features/mail/data/delivery_watch.dart';
import 'package:edgepost/features/mail/data/provisioning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compareVersions compares dotted versions numerically', () {
    expect(compareVersions('1.3.0', '1.2.9'), greaterThan(0));
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    expect(compareVersions('1.3.0', '1.3.0'), 0);
    expect(compareVersions('1.3.0', '2.0.0'), lessThan(0));
    expect(compareVersions('1.3', '1.3.0'), 0);
  });

  test("delivery is 'low' below 95% only with at least 5 finished sends", () {
    DomainDelivery d(int ok, int bad) => DomainDelivery(zoneId: 'z', domain: 'a.dev', delivered: ok, failed: bad);
    expect(d(3, 1).low, isFalse, reason: 'too few sends to judge');
    expect(d(19, 1).low, isFalse, reason: '95% meets the target');
    expect(d(18, 2).low, isTrue);
    expect(d(0, 0).rate, isNull);
  });
}
