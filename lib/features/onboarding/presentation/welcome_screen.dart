import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/adaptive/ep_page.dart' show EpReadableWidth;
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/brand_mark.dart';

/// First run: the mark and what Edgepost does, a few sample cards (labelled
/// as such), then on to adding a token.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: EpReadableWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(EpSpace.xl, EpSpace.xl, EpSpace.xl, EpSpace.xl),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wordmark(name: l.appName, size: 22),
              ),
              const SizedBox(height: EpSpace.xl + EpSpace.sm),
              Text(
                l.welcomeTitle,
                style: EpType.title(context, size: 34, weight: FontWeight.w700).copyWith(height: 1.1),
              ),
              const SizedBox(height: EpSpace.md),
              Text(l.welcomeBody, style: text.bodyLarge?.copyWith(color: c.inkMuted, height: 1.45)),
              const SizedBox(height: EpSpace.xl),
              ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.syntheticDataLabel.toUpperCase(), style: EpType.groupLabel(context)),
                    const SizedBox(height: EpSpace.sm),
                    Strip(
                      title: 'atelier-nord.dev',
                      family: Family.domains,
                      cocked: true,
                      reason: 'Nameservers not switched yet',
                      fields: [
                        StripField('Status', 'Pending', color: c.caution),
                        const StripField('Plan', 'Free'),
                      ],
                    ),
                    const SizedBox(height: EpSpace.sm),
                    // Same shape as a real inbox card (MessageStrip).
                    const Strip(
                      title: 'Lena Varga',
                      caption: '09:42 · to contact@atelier-nord.dev',
                      family: Family.mail,
                      emphasis: true,
                      detail: Text('Re: Invoice 2026-118 for October'),
                    ),
                    const SizedBox(height: EpSpace.sm),
                    Strip(
                      title: 'docs-site',
                      caption: 'Pages · main',
                      family: Family.compute,
                      fields: [
                        StripField('Build', 'Success', color: c.ok),
                        const StripField('Took', '41 s'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: EpSpace.xl),
              Text(l.welcomePrivacy, style: text.bodyMedium?.copyWith(color: c.inkMuted, height: 1.45)),
              const SizedBox(height: EpSpace.xl),
              EpButton(label: l.welcomeAddToken, onPressed: () => context.go('/welcome/token')),
              const SizedBox(height: EpSpace.sm),
              EpButton(
                label: l.welcomeHowTo,
                secondary: true,
                onPressed: () => launchUrl(
                  Uri.parse('https://developers.cloudflare.com/fundamentals/api/get-started/create-token/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: EpSpace.xl),
              Text(
                l.welcomeNotAffiliated,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: c.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
