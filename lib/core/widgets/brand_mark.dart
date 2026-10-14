import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The Signpost: a post with two boards. The upper one is an envelope
/// pointing right (mail goes out), the lower one points back (routing, DNS).
/// Drawn on a 100-unit grid so every size, the app icon included, comes
/// from the same geometry.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({required this.post, required this.envelope, required this.flap, this.tile});

  /// The post and the lower board.
  final Color post;

  /// The envelope board (the brand orange).
  final Color envelope;

  /// The envelope's flap line: the colour behind the mark, so it reads as a
  /// cut. Fully transparent cuts it out for real (single-colour icons).
  final Color flap;

  /// The app tile behind the mark (icons only).
  final Color? tile;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * u) / 2, (size.height - 100 * u) / 2);
    canvas.scale(u);
    if (tile != null) canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = tile!);
    final cut = flap.a == 0;
    if (cut) canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());

    final fill = Paint()..isAntiAlias = true;
    // Rounded joins soften every corner by the same amount.
    Paint soft(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;

    // The post.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(46.5, 15, 7, 71), const Radius.circular(3.5)),
      fill..color = post,
    );

    // Lower board, pointing back.
    final lower = Path()
      ..moveTo(30, 62)
      ..lineTo(37.5, 54.5)
      ..lineTo(65, 54.5)
      ..lineTo(65, 69.5)
      ..lineTo(37.5, 69.5)
      ..close();
    canvas.drawPath(lower, fill..color = post);
    canvas.drawPath(lower, soft(post));

    // Upper board: the envelope, pointing out.
    final upper = Path()
      ..moveTo(21, 25)
      ..lineTo(69, 25)
      ..lineTo(80, 37.5)
      ..lineTo(69, 50)
      ..lineTo(21, 50)
      ..close();
    canvas.drawPath(upper, fill..color = envelope);
    canvas.drawPath(upper, soft(envelope));

    // The flap.
    final flapLine = Path()
      ..moveTo(25.5, 29)
      ..lineTo(45, 40.5)
      ..lineTo(64.5, 29);
    canvas.drawPath(
      flapLine,
      Paint()
        ..color = cut ? const Color(0xFF000000) : flap
        ..blendMode = cut ? BlendMode.clear : BlendMode.srcOver
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (cut) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter old) =>
      old.post != post || old.envelope != envelope || old.flap != flap || old.tile != tile;
}

/// The Signpost mark in the app's colours: ink post, orange envelope.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.background});

  final double size;

  /// What the mark sits on (the flap is cut in this colour); the canvas by
  /// default.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: BrandMarkPainter(post: c.ink, envelope: c.brand, flap: background ?? c.canvas),
      ),
    );
  }
}

/// The mark and the name, for the welcome and lock screens.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.name, this.size = 28, this.background});

  final String name;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) => Semantics(
        label: name,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: size * 1.5, background: background),
            SizedBox(width: size * 0.3),
            ExcludeSemantics(child: Text(name, style: EpType.title(context, size: size, weight: FontWeight.w700))),
          ],
        ),
      );
}
