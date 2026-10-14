import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../data/branding.dart';
import '../data/mail_models.dart';
import 'compose_screen.dart' show attachmentPickerProvider;

/// A domain's signature and logo: what mail sent from it ends with, on every
/// device using this mail service. Changes apply together on Save.
class DomainBrandScreen extends ConsumerStatefulWidget {
  const DomainBrandScreen({super.key, required this.domain});
  final String domain;

  @override
  ConsumerState<DomainBrandScreen> createState() => _DomainBrandScreenState();
}

class _DomainBrandScreenState extends ConsumerState<DomainBrandScreen> {
  final _signature = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  /// A newly chosen logo, not saved yet.
  PreparedLogo? _newLogo;

  /// The saved logo goes on Save.
  bool _removeLogo = false;

  String get _account => ref.read(activeAccountProvider)!.id;
  String get _domain => widget.domain.toLowerCase();

  @override
  void initState() {
    super.initState();
    _signature.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  DomainBrand _saved(List<DomainBrand> brands) => brandOf(brands, _domain);

  bool _dirty(DomainBrand saved) => _newLogo != null || _removeLogo || _signature.text.trim() != saved.signature;

  Future<void> _choose() async {
    final l = context.l10n;
    final List<PlatformFile> files;
    try {
      files = await ref.read(attachmentPickerProvider)(FileType.image);
    } on Object {
      return;
    }
    if (files.isEmpty || !mounted) return;
    try {
      final logo = await prepareLogo(Uint8List.fromList(await files.first.readAsBytes()));
      if (!mounted) return;
      setState(() {
        _newLogo = logo;
        _removeLogo = false;
      });
    } on LogoException {
      if (mounted) showEpToast(context, l.mailBrandLogoUnreadable);
    }
  }

  Future<void> _save(DomainBrand saved) async {
    final l = context.l10n;
    final brands = ref.read(brandsProvider(_account).notifier);
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      if (_signature.text.trim() != saved.signature) await brands.saveSignature(_domain, _signature.text.trim());
      if (_newLogo != null) {
        await brands.setLogo(_domain, _newLogo!);
      } else if (_removeLogo && saved.logo != null) {
        await brands.removeLogo(_domain);
      }
      if (!mounted) return;
      showEpToast(context, l.mailBrandSaved(_domain));
      context.pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showEpToast(context, describeError(context, e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final async = ref.watch(brandsProvider(_account));
    final data = async.value?.data;
    if (data == null) {
      return EpPage(
        title: l.mailBrandTitle,
        largeTitle: false,
        slivers: [
          EpFill(
            child: async.hasError
                ? EpErrorView(error: async.error!, onRetry: () => ref.invalidate(brandsProvider(_account)))
                : const EpLoading(),
          ),
        ],
      );
    }
    final saved = _saved(data);
    if (!_loaded) {
      _loaded = true;
      _signature.text = saved.signature;
    }

    // What the preview and the Logo group show: the new logo, the saved one,
    // or none.
    final savedImage = saved.logo == null ? null : ref.watch(brandLogoProvider((_account, _domain))).value;
    final Uint8List? image = _newLogo?.png ?? (_removeLogo ? null : savedImage);
    final BrandLogo? logo = _newLogo != null
        ? BrandLogo(width: _newLogo!.width, height: _newLogo!.height, size: _newLogo!.png.length, updatedAt: 'new')
        : (_removeLogo ? null : saved.logo);
    final hasLogo = logo != null;

    return EpPage(
      title: l.mailBrandTitle,
      subtitle: Text(_domain),
      largeTitle: false,
      // In the top bar: the keyboard never covers it while the signature is
      // being typed.
      textAction: EpTextAction(
        label: l.actionSave,
        busy: _saving,
        onPressed: _dirty(saved) ? () => _save(saved) : null,
      ),
      slivers: [
        SliverToBoxAdapter(
          child: EpSection(
            header: l.mailBrandLogo,
            footer: l.mailBrandLogoHelp,
            children: [
              if (hasLogo)
                Padding(
                  padding: const EdgeInsets.all(EpSpace.lg),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: image == null
                        ? SizedBox(width: logo.shown.$1, height: logo.shown.$2)
                        : Image.memory(
                            image,
                            width: logo.shown.$1,
                            height: logo.shown.$2,
                            semanticLabel: l.mailSignatureLogoLabel(_domain),
                            errorBuilder: (_, _, _) => SizedBox(width: logo.shown.$1, height: logo.shown.$2),
                          ),
                  ),
                ),
              EpTile(
                leading: EpIconView(EpIcon.image, color: c.tint),
                title: Text(hasLogo ? l.mailBrandReplaceLogo : l.mailBrandChooseLogo, style: TextStyle(color: c.tint)),
                showChevron: false,
                onTap: _saving ? null : _choose,
              ),
              if (hasLogo)
                EpTile(
                  title: Text(l.mailBrandRemoveLogo),
                  destructive: true,
                  showChevron: false,
                  onTap: _saving
                      ? null
                      : () => setState(() {
                          _newLogo = null;
                          _removeLogo = true;
                        }),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.mailBrandSignature,
            footer: l.mailBrandSignatureHelp(_domain),
            children: [_SignatureField(controller: _signature, placeholder: l.mailBrandSignaturePlaceholder)],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.mailBrandPreview,
            children: [_Preview(sample: l.mailBrandSample, signature: _signature.text, logo: logo, image: image)],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: EpSpace.xl)),
      ],
    );
  }
}

/// The signature text, as a multi-line cell of its section.
class _SignatureField extends StatelessWidget {
  const _SignatureField({required this.controller, required this.placeholder});
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: EpColors.of(context).ink, fontSize: 16, height: 1.4);
    if (isCupertino(context)) {
      return CupertinoTextField.borderless(
        controller: controller,
        placeholder: placeholder,
        padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.md),
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        style: style,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.md),
      child: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        style: style,
        decoration: bareInputDecoration(hintText: placeholder),
      ),
    );
  }
}

/// The end of a message as recipients see it: on paper white (mail is
/// written for it), the logo at its real size, links in blue.
class _Preview extends StatelessWidget {
  const _Preview({required this.sample, required this.signature, required this.logo, required this.image});
  final String sample;
  final String signature;
  final BrandLogo? logo;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17181C);
    const muted = Color(0xFF5B606A);
    const link = Color(0xFF2557D6);
    final lines = signature.trim().isEmpty ? const <String>[] : signature.trim().split('\n');
    final linkPattern = RegExp(r'(https?://\S+|www\.\S+|[\w.+-]+@[\w-]+(\.[\w-]+)+)');
    TextSpan line(String text) {
      final spans = <TextSpan>[];
      var at = 0;
      for (final m in linkPattern.allMatches(text)) {
        spans.add(TextSpan(text: text.substring(at, m.start)));
        spans.add(
          TextSpan(
            text: m.group(0),
            style: const TextStyle(color: link),
          ),
        );
        at = m.end;
      }
      spans.add(TextSpan(text: text.substring(at)));
      return TextSpan(children: spans);
    }

    return Container(
      color: const Color(0xFFFFFFFF),
      width: double.infinity,
      padding: const EdgeInsets.all(EpSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sample, style: const TextStyle(color: ink, fontSize: 15, height: 1.45)),
          const SizedBox(height: 20),
          if (logo != null) ...[
            image == null
                ? SizedBox(width: logo!.shown.$1, height: logo!.shown.$2)
                : Image.memory(
                    image!,
                    width: logo!.shown.$1,
                    height: logo!.shown.$2,
                    errorBuilder: (_, _, _) => SizedBox(width: logo!.shown.$1, height: logo!.shown.$2),
                  ),
            if (lines.isNotEmpty) const SizedBox(height: 10),
          ],
          for (final l in lines) Text.rich(line(l), style: const TextStyle(color: muted, fontSize: 14, height: 1.45)),
        ],
      ),
    );
  }
}

/// A one-line summary of a domain's branding, for lists.
String brandSummary(BuildContext context, DomainBrand b) {
  final l = context.l10n;
  final sig = b.signature.trim().isNotEmpty;
  return switch ((sig, b.logo != null)) {
    (true, true) => l.mailBrandSummaryBoth,
    (true, false) => l.mailBrandSummarySignature,
    (false, true) => l.mailBrandSummaryLogo,
    (false, false) => l.mailBrandSummaryNone,
  };
}
