import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'mail_models.dart';
import 'mail_providers.dart';

/// Every configured domain's signature and logo, from the account's mail
/// service (shared by every device that uses it).
final brandsProvider = AsyncNotifierProvider.family<BrandsNotifier, Synced<List<DomainBrand>>, String>(
  BrandsNotifier.new,
);

class BrandsNotifier extends SyncedNotifier<List<DomainBrand>> {
  BrandsNotifier(this.accountId);
  final String accountId;

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'mail:brands';

  @override
  void prepare() => ref.watch(mailServiceProvider(accountId));

  @override
  Future<List<DomainBrand>> fetch() => ref.read(mailClientProvider(accountId)).brands();

  @override
  Object? encode(List<DomainBrand> data) => data.map((b) => b.toJson()).toList();

  @override
  List<DomainBrand> decode(Object? json) =>
      (json as List).cast<Map<String, dynamic>>().map(DomainBrand.fromJson).toList();

  void _replace(DomainBrand b) =>
      setData([for (final x in state.value?.data ?? const <DomainBrand>[]) x.domain == b.domain ? b : x]);

  Future<void> saveSignature(String domain, String signature) async =>
      _replace(await ref.read(mailClientProvider(accountId)).putSignature(domain, signature));

  Future<void> setLogo(String domain, PreparedLogo logo) async {
    final b = await ref.read(mailClientProvider(accountId)).putLogo(domain, logo.png);
    await _cacheLogo(ref, accountId, domain, b.logo!, logo.png);
    _replace(b);
  }

  Future<void> removeLogo(String domain) async =>
      _replace(await ref.read(mailClientProvider(accountId)).deleteLogo(domain));
}

/// [domain]'s brand in [brands] (blank when the service doesn't list it).
DomainBrand brandOf(List<DomainBrand> brands, String domain) =>
    brands.where((b) => b.domain == domain.toLowerCase()).firstOrNull ??
    DomainBrand(domain: domain.toLowerCase(), signature: '');

String _logoKey(String domain) => 'mail:brand-logo:$domain';

Future<void> _cacheLogo(Ref ref, String accountId, String domain, BrandLogo logo, Uint8List png) => ref
    .read(cacheStoreProvider)
    .write(accountId, _logoKey(domain), {'updatedAt': logo.updatedAt, 'png': base64Encode(png)});

/// A domain's logo image (null without one), cached on the device until the
/// logo changes.
final brandLogoProvider = FutureProvider.family<Uint8List?, (String, String)>((ref, key) async {
  final (accountId, domain) = key;
  final logo = await ref.watch(
    brandsProvider(accountId).selectAsync((s) => brandOf(s.data, domain).logo),
  );
  if (logo == null) return null;
  final cache = ref.read(cacheStoreProvider);
  final hit = await cache.read(accountId, _logoKey(domain));
  if (hit != null) {
    final j = hit.value as Map<String, dynamic>;
    if (j['updatedAt'] == logo.updatedAt) return base64Decode(j['png'] as String);
  }
  final png = await ref.read(mailClientProvider(accountId)).logo(domain);
  await _cacheLogo(ref, accountId, domain, logo, png);
  return png;
});

/// A logo ready to upload: PNG, at most 480 × 96 (2× the 240 × 48 it's shown
/// at in mail), aspect ratio kept, never scaled up.
class PreparedLogo {
  const PreparedLogo({required this.png, required this.width, required this.height});
  final Uint8List png;
  final int width;
  final int height;
}

/// The picked image could not be read as a picture.
class LogoException implements Exception {
  const LogoException();
}

/// Decodes any image the platform reads (PNG, JPEG, HEIC, WebP…), scales it
/// to fit 480 × 96 and re-encodes it as PNG, so the mail service only ever
/// stores small PNGs.
Future<PreparedLogo> prepareLogo(Uint8List input) async {
  final ui.Codec probe;
  try {
    probe = await ui.instantiateImageCodec(input);
  } on Object {
    throw const LogoException();
  }
  final first = await probe.getNextFrame();
  final w0 = first.image.width, h0 = first.image.height;
  first.image.dispose();
  probe.dispose();
  final s = min(1.0, min(480 / w0, 96 / h0));
  final w = max(1, (w0 * s).round()), h = max(1, (h0 * s).round());
  final codec = await ui.instantiateImageCodec(input, targetWidth: w, targetHeight: h);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  if (data == null) throw const LogoException();
  return PreparedLogo(png: data.buffer.asUint8List(), width: w, height: h);
}
