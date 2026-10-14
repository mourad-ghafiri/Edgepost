import 'package:edgepost/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent settings updates never drop each other', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final a = SecureStore(), b = SecureStore();
    await Future.wait([
      for (var i = 0; i < 20; i++) (i.isEven ? a : b).updateSettings((s) => s['k$i'] = i),
    ]);
    final s = await a.readSettings();
    expect(s.keys, hasLength(20));
  });

  test('a failing update does not block the next one', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureStore();
    await expectLater(store.updateSettings<void>((_) => throw StateError('x')), throwsStateError);
    await store.updateSettings((s) => s['ok'] = true);
    expect((await store.readSettings())['ok'], true);
  });
}
