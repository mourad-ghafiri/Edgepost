import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../data/reply_builder.dart';

/// Renders an HTML email safely:
/// - a Content-Security-Policy forbids every script, frame, form and remote
///   load; remote images only when the user asks;
/// - scripts and event handlers are also stripped before loading;
/// - links never navigate in place: they open externally after the user sees
///   the real destination.
/// The page is sized to its content so the thread scrolls as one surface.
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({super.key, required this.html, this.allowRemote = false});

  final String html;
  final bool allowRemote;

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView> {
  late final WebViewController _ctl;
  double _height = 120;

  static String wrap(String html, {required bool allowRemote, double fontPx = 15}) {
    final img = allowRemote ? "img-src data: https:" : "img-src data:";
    final csp =
        "default-src 'none'; $img; style-src 'unsafe-inline'; font-src data:; "
        "media-src 'none'; frame-src 'none'; form-action 'none'; script-src 'none'; base-uri 'none'";
    final body = sanitizeForQuote(html)
        .replaceAll(RegExp(r'<form[\s\S]*?</form>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<meta[^>]*http-equiv[^>]*>', caseSensitive: false), '');
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="$csp">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<style>html,body{margin:0;padding:0;background:#fff;color:#111;'
        'font:${fontPx.toStringAsFixed(1)}px/1.45 -apple-system,Roboto,Helvetica,Arial,sans-serif;'
        '-webkit-text-size-adjust:100%;word-wrap:break-word;}'
        'body{padding:12px}img{max-width:100%;height:auto}table{max-width:100%}'
        'pre{white-space:pre-wrap}blockquote{margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex}</style>'
        '</head><body>$body</body></html>';
  }

  @override
  void initState() {
    super.initState();
    _ctl = WebViewController()
      // JavaScript is enabled only so the app can measure the page height;
      // the CSP above blocks every script that came with the email.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            if (req.url == 'about:blank' || req.url.startsWith('data:')) return NavigationDecision.navigate;
            _confirmOpen(req.url);
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) => _measure(),
        ),
      );
  }

  /// Base text size follows Dynamic Type / Android font scale, like the
  /// rest of the app (emails that set their own sizes keep them).
  double? _fontPx;

  void _load() => _ctl.loadHtmlString(wrap(widget.html, allowRemote: widget.allowRemote, fontPx: _fontPx ?? 15));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final px = MediaQuery.textScalerOf(context).scale(15);
    if (px != _fontPx) {
      _fontPx = px;
      _load();
    }
  }

  @override
  void didUpdateWidget(MailHtmlView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html || old.allowRemote != widget.allowRemote) _load();
  }

  Future<void> _measure() async {
    for (final delay in const [0, 250, 900]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      try {
        final r = await _ctl.runJavaScriptReturningResult(
          'Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)',
        );
        final h = double.tryParse('$r'.replaceAll('"', ''));
        if (h != null && mounted && (h - _height).abs() > 2) setState(() => _height = h.clamp(40, 20000));
      } on Object {
        return;
      }
    }
  }

  Future<void> _confirmOpen(String url) async {
    final l = context.l10n;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http') || uri.isScheme('mailto') || uri.isScheme('tel'))) {
      return;
    }
    final ok = await showEpConfirm(
      context,
      title: l.mailOpenLinkTitle,
      message: l.mailOpenLinkBody(url),
      confirmLabel: l.actionOpen,
    );
    if (ok) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF), // emails are authored for white paper
        borderRadius: BorderRadius.circular(EpRadius.sm),
        border: Border.all(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: WebViewWidget(
        controller: _ctl,
        // Let horizontal drags reach wide tables; vertical scroll belongs to the thread.
        gestureRecognizers: {Factory<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new)},
      ),
    );
  }
}
