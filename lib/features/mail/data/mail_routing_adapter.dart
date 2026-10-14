import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cloudflare/cf_client.dart';
import '../../email_routing/data/email_routing_repository.dart' as routing;
import 'provisioning.dart';

/// Mail setup's view of Email Routing, over the email_routing feature's API.
class EmailRoutingForMail implements MailRouting {
  const EmailRoutingForMail();

  @override
  Future<void> enableRouting(CfClient client, String zoneId) async {
    final s = await routing.fetchRoutingSettings(client, zoneId);
    if (s.enabled && s.status == routing.RoutingStatus.ready) return;
    await routing.enableRouting(client, zoneId);
  }

  @override
  Future<void> setCatchAllToWorker(CfClient client, String zoneId, String workerName) =>
      routing.setCatchAllToWorker(client, zoneId, workerName);

  @override
  Future<void> routeAddressToWorker(CfClient client, String zoneId, String address, String workerName) =>
      routing.routeAddressToWorker(client, zoneId, address, workerName);
}

final mailRoutingProvider = Provider<MailRouting>((ref) => const EmailRoutingForMail());
