// Renders the demo domain's logo for the fake API (a made-up studio, so
// screenshots never show Edgepost's own mark as a customer's logo):
//   flutter test tool/fake_cf_api/sample_logo_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _navy = Color(0xFF1E3A5F);

/// A north arrow in a circle: "Nord".
class _Mark extends CustomPainter {
  const _Mark();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, r, Paint()..color = _navy);
    final arrow = Path()
      ..moveTo(centre.dx, centre.dy - r * 0.62)
      ..lineTo(centre.dx + r * 0.36, centre.dy + r * 0.5)
      ..lineTo(centre.dx, centre.dy + r * 0.28)
      ..lineTo(centre.dx - r * 0.36, centre.dy + r * 0.5)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_Mark oldDelegate) => false;
}

void main() {
  testWidgets('sample logo', (tester) async {
    await tester.runAsync(() async {
      final bytes = File('assets/fonts/Inter-SemiBold.ttf').readAsBytesSync();
      await (FontLoader('Inter')..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))))).load();
    });
    tester.view
      ..physicalSize = const Size(340, 96)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: SizedBox(
            width: 340,
            height: 96,
            child: Row(
              children: [
                SizedBox(width: 12),
                SizedBox.square(dimension: 72, child: CustomPaint(painter: _Mark())),
                SizedBox(width: 18),
                Text(
                  'atelier nord',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 42,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('sample_logo.png'));
  });
}
