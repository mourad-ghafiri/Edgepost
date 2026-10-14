#!/usr/bin/env bash
# Derives every icon and launch raster from the masters rendered from code by
# tool/icon/icon_render_test.dart (run it with --update-goldens first), using
# macOS `sips`. Resource XML (adaptive icon, launch screens, colours) is
# written by hand and only references these files.
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC="tool/icon"
# Intermediate files live in the git-ignored build output, overwritten each run.
WORK="build/icon-work"
mkdir -p "$WORK"

# App Store Connect rejects icons with an alpha channel: flatten through JPEG.
flat() { sips -s format jpeg -s formatOptions 100 "$1" --out "$2" >/dev/null; }
png() { sips -s format png -z "$3" "$3" "$1" --out "$2" >/dev/null; }

# iOS: one 1024 icon per appearance; Xcode derives the sizes.
IOS="ios/Runner/Assets.xcassets/AppIcon.appiconset"
for v in "" "_dark" "_tinted"; do
  flat "$SRC/edgepost_icon${v}_1024.png" "$WORK/flat-icon$v.jpg"
  png "$WORK/flat-icon$v.jpg" "$IOS/Icon-1024${v//_/-}.png" 1024
done

# iOS launch mark at 120 pt. The app opens light (its default appearance),
# so the launch screen is light in either system mode.
LAUNCH="ios/Runner/Assets.xcassets/LaunchImage.imageset"
png "$SRC/launch_mark_light_384.png" "$LAUNCH/LaunchImage.png" 120
png "$SRC/launch_mark_light_384.png" "$LAUNCH/LaunchImage@2x.png" 240
png "$SRC/launch_mark_light_384.png" "$LAUNCH/LaunchImage@3x.png" 360

# Android: legacy icon (pre-8.0), adaptive layers (108 dp), notification
# icon (24 dp) per density.
RES="android/app/src/main/res"
flat "$SRC/edgepost_icon_1024.png" "$WORK/flat-legacy.jpg"
for spec in "mdpi:1" "hdpi:1.5" "xhdpi:2" "xxhdpi:3" "xxxhdpi:4"; do
  dpi="${spec%%:*}"; k="${spec##*:}"
  px() { awk -v d="$1" -v k="$k" 'BEGIN { printf "%d", d * k }'; }
  png "$WORK/flat-legacy.jpg" "$RES/mipmap-$dpi/ic_launcher.png" "$(px 48)"
  png "$SRC/adaptive_foreground_432.png" "$RES/mipmap-$dpi/ic_launcher_foreground.png" "$(px 108)"
  png "$SRC/adaptive_monochrome_432.png" "$RES/mipmap-$dpi/ic_launcher_monochrome.png" "$(px 108)"
  mkdir -p "$RES/drawable-$dpi"
  png "$SRC/notification_96.png" "$RES/drawable-$dpi/ic_stat_edgepost.png" "$(px 24)"
done

# Android launch mark (96 dp, scaled down by the system on lower densities),
# light in either system mode, as on iOS.
mkdir -p "$RES/drawable-xxxhdpi"
png "$SRC/launch_mark_light_384.png" "$RES/drawable-xxxhdpi/launch_mark.png" 384

echo "Icons and launch marks written."
