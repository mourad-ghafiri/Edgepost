// Renders every Edgepost icon raster from the one Signpost geometry
// (lib/core/widgets/brand_mark.dart), so the shipping files have a
// reproducible source:
//   flutter test tool/icon/icon_render_test.dart --update-goldens
// writes the masters next to this file; tool/icon/make_icons.sh then derives
// the iOS and Android sizes with `sips`.
import 'package:edgepost/core/widgets/brand_mark.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _tile = Color(0xFF141518);
const _tileDark = Color(0xFF0B0B0D);
const _post = Color(0xFFF3F4F6);
const _orange = Color(0xFFF2672A);
const _clear = Color(0x00000000);
const _white = Color(0xFFFFFFFF);

/// A [size]² canvas with the mark drawn in a box [zoom] times the canvas,
/// centred (and clipped to the canvas).
Widget _master(double size, BrandMarkPainter painter, {double zoom = 1}) => SizedBox.square(
      dimension: size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size * zoom,
          maxWidth: size * zoom,
          minHeight: size * zoom,
          maxHeight: size * zoom,
          child: CustomPaint(size: Size.square(size * zoom), painter: painter),
        ),
      ),
    );

Future<void> _render(WidgetTester tester, String name, double size, Widget master, {Color? ground}) async {
  tester.view.physicalSize = Size.square(size);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(child: ground == null ? master : ColoredBox(color: ground, child: master)),
    ),
  ));
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(name));
}

void main() {
  // App Store / home screen: the mark at about half the tile, on near-black.
  testWidgets('app icon', (tester) async {
    await _render(tester, 'edgepost_icon_1024.png', 1024,
        _master(1024, const BrandMarkPainter(post: _post, envelope: _orange, flap: _tile), zoom: 0.78), ground: _tile);
  });

  // iOS dark appearance: the same mark on a deeper tile.
  testWidgets('app icon, dark', (tester) async {
    await _render(tester, 'edgepost_icon_dark_1024.png', 1024,
        _master(1024, const BrandMarkPainter(post: _post, envelope: _orange, flap: _tileDark), zoom: 0.78), ground: _tileDark);
  });

  // iOS tinted appearance: greyscale on black; the system applies the tint.
  testWidgets('app icon, tinted', (tester) async {
    await _render(tester, 'edgepost_icon_tinted_1024.png', 1024,
        _master(1024, const BrandMarkPainter(post: Color(0xFF9C9C9C), envelope: _white, flap: Color(0xFF000000)), zoom: 0.78),
        ground: const Color(0xFF000000));
  });

  // Android adaptive foreground (108 dp at 4×): the mark inside the 66 dp
  // safe zone, on transparent; the background layer is the tile colour.
  testWidgets('adaptive foreground', (tester) async {
    await _render(tester, 'adaptive_foreground_432.png', 432,
        _master(432, const BrandMarkPainter(post: _post, envelope: _orange, flap: _tile), zoom: 66 / 108));
  });

  // Android 13+ themed icon: one colour, the flap cut out.
  testWidgets('adaptive monochrome', (tester) async {
    await _render(tester, 'adaptive_monochrome_432.png', 432,
        _master(432, const BrandMarkPainter(post: _white, envelope: _white, flap: _clear), zoom: 66 / 108));
  });

  // Notification small icon (24 dp at 4×): white silhouette, flap cut out,
  // filling the icon's height.
  testWidgets('notification icon', (tester) async {
    await _render(tester, 'notification_96.png', 96,
        _master(96, const BrandMarkPainter(post: _white, envelope: _white, flap: _clear), zoom: 1.33));
  });

  // The launch mark on the light canvas (#F6F7F9): the app opens light.
  testWidgets('launch mark, light', (tester) async {
    await _render(tester, 'launch_mark_light_384.png', 384,
        _master(384, const BrandMarkPainter(post: Color(0xFF17181C), envelope: _orange, flap: Color(0xFFF6F7F9))));
  });
}
