import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../zones/data/zones_providers.dart';
import '../data/purge.dart';
import '../data/zone_settings_repository.dart';

/// Purge specific URLs: one per line, checked against the zone before sending.
class PurgeUrlsScreen extends ConsumerStatefulWidget {
  const PurgeUrlsScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  ConsumerState<PurgeUrlsScreen> createState() => _PurgeUrlsScreenState();
}

class _PurgeUrlsScreenState extends ConsumerState<PurgeUrlsScreen> {
  final _field = TextEditingController();
  bool _submitted = false;
  bool _busy = false;
  int _done = 0;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    if (zone == null) {
      return EpPage(title: l.controlsPurgeUrls, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final check = checkPurgeUrls(_field.text, zone.name);
    final error = _submitted ? _errorText(context, check, zone.name) : null;
    final total = check.urls.length;

    return EpPage(
      title: l.controlsPurgeUrls,
      largeTitle: false,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
          sliver: SliverList.list(
            children: [
              EpTextField(
                label: l.controlsPurgeUrlsField,
                controller: _field,
                placeholder: l.controlsPurgeUrlsPlaceholder(zone.name),
                keyboardType: TextInputType.multiline,
                monospace: true,
                autocorrect: false,
                minLines: 5,
                maxLines: 12,
                enabled: !_busy,
                errorText: error,
                helperText: l.controlsPurgeUrlsHelp(zone.name),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: EpSpace.xl),
              EpButton(
                label: _busy && total > ZoneSettingsRepository.maxFilesPerPurge
                    ? '$_done / $total'
                    : l.controlsPurgeUrlsButton(total),
                busy: _busy,
                destructive: true,
                onPressed: () => _purge(zone),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _errorText(BuildContext context, PurgeUrlCheck check, String domain) {
    final l = context.l10n;
    if (check.isEmpty) return l.controlsPurgeUrlsEmpty(domain);
    if (check.rejected.isEmpty) return null;
    final first = check.rejected.first;
    final line = switch (first.problem) {
      PurgeUrlProblem.notUrl => l.controlsPurgeUrlNotUrl(first.line),
      PurgeUrlProblem.notHttp => l.controlsPurgeUrlNotHttp(first.line),
      PurgeUrlProblem.otherDomain => l.controlsPurgeUrlOtherDomain(domain, first.line),
    };
    final more = check.rejected.length - 1;
    return more > 0 ? '$line\n${l.controlsPurgeUrlsMore(more)}' : line;
  }

  Future<void> _purge(Zone zone) async {
    final zoneId = zone.id, domain = zone.name;
    final l = context.l10n;
    final check = checkPurgeUrls(_field.text, domain);
    setState(() => _submitted = true);
    if (!check.ok) return;
    setState(() {
      _busy = true;
      _done = 0;
    });
    final repo = ZoneSettingsRepository(ref.zoneClient(zone, Capability.cachePurge));
    try {
      final n = await repo.purgeFiles(zoneId, check.urls, onProgress: (d) {
        if (mounted) setState(() => _done = d);
      });
      if (!mounted) return;
      showEpToast(context, l.controlsPurgeUrlsDone(n));
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      final reason = isPurgeRateLimited(e)
          ? l.controlsPurgeRateLimited
          : describeError(context, e, permission: Capability.cachePurge.permission);
      if (_done > 0) {
        // Keep only what still needs purging, so a retry doesn't resend.
        _field.text = check.urls.skip(_done).join('\n');
        showEpToast(context, l.controlsPurgeUrlsPartial(_done, check.urls.length, reason));
      } else {
        showEpToast(context, reason);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
