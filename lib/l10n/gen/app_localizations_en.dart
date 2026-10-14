// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get trafficTitle => 'Traffic';

  @override
  String get trafficRange24h => '24 hours';

  @override
  String get trafficRange7d => '7 days';

  @override
  String get trafficRange30d => '30 days';

  @override
  String get trafficCaption24h => 'Last 24 hours · UTC';

  @override
  String get trafficCaption7d => 'Last 7 days · UTC';

  @override
  String get trafficCaption30d => 'Last 30 days · UTC';

  @override
  String get trafficFieldRequests => 'Requests';

  @override
  String get trafficFieldBandwidth => 'Bandwidth';

  @override
  String get trafficFieldCached => 'Cached';

  @override
  String get trafficFieldThreats => 'Threats';

  @override
  String get trafficFieldVisitors => 'Visitors';

  @override
  String get trafficChartHourly => 'Requests per hour';

  @override
  String get trafficChartDaily => 'Requests per day';

  @override
  String get trafficLegendAll => 'Not cached';

  @override
  String get trafficLegendCached => 'Served from cache';

  @override
  String trafficTooltipRequests(String count) {
    return '$count requests';
  }

  @override
  String trafficTooltipCached(String count, String percent) {
    return '$count from cache ($percent)';
  }

  @override
  String trafficChartSummary(String chart, String range, String total, String cached, String peak, String when) {
    return '$chart, $range. $total requests in all, $cached served from cache. Busiest: $peak requests, $when.';
  }

  @override
  String get trafficEmptyTitle => 'No traffic in this range';

  @override
  String trafficEmptyMessage(String domain) {
    return 'Cloudflare saw no requests for $domain. Traffic shows here once its DNS records are proxied through Cloudflare and visitors arrive.';
  }

  @override
  String get trafficRangeUnavailableTitle => 'This range isn\'t available on your plan';

  @override
  String get trafficRangeUnavailableMessage =>
      'Cloudflare keeps traffic history for a limited time on each plan, and this range reaches further back. Pick a shorter range.';

  @override
  String trafficShowRange(String range) {
    return 'Show $range';
  }

  @override
  String get trafficFieldPageViews => 'Page views';

  @override
  String get computeBayWorkers => 'Workers';

  @override
  String get computeBayPages => 'Pages';

  @override
  String computeGapPermission(String permission) {
    return 'This token can\'t list these. Add “$permission” to it in the Cloudflare dashboard, then pull to refresh.';
  }

  @override
  String computeGapFailed(String message) {
    return 'Couldn\'t load these: $message Pull to refresh to try again.';
  }

  @override
  String get computeNoAccessTitle => 'No access to Workers or Pages';

  @override
  String computeNoAccessMessage(String workers, String pages) {
    return 'Your tokens can\'t read Workers or Pages. In the Cloudflare dashboard, add “$workers” and “$pages” to a token, then pull to refresh.';
  }

  @override
  String get computeZoneRoutesTitle => 'Worker routes';

  @override
  String get computeZoneRoutesSectionRoutes => 'Routes';

  @override
  String get computeZoneRoutesRoutesFooter => 'Requests matching a route run the Worker before reaching your origin.';

  @override
  String get computeZoneRoutesSectionDomains => 'Custom domains';

  @override
  String get computeZoneRoutesDomainsFooter =>
      'A custom domain points a whole hostname at a Worker, with no origin behind it.';

  @override
  String get computeZoneRoutesNoRoutes => 'No routes on this domain.';

  @override
  String get computeZoneRoutesNoDomains => 'No Worker custom domains on this domain.';

  @override
  String get computeZoneRoutesNoScript => 'No Worker: requests go straight to the origin';

  @override
  String computeZoneRoutesRunsScript(String script) {
    return 'Runs $script';
  }

  @override
  String computeZoneRoutesEmptyTitle(String zone) {
    return 'No Workers on $zone';
  }

  @override
  String get computeZoneRoutesEmptyMessage =>
      'Add a route or custom domain to a Worker in the Cloudflare dashboard or with wrangler, then pull to refresh.';

  @override
  String get workersEmpty => 'No Workers in this account yet.';

  @override
  String get workersFieldModified => 'Modified';

  @override
  String get workersFieldRoutes => 'Routes';

  @override
  String get workersFieldCompat => 'Compat date';

  @override
  String get workersFieldUsage => 'Usage';

  @override
  String workersStripSemantics(String name, String modified, int routes) {
    String _temp0 = intl.Intl.pluralLogic(
      routes,
      locale: localeName,
      other: '$routes routes',
      one: '1 route',
      zero: 'no routes',
    );
    return 'Worker $name, modified $modified, $_temp0';
  }

  @override
  String get workersLiveLogs => 'Live logs';

  @override
  String get workersLiveLogsHint => 'Stream console output and requests as they happen';

  @override
  String get workersOpenWorkersDev => 'Open on workers.dev';

  @override
  String get workersSectionOverview => 'Overview';

  @override
  String get workersCreated => 'Created';

  @override
  String get workersModified => 'Modified';

  @override
  String get workersCompatDate => 'Compatibility date';

  @override
  String get workersCompatFlags => 'Compatibility flags';

  @override
  String get workersUsageModel => 'Usage model';

  @override
  String get workersDeployedFrom => 'Last deployed from';

  @override
  String get workersHandlers => 'Handlers';

  @override
  String get workersSectionTriggers => 'Triggers';

  @override
  String get workersDev => 'workers.dev';

  @override
  String get workersStateOn => 'On';

  @override
  String get workersStateOff => 'Off';

  @override
  String get workersPreviewsOn => 'Preview URLs on';

  @override
  String get workersPreviewsOff => 'Preview URLs off';

  @override
  String get workersCustomDomain => 'Custom domain';

  @override
  String get workersRoute => 'Route';

  @override
  String get workersNoTriggers =>
      'This Worker has no route, custom domain or workers.dev address, so nothing on the internet reaches it.';

  @override
  String get workersSectionDeployment => 'Deployment';

  @override
  String get workersActiveDeployment => 'Serving now';

  @override
  String get workersNoDeployments => 'Nothing is deployed yet.';

  @override
  String get workersGradualFooter => 'Traffic is split between versions (a gradual deployment).';

  @override
  String workersPercent(String percent) {
    return '$percent%';
  }

  @override
  String workersLiveShare(String percent) {
    return 'Live $percent%';
  }

  @override
  String get workersSectionVersions => 'Versions';

  @override
  String get workersNoVersions => 'No versions uploaded yet.';

  @override
  String get workersVersionsFooter =>
      'Tap a version to roll back to it. Rolling back sends all traffic to that version; you can roll forward the same way.';

  @override
  String workersVersionNumber(int number) {
    return 'Version $number';
  }

  @override
  String workersVersionShort(String id) {
    return 'Version $id';
  }

  @override
  String get workersRollbackAction => 'Roll back to this version';

  @override
  String get workersCopyVersionId => 'Copy version ID';

  @override
  String workersRollbackTitle(String version) {
    return 'Roll back to $version?';
  }

  @override
  String workersRollbackMessage(String script, String version, String id) {
    return 'All traffic to $script will go to $version ($id). The version serving now stays available, so you can roll forward the same way.';
  }

  @override
  String get workersRollbackConfirm => 'Roll back';

  @override
  String workersRollbackDone(String version) {
    return '$version now serves all traffic.';
  }

  @override
  String get workersRollbackBlockedTitle => 'Cloudflare blocked this rollback';

  @override
  String workersRollbackBlockedMessage(String message) {
    return 'Cloudflare said: “$message” You can force it, but that version may expect secrets or settings that have changed since.';
  }

  @override
  String get workersRollbackForce => 'Roll back anyway';

  @override
  String get workersSectionSecrets => 'Secrets';

  @override
  String get workersSecretsFooter => 'Cloudflare never returns secret values, so only names are shown.';

  @override
  String get workersNoSecrets => 'No secrets on this Worker.';

  @override
  String get workersSecretText => 'Secret text';

  @override
  String get workersSecretKey => 'Secret key';

  @override
  String get workersLogsTitle => 'Live logs';

  @override
  String get workersLogsConnecting => 'Connecting…';

  @override
  String workersLogsLive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Live · $count events',
      one: 'Live · 1 event',
      zero: 'Live · waiting for events',
    );
    return '$_temp0';
  }

  @override
  String workersLogsPaused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Paused · $count new events held',
      one: 'Paused · 1 new event held',
      zero: 'Paused',
    );
    return '$_temp0';
  }

  @override
  String get workersLogsEnded => 'Stream ended';

  @override
  String get workersLogsEndedHint =>
      'Cloudflare closed the log stream; log sessions expire after a while. Reconnect to keep watching.';

  @override
  String get workersLogsStopped => 'Stopped';

  @override
  String get workersLogsFailed => 'Couldn\'t start the log stream';

  @override
  String workersLogsWaiting(String script) {
    return 'Waiting for $script to run…';
  }

  @override
  String get workersLogsWaitingHint =>
      'Send a request to the Worker; its console output, exceptions and requests show up here as they happen.';

  @override
  String get workersLogsPrivacy => 'Logs stream straight from Cloudflare and are not saved.';

  @override
  String get workersLogsPause => 'Pause';

  @override
  String get workersLogsResume => 'Resume';

  @override
  String get workersLogsClear => 'Clear';

  @override
  String get workersLogsStop => 'Stop';

  @override
  String get workersLogsReconnect => 'Reconnect';

  @override
  String get workersLogsNoUrl => '(no URL)';

  @override
  String workersLogsCron(String cron) {
    return 'Cron $cron';
  }

  @override
  String get workersLogsAlarm => 'Durable Object alarm';

  @override
  String workersLogsEmail(String route) {
    return 'Email $route';
  }

  @override
  String workersLogsQueue(String queue) {
    return 'Queue $queue';
  }

  @override
  String workersLogsRpc(String method) {
    return 'RPC $method';
  }

  @override
  String workersLogsTailEvent(String scripts) {
    return 'Tail $scripts';
  }

  @override
  String get workersLogsEvent => 'Event';

  @override
  String get workersLogsOverload => 'Too many events: Cloudflare is sampling this stream.';

  @override
  String get workersLogsOverloadStop => 'Sampling stopped: every event is shown again.';

  @override
  String workersLogsLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log lines',
      one: '1 log line',
    );
    return '$_temp0';
  }

  @override
  String workersLogsExceptions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exceptions',
      one: '1 exception',
    );
    return '$_temp0';
  }

  @override
  String get workersOutcomeOk => 'OK';

  @override
  String get workersOutcomeCanceled => 'Canceled';

  @override
  String get workersOutcomeException => 'Exception thrown';

  @override
  String get workersOutcomeCpu => 'Exceeded CPU limit';

  @override
  String get workersOutcomeMemory => 'Exceeded memory limit';

  @override
  String get workersOutcomeUnknown => 'Unknown outcome';

  @override
  String get pagesEmpty => 'No Pages projects in this account.';

  @override
  String get pagesFieldStatus => 'Latest';

  @override
  String get pagesFieldBranch => 'Branch';

  @override
  String get pagesFieldWhen => 'When';

  @override
  String get pagesFieldEnv => 'Environment';

  @override
  String get pagesStatusSuccess => 'Success';

  @override
  String get pagesStatusFailed => 'Failed';

  @override
  String get pagesStatusBuilding => 'Building';

  @override
  String get pagesStatusQueued => 'Queued';

  @override
  String get pagesStatusCanceled => 'Canceled';

  @override
  String get pagesStatusSkipped => 'Skipped';

  @override
  String get pagesStatusUnknown => 'Unknown';

  @override
  String get pagesStatusNone => 'No deploys';

  @override
  String pagesReasonFailed(String branch, String time) {
    return 'Last build on $branch failed $time.';
  }

  @override
  String pagesReasonFailedNoBranch(String time) {
    return 'Last build failed $time.';
  }

  @override
  String get pagesWorkersNote => 'Cloudflare recommends starting new projects on Workers.';

  @override
  String get pagesWorkersNoteLink => 'Migration guide';

  @override
  String get pagesEnvProduction => 'Production';

  @override
  String get pagesEnvPreview => 'Preview';

  @override
  String get pagesLiveMarker => 'Live';

  @override
  String pagesDeploymentSemantics(String id, String status, String environment, String branch, String time) {
    return 'Deployment $id, $status, $environment, branch $branch, $time';
  }

  @override
  String get pagesOpenSite => 'Open site';

  @override
  String get pagesSectionProject => 'Project';

  @override
  String get pagesSite => 'Site';

  @override
  String get pagesProductionBranch => 'Production branch';

  @override
  String get pagesRepository => 'Repository';

  @override
  String get pagesCreated => 'Created';

  @override
  String get pagesSectionDomains => 'Custom domains';

  @override
  String get pagesNoDomains => 'No custom domains.';

  @override
  String get pagesDomainActive => 'Active';

  @override
  String get pagesDomainPending => 'Pending';

  @override
  String get pagesDomainInitializing => 'Setting up';

  @override
  String get pagesDomainBlocked => 'Blocked';

  @override
  String get pagesDomainDeactivated => 'Deactivated';

  @override
  String get pagesDomainError => 'Error';

  @override
  String get pagesSectionDeployments => 'Deployments';

  @override
  String get pagesNoDeployments => 'No deployments yet.';

  @override
  String get pagesDeploymentsHint => 'Touch and hold a deployment to retry, roll back or open it.';

  @override
  String get pagesSectionDeployment => 'Deployment';

  @override
  String get pagesCommit => 'Commit';

  @override
  String get pagesTrigger => 'Trigger';

  @override
  String get pagesTriggerPush => 'Git push';

  @override
  String get pagesTriggerUpload => 'Direct upload';

  @override
  String get pagesTriggerHook => 'Deploy hook';

  @override
  String get pagesAlias => 'Alias';

  @override
  String get pagesSectionStages => 'Stages';

  @override
  String get pagesStageQueued => 'Queued';

  @override
  String get pagesStageInitialize => 'Initialize';

  @override
  String get pagesStageClone => 'Clone repository';

  @override
  String get pagesStageBuild => 'Build';

  @override
  String get pagesStageDeploy => 'Deploy';

  @override
  String get pagesStageSuccess => 'Done';

  @override
  String get pagesStageActive => 'Running';

  @override
  String get pagesStageIdle => 'Waiting';

  @override
  String get pagesStageFailure => 'Failed';

  @override
  String get pagesStageCanceled => 'Canceled';

  @override
  String get pagesStageSkipped => 'Skipped';

  @override
  String get pagesSectionBuildLog => 'Build log';

  @override
  String get pagesLogEmpty => 'This build has no log lines.';

  @override
  String get pagesLogUnavailable => 'Cloudflare has no build log for this deployment (direct uploads don\'t build).';

  @override
  String pagesLogPartial(int shown, int total) {
    return 'Showing $shown of $total lines.';
  }

  @override
  String get pagesOpenDeployment => 'Open this deployment';

  @override
  String get pagesRetry => 'Retry build';

  @override
  String get pagesRetryHint => 'Builds the same commit again as a new deployment';

  @override
  String pagesRetryStarted(String name) {
    return 'New build started for $name.';
  }

  @override
  String get pagesRollbackAction => 'Roll back production to this';

  @override
  String get pagesRollbackHint => 'Production serves this deployment again';

  @override
  String pagesRollbackTitle(String id) {
    return 'Roll back to $id?';
  }

  @override
  String pagesRollbackMessage(String project, String deployment) {
    return 'Production for $project will serve $deployment again. Newer deployments stay in the list, so you can roll forward the same way.';
  }

  @override
  String get pagesRollbackConfirm => 'Roll back';

  @override
  String pagesRollbackDone(String id) {
    return 'Production now serves $id.';
  }

  @override
  String get pagesCopyId => 'Copy deployment ID';

  @override
  String pagesDeploymentOnBranch(String id, String branch) {
    return '$id on $branch';
  }

  @override
  String get registrarTitle => 'Registrar';

  @override
  String get registrarRowTitle => 'Registered domains';

  @override
  String registrarSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count domains, all in line',
      one: '1 domain, in line',
    );
    return '$_temp0';
  }

  @override
  String registrarSummaryAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count domains need you',
      one: '1 domain needs you',
    );
    return '$_temp0';
  }

  @override
  String get registrarSummaryNone => 'No domains registered with Cloudflare';

  @override
  String get registrarSummaryFailed => 'Couldn\'t load registrations';

  @override
  String get registrarAccountTokenShort => 'Not available with account-owned tokens';

  @override
  String registrarNeedsPermission(String permission) {
    return 'Needs “$permission” on the token';
  }

  @override
  String get registrarAccountTokenTitle => 'Registrar needs a user API token';

  @override
  String registrarAccountTokenMessage(String permission) {
    return 'Cloudflare Registrar doesn\'t accept account-owned API tokens. To see expiry dates here, add a user API token with “$permission” in Settings.';
  }

  @override
  String get registrarPermissionTitle => 'No access to Registrar';

  @override
  String registrarPermissionMessage(String permission) {
    return 'Add “$permission” to a user API token in the Cloudflare dashboard, then pull to refresh.';
  }

  @override
  String get registrarFailedTitle => 'Couldn\'t load registered domains';

  @override
  String get registrarEmptyTitle => 'No domains registered with Cloudflare';

  @override
  String get registrarEmptyMessage =>
      'Domains you register or transfer to Cloudflare Registrar show up here with their expiry dates.';

  @override
  String get registrarBayAttention => 'Needs you';

  @override
  String get registrarBayAll => 'In line';

  @override
  String get registrarAllAttention => 'Every registered domain needs a look.';

  @override
  String get registrarFieldExpires => 'Expires';

  @override
  String get registrarFieldAutoRenew => 'Auto-renew';

  @override
  String get registrarFieldLock => 'Transfer lock';

  @override
  String get registrarAutoRenewOn => 'On';

  @override
  String get registrarAutoRenewOff => 'Off';

  @override
  String get registrarLocked => 'Locked';

  @override
  String get registrarUnlocked => 'Unlocked';

  @override
  String registrarExpiresSemantics(String date) {
    return 'expires $date';
  }

  @override
  String registrarReasonExpiring(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expires in $days days and won\'t renew automatically.',
      one: 'Expires tomorrow and won\'t renew automatically.',
    );
    return '$_temp0';
  }

  @override
  String get registrarReasonToday => 'Expires today and won\'t renew automatically.';

  @override
  String registrarReasonStatus(String status) {
    return '$status: renew or restore it in Cloudflare Registrar before it\'s lost.';
  }

  @override
  String get registrarStatusActive => 'Active';

  @override
  String get registrarStatusRegistering => 'Registering';

  @override
  String get registrarStatusTransferring => 'Transferring in';

  @override
  String get registrarStatusExpired => 'Expired';

  @override
  String get registrarStatusSuspended => 'Suspended';

  @override
  String get registrarStatusRedemption => 'In redemption period';

  @override
  String get registrarStatusPendingDelete => 'Pending deletion';

  @override
  String get registrarStatusUnknown => 'Unknown status';

  @override
  String get registrarFooter => 'Turn on auto-renew in the Cloudflare dashboard so a domain never lapses.';

  @override
  String get appName => 'Edgepost';

  @override
  String get tabToday => 'Today';

  @override
  String get tabDomains => 'Domains';

  @override
  String get tabMail => 'Mail';

  @override
  String get tabCompute => 'Compute';

  @override
  String get tabSettings => 'Settings';

  @override
  String get sidebarShow => 'Show sidebar';

  @override
  String get sidebarHide => 'Hide sidebar';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionSave => 'Save';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionDone => 'Done';

  @override
  String get actionClose => 'Close';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionOpen => 'Open';

  @override
  String get copiedToClipboard => 'Copied';

  @override
  String syncedAt(String time) {
    return 'Synced $time';
  }

  @override
  String syncFailed(String time) {
    return 'Couldn\'t refresh. Showing data from $time.';
  }

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '1 h ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: 'yesterday',
    );
    return '$_temp0';
  }

  @override
  String get errorGeneric => 'Something went wrong. Try again in a moment.';

  @override
  String errorPermission(String permission) {
    return 'This token can\'t do that yet. In the Cloudflare dashboard, add the permission “$permission” to the token, then pull to refresh.';
  }

  @override
  String get errorPermissionGeneric =>
      'This token doesn\'t have permission for this. Edit the token in the Cloudflare dashboard and add the missing permission.';

  @override
  String typeToConfirm(String name) {
    return 'Type $name to confirm.';
  }

  @override
  String get fieldRequired => 'Required';

  @override
  String get loading => 'Loading…';

  @override
  String emptySearch(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get searchPlaceholder => 'Search';

  @override
  String get syntheticDataLabel => 'Sample data';

  @override
  String get actionShow => 'Show';

  @override
  String get actionHide => 'Hide';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionSend => 'Send';

  @override
  String timeSecondsAgo(int count) {
    return '$count s ago';
  }

  @override
  String tabBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread',
      one: '1 unread',
    );
    return '$_temp0';
  }

  @override
  String tabNeedsYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need you',
      one: '1 needs you',
    );
    return '$_temp0';
  }

  @override
  String get errorNoToken => 'None of your API tokens reaches this account any more. Add a token for it in Settings.';

  @override
  String get errorNeedsUserToken =>
      'This needs a user API token: Cloudflare doesn\'t accept account-owned tokens here.';

  @override
  String confirmAccount(String name) {
    return 'Account: $name';
  }

  @override
  String get dnsTitle => 'DNS records';

  @override
  String get dnsAddRecord => 'Add record';

  @override
  String get dnsMoreActions => 'Templates, import and export';

  @override
  String dnsSectionHeader(String type, int count) {
    return '$type · $count';
  }

  @override
  String get dnsFilterAll => 'All';

  @override
  String get dnsFilterAddress => 'A·AAAA';

  @override
  String get dnsFilterOther => 'Other';

  @override
  String get dnsSearchPlaceholder => 'Search names and values';

  @override
  String get dnsEmptyTitle => 'No DNS records yet';

  @override
  String get dnsEmptyMessage =>
      'Nothing resolves for this domain yet. Add a record, start from a template, or import a BIND zone file.';

  @override
  String get dnsFilterEmpty => 'No records of this type.';

  @override
  String get dnsZoneMissingTitle => 'Domain not found';

  @override
  String get dnsZoneMissingMessage =>
      'This domain isn\'t in your list anymore. Refresh the Domains tab, or check that its token is still added in Settings.';

  @override
  String get dnsProxied => 'Proxied';

  @override
  String get dnsDnsOnly => 'DNS only';

  @override
  String dnsPriorityShort(int value) {
    return 'Priority $value';
  }

  @override
  String get dnsTtlAuto => 'Auto';

  @override
  String dnsTtlSeconds(int count) {
    return '$count s';
  }

  @override
  String dnsTtlMinutes(int count) {
    return '$count min';
  }

  @override
  String dnsTtlHours(int count) {
    return '$count h';
  }

  @override
  String dnsTtlDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get dnsRowHint => 'Touch and hold for more actions';

  @override
  String get dnsActionCopyName => 'Copy name';

  @override
  String get dnsActionCopyContent => 'Copy value';

  @override
  String get dnsDeleteTitle => 'Delete this record?';

  @override
  String dnsDeleteMessage(String type, String name) {
    return 'The $type record $name stops resolving within its TTL. You can undo right after.';
  }

  @override
  String get dnsDeleted => 'Record deleted';

  @override
  String get dnsRestored => 'Record restored';

  @override
  String dnsRestoreFailed(String reason) {
    return 'Couldn\'t restore the record. $reason';
  }

  @override
  String dnsDeleteFailed(String reason) {
    return 'Couldn\'t delete the record, so it\'s back in the list. $reason';
  }

  @override
  String get dnsSaved => 'Record saved';

  @override
  String get dnsCreated => 'Record added';

  @override
  String dnsSaveFailed(String reason) {
    return 'Couldn\'t save. $reason';
  }

  @override
  String get dnsMenuPointToIp => 'Point domain to an IP';

  @override
  String get dnsMenuVerifyTxt => 'Add a verification TXT';

  @override
  String get dnsMenuMailCheck => 'Check mail records';

  @override
  String get dnsMenuExport => 'Export zone file';

  @override
  String get dnsMenuImport => 'Import zone file';

  @override
  String dnsExportSubject(String zone) {
    return 'DNS records for $zone';
  }

  @override
  String dnsExportFailed(String reason) {
    return 'Couldn\'t export. $reason';
  }

  @override
  String dnsImportTitle(String file) {
    return 'Import $file?';
  }

  @override
  String dnsImportMessage(String zone) {
    return 'Cloudflare adds the records in this BIND file to $zone. Zone files can be up to 256 KiB, and Cloudflare accepts 3 imports per minute.';
  }

  @override
  String get dnsImportDnsOnly => 'Import as DNS only';

  @override
  String get dnsImportProxied => 'Import and proxy eligible records';

  @override
  String dnsImportTooLarge(int size) {
    return 'This file is $size KiB. Cloudflare accepts zone files up to 256 KiB: split it and import each part.';
  }

  @override
  String dnsImportThrottled(int seconds) {
    return 'Cloudflare accepts 3 imports per minute. Try again in $seconds s.';
  }

  @override
  String dnsImportDone(int added, int parsed) {
    return 'Added $added of $parsed records from the file.';
  }

  @override
  String dnsImportFailed(String reason) {
    return 'Couldn\'t import. $reason';
  }

  @override
  String get dnsImportOpenFailed => 'Couldn\'t open that file. Pick a plain-text BIND zone file.';

  @override
  String get dnsEditorNewTitle => 'New record';

  @override
  String get dnsEditorEditTitle => 'Edit record';

  @override
  String get dnsRecordMissingTitle => 'Record not found';

  @override
  String get dnsRecordMissingMessage => 'It may have been deleted or changed elsewhere. Go back and pull to refresh.';

  @override
  String get dnsSectionRecord => 'Record';

  @override
  String get dnsSectionOptions => 'Options';

  @override
  String get dnsFieldType => 'Type';

  @override
  String get dnsTypeOther => 'Other';

  @override
  String get dnsChooseType => 'Record type';

  @override
  String get dnsFieldTypeRaw => 'Record type';

  @override
  String get dnsFieldName => 'Name';

  @override
  String get dnsNamePlaceholder => '@ or subdomain';

  @override
  String dnsNameHelper(String name) {
    return 'Resolves as $name';
  }

  @override
  String get dnsFieldIpv4 => 'IPv4 address';

  @override
  String get dnsFieldIpv6 => 'IPv6 address';

  @override
  String get dnsFieldTarget => 'Target';

  @override
  String dnsTargetHelper(String zone) {
    return 'A hostname. Use @ for $zone.';
  }

  @override
  String get dnsFieldNameserver => 'Nameserver';

  @override
  String get dnsFieldPtr => 'Domain name';

  @override
  String get dnsFieldMailServer => 'Mail server';

  @override
  String get dnsFieldPriority => 'Priority';

  @override
  String get dnsPriorityHelper => '0–65535. Lower numbers are tried first.';

  @override
  String get dnsFieldContent => 'Content';

  @override
  String dnsTxtHelper(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0. Values over 255 characters are split into several strings automatically.';
  }

  @override
  String get dnsFieldService => 'Service';

  @override
  String get dnsServiceHelper => 'The service label, such as _sip or _imaps.';

  @override
  String get dnsFieldProtocol => 'Protocol';

  @override
  String get dnsFieldWeight => 'Weight';

  @override
  String get dnsFieldPort => 'Port';

  @override
  String get dnsSrvTargetHelper => 'The host that offers the service. Use a single dot if it isn\'t offered.';

  @override
  String get dnsFieldCaaTag => 'Tag';

  @override
  String get dnsCaaIssue => 'Issue';

  @override
  String get dnsCaaIssueWild => 'Wildcard';

  @override
  String get dnsCaaIodef => 'Report';

  @override
  String get dnsCaaTagHelp =>
      'Issue lets a certificate authority issue certificates for this name, Wildcard covers wildcard certificates, and Report says where to send violation reports.';

  @override
  String get dnsFieldValue => 'Value';

  @override
  String get dnsFieldFlags => 'Flags';

  @override
  String get dnsFlagsHelper => 'Usually 0. 128 marks the tag as critical.';

  @override
  String get dnsFieldHttpsValue => 'Parameters';

  @override
  String get dnsHttpsValueHelper => 'Service parameters, for example alpn=\"h3,h2\". Optional.';

  @override
  String get dnsFieldUri => 'URI';

  @override
  String get dnsOtherDataNote =>
      'This type stores structured data. Change its value in the Cloudflare dashboard; you can still change the name, TTL and comment here.';

  @override
  String get dnsFieldProxied => 'Proxy through Cloudflare';

  @override
  String get dnsProxiedOnHelp =>
      'Traffic passes through Cloudflare\'s cache and security. Visitors see Cloudflare\'s addresses.';

  @override
  String get dnsProxiedOffHelp => 'DNS only: Cloudflare answers with this value and doesn\'t touch the traffic.';

  @override
  String get dnsProxiedOnFooter =>
      'Traffic passes through Cloudflare\'s cache and security, and visitors see Cloudflare\'s addresses. Proxied records always use Auto TTL.';

  @override
  String get dnsFieldTtl => 'TTL';

  @override
  String get dnsChooseTtl => 'Time to live';

  @override
  String get dnsFieldComment => 'Comment';

  @override
  String get dnsCommentPlaceholder => 'A note for yourself, not published in DNS';

  @override
  String dnsTypeChangeNote(String from) {
    return 'Changing the type replaces the record: the $from record is deleted and the new one created in a single step.';
  }

  @override
  String get dnsDeleteRecord => 'Delete record';

  @override
  String get dnsErrorName =>
      'Use @ for the domain itself, or letters, digits, hyphens and dots. Internationalized names go in punycode (xn--…).';

  @override
  String get dnsErrorIpv4 => 'Enter an IPv4 address such as 203.0.113.10.';

  @override
  String get dnsErrorIpv6 => 'Enter an IPv6 address such as 2001:db8::1.';

  @override
  String get dnsErrorHostname => 'Enter a hostname such as mail.example.com.';

  @override
  String get dnsErrorRange => 'Enter a whole number from 0 to 65535.';

  @override
  String get dnsErrorFlags => 'Enter a whole number from 0 to 255.';

  @override
  String get dnsErrorType => 'Enter a record type in capitals, such as TLSA.';

  @override
  String get dnsErrorQuotes => 'The quotation marks don\'t pair up. Remove them, or wrap each part in its own pair.';

  @override
  String get dnsErrorTooLong => 'The full name is longer than 253 characters.';

  @override
  String get dnsTemplatePointTitle => 'Point to an IP';

  @override
  String dnsTemplatePointIntro(String zone) {
    return 'Sends $zone to your server\'s IP address.';
  }

  @override
  String get dnsTemplateIpLabel => 'Server IP address';

  @override
  String get dnsTemplateIpHelper => 'IPv4 or IPv6.';

  @override
  String get dnsTemplateErrorIp => 'Enter an IPv4 or IPv6 address.';

  @override
  String get dnsTemplateIncludeWww => 'Also point www';

  @override
  String dnsTemplateIncludeWwwHelp(String zone) {
    return 'Adds www.$zone as a CNAME to $zone.';
  }

  @override
  String get dnsTemplateCreates => 'Creates';

  @override
  String get dnsTemplateReplaces => 'Replaces';

  @override
  String get dnsTemplateReplacesFooter => 'These records would conflict, so they\'re removed in the same step.';

  @override
  String dnsTemplateReplaceTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records',
      one: '1 record',
    );
    return 'Replace $_temp0?';
  }

  @override
  String dnsTemplateReplaceMessage(String zone) {
    return 'The current address records for $zone are deleted and the new ones created in a single step.';
  }

  @override
  String get dnsTemplateReplace => 'Replace';

  @override
  String get dnsTemplateApplied => 'Records added';

  @override
  String get dnsTemplateVerifyTitle => 'Verification TXT';

  @override
  String dnsTemplateVerifyIntro(String zone) {
    return 'Services such as Google, Microsoft and Apple ask for a TXT record to prove you own $zone.';
  }

  @override
  String get dnsTemplateVerifyHelper => 'Paste the exact value the service gave you.';

  @override
  String get dnsMailTitle => 'Mail records';

  @override
  String dnsMailIntro(String zone) {
    return 'A read-only check of the records that decide where mail for $zone goes and whether mail from it is trusted.';
  }

  @override
  String get dnsMailMx => 'Receiving (MX)';

  @override
  String get dnsMailSpf => 'Allowed senders (SPF)';

  @override
  String get dnsMailDmarc => 'Policy (DMARC)';

  @override
  String get dnsMailDkim => 'Signatures (DKIM)';

  @override
  String get dnsMailStatusOk => 'Present';

  @override
  String get dnsMailStatusWarn => 'Needs a look';

  @override
  String get dnsMailStatusMissing => 'Missing';

  @override
  String dnsMailMxOk(String zone) {
    return 'Mail for $zone goes to the servers below, lowest priority first.';
  }

  @override
  String dnsMailMxRouting(String zone) {
    return 'Cloudflare Email Routing receives mail for $zone.';
  }

  @override
  String dnsMailMxMissing(String zone) {
    return 'Nobody can send mail to $zone. Turn on Email Routing, or add the MX records your mail provider gives you.';
  }

  @override
  String dnsMailMxNull(String zone) {
    return 'This null MX record says $zone accepts no mail. Remove it if you want to receive mail here.';
  }

  @override
  String dnsMailSpfOk(String zone) {
    return 'Receivers can check which servers may send mail as $zone.';
  }

  @override
  String dnsMailSpfMissing(String zone) {
    return 'Without SPF, mail from $zone is more likely to land in spam, and anyone can pose as you. Add the SPF record your mail provider gives you, or v=spf1 -all if this domain never sends mail.';
  }

  @override
  String get dnsMailSpfMultiple =>
      'There are several SPF records. Receivers treat that as an error, so merge them into one.';

  @override
  String dnsMailSpfPassAll(String zone) {
    return 'This SPF record lets any server send as $zone. End it with ~all or -all instead.';
  }

  @override
  String get dnsMailDmarcOk => 'Receivers know what to do with mail that fails SPF and DKIM.';

  @override
  String get dnsMailDmarcNone =>
      'The policy is p=none, so receivers only report failures. Move to quarantine or reject once the reports look clean.';

  @override
  String dnsMailDmarcMissing(String zone) {
    return 'Without DMARC, receivers decide on their own what to do with forged mail from $zone. Start with a monitoring policy.';
  }

  @override
  String get dnsMailDmarcMultiple => 'There are several DMARC records at _dmarc. Keep exactly one.';

  @override
  String dnsMailDkimOk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signing keys published.',
      one: '1 signing key published.',
    );
    return '$_temp0';
  }

  @override
  String dnsMailDkimMissing(String zone) {
    return 'No DKIM keys under _domainkey. If you send mail from $zone, add the DKIM record your mail provider gives you.';
  }

  @override
  String get dnsMailAddDmarc => 'Add a monitoring DMARC record';

  @override
  String get routingTitle => 'Email routing';

  @override
  String get routingStripCaption => 'Email routing';

  @override
  String get routingFieldStatus => 'Status';

  @override
  String get routingFieldRules => 'Rules';

  @override
  String get routingFieldCatchAll => 'Catch-all';

  @override
  String get routingStatusReady => 'Ready';

  @override
  String get routingStatusOff => 'Off';

  @override
  String get routingStatusMisconfigured => 'Misconfigured';

  @override
  String get routingStatusUnlocked => 'Unlocked';

  @override
  String get routingReasonOff => 'Routing is off. Turn it on to receive mail at this domain through Cloudflare.';

  @override
  String get routingReasonMisconfigured =>
      'DNS records don\'t match what Email Routing needs, so mail may not arrive. Add the missing records below.';

  @override
  String get routingReasonUnlocked =>
      'Routing records are unlocked and can be changed. Lock them again when you\'re done.';

  @override
  String routingReasonUnverified(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules wait on unverified destinations and can\'t deliver yet.',
      one: '1 rule waits on an unverified destination and can\'t deliver yet.',
    );
    return '$_temp0';
  }

  @override
  String get routingEnableHeader => 'Turn on Email Routing';

  @override
  String routingEnableExplain(String domain) {
    return 'Cloudflare adds the MX and SPF records $domain needs and locks them so other DNS edits can\'t break delivery. Mail for $domain then arrives at Cloudflare instead of any other mail provider.';
  }

  @override
  String get routingEnableRecordsFooter => 'Cloudflare adds these records when you turn routing on.';

  @override
  String get routingEnableAction => 'Turn on routing';

  @override
  String routingEnableConfirmTitle(String domain) {
    return 'Turn on routing for $domain?';
  }

  @override
  String routingEnableConfirmMessage(String domain) {
    return 'Cloudflare adds and locks the routing records. Mail for $domain stops reaching any other mail provider.';
  }

  @override
  String get routingEnabledToast => 'Email routing is on.';

  @override
  String get routingMisconfiguredExplain =>
      'Cloudflare can add the missing MX and SPF records and lock them. If this domain used another mail provider, remove its MX records in DNS first.';

  @override
  String get routingRepairAction => 'Add missing records';

  @override
  String get routingRepairedToast => 'Records added and locked.';

  @override
  String get routingUnlockedExplain =>
      'The MX and SPF records are unlocked, so DNS edits can change them. Lock them again to protect mail delivery.';

  @override
  String get routingLockAction => 'Lock records';

  @override
  String get routingRulesHeader => 'Addresses';

  @override
  String routingRulesCount(int count, int max) {
    return '$count of $max rules used.';
  }

  @override
  String get routingRulesOffFooter => 'Rules take effect once routing is on.';

  @override
  String get routingRulesEmptyTitle => 'No address rules yet';

  @override
  String routingRulesEmptyMessage(String domain) {
    return 'Add one to send mail for an address at $domain to an inbox, your Edgepost mailbox, or nowhere.';
  }

  @override
  String get routingAddRule => 'New address rule';

  @override
  String get routingRuleArrow => '→';

  @override
  String get routingRuleOffNote => 'Off.';

  @override
  String get routingRuleUnverifiedNote => 'Destination not verified, so this rule can\'t deliver yet.';

  @override
  String get routingRuleWranglerNote => 'Managed by a Worker\'s Wrangler config.';

  @override
  String get routingRuleTurnOff => 'Turn off';

  @override
  String get routingRuleTurnOn => 'Turn on';

  @override
  String routingRuleTurnedOff(String address) {
    return '$address is off.';
  }

  @override
  String routingRuleTurnedOn(String address) {
    return '$address is on.';
  }

  @override
  String routingRuleDeleteTitle(String address) {
    return 'Delete $address?';
  }

  @override
  String get routingRuleDeleteMessage =>
      'Mail to this address is no longer routed by this rule. The catch-all handles it if it\'s on.';

  @override
  String routingRuleDeleted(String address) {
    return 'Deleted $address.';
  }

  @override
  String routingRuleSaved(String address) {
    return 'Saved $address.';
  }

  @override
  String get routingCatchAllHeader => 'Everything else';

  @override
  String get routingCatchAllTitle => 'Catch-all';

  @override
  String routingCatchAllFooter(String domain) {
    return 'Handles mail to any address at $domain that has no rule of its own, including typos.';
  }

  @override
  String get routingCatchAllOffLine => 'Off. Mail to addresses without a rule isn\'t delivered.';

  @override
  String get routingCatchAllOffShort => 'Off';

  @override
  String get routingCatchAllSheetTitle => 'Catch-all';

  @override
  String routingCatchAllSheetMessage(String domain) {
    return 'What happens to mail for addresses at $domain that have no rule?';
  }

  @override
  String get routingCatchAllOff => 'Off';

  @override
  String get routingCatchAllForward => 'Forward to…';

  @override
  String get routingCatchAllDrop => 'Drop';

  @override
  String get routingCatchAllSaved => 'Catch-all updated.';

  @override
  String get routingActionForward => 'Forward';

  @override
  String get routingActionMailbox => 'Mailbox';

  @override
  String get routingActionWorker => 'Worker';

  @override
  String get routingActionDrop => 'Drop';

  @override
  String get routingActionUnknown => 'Other';

  @override
  String get routingDestMailbox => 'Edgepost mailbox';

  @override
  String routingDestWorker(String name) {
    return 'Worker $name';
  }

  @override
  String get routingDestDropped => 'Dropped';

  @override
  String get routingDestinationsLink => 'Destination addresses';

  @override
  String routingPendingCount(int count) {
    return '$count waiting for verification';
  }

  @override
  String get routingPickDestinationTitle => 'Forward to';

  @override
  String get routingPickDestinationUnavailable =>
      'Destination addresses couldn\'t be loaded. Add one here, or check that the token has Email Routing Addresses permission.';

  @override
  String routingPendingAddress(String address) {
    return '$address (waiting for verification)';
  }

  @override
  String get routingAddAddressEllipsis => 'Add address…';

  @override
  String get routingAddAddress => 'Add address';

  @override
  String get routingAddAddressTitle => 'Add destination address';

  @override
  String get routingAddAddressMessage =>
      'Cloudflare emails this address a link. Mail is forwarded to it only after the owner clicks it.';

  @override
  String get routingAddressPlaceholder => 'you@example.com';

  @override
  String get routingAddressInvalid => 'Enter a full email address, like you@example.com.';

  @override
  String routingAddressAddedToast(String email) {
    return 'Cloudflare sent a verification link to $email.';
  }

  @override
  String get routingAuthHeader => 'Mail authentication';

  @override
  String get routingAuthLoadFailed => 'Couldn\'t check mail authentication';

  @override
  String get routingAuthNeedsDnsTitle => 'DNS access needed to check SPF, DKIM and DMARC';

  @override
  String routingAuthNoDmarcPermission(String permission) {
    return 'Add “$permission” to the token to also see SPF lookup counts and DMARC report status.';
  }

  @override
  String get routingAuthSpf => 'SPF';

  @override
  String get routingAuthDkim => 'DKIM';

  @override
  String get routingAuthDmarc => 'DMARC';

  @override
  String get routingAuthMx => 'MX';

  @override
  String get routingAuthStateOk => 'Passing';

  @override
  String get routingAuthStateAttention => 'Needs attention';

  @override
  String get routingAuthStateMissing => 'Missing';

  @override
  String get routingAuthStateUnknown => 'Unknown';

  @override
  String routingAuthCopySuggestion(String kind) {
    return 'Copy suggested $kind record';
  }

  @override
  String get routingAuthUnknownAdvice => 'Couldn\'t be checked.';

  @override
  String get routingAuthSpfOk => 'Published and valid.';

  @override
  String routingAuthSpfOkLookups(int count) {
    return 'Published and valid. Uses $count of 10 DNS lookups.';
  }

  @override
  String get routingAuthSpfMissing => 'No SPF record, so receivers can\'t tell which servers may send as this domain.';

  @override
  String get routingAuthSpfMissingRouting =>
      'No SPF record. Copy Cloudflare\'s record and add it as a TXT record on the domain.';

  @override
  String get routingAuthSpfMultiple =>
      'More than one SPF record, which receivers treat as an error. Replace them with the merged record.';

  @override
  String get routingAuthSpfNoCloudflare =>
      'Doesn\'t include Cloudflare\'s mail servers. Copy the updated record, which adds include:_spf.mx.cloudflare.net.';

  @override
  String get routingAuthSpfPassAll =>
      'Ends in +all, which lets any server send as this domain. Copy the record ending in ~all instead.';

  @override
  String routingAuthSpfTooManyLookups(int count) {
    return 'Needs $count DNS lookups; the limit is 10, so SPF fails. Remove includes you no longer use.';
  }

  @override
  String routingAuthSpfInvalid(String detail) {
    return 'Cloudflare couldn\'t evaluate it: $detail';
  }

  @override
  String get routingAuthDkimOk => 'Email Routing\'s signing key (cf2024-1) is published.';

  @override
  String get routingAuthDkimMissing => 'No Email Routing signing key. Cloudflare adds it when routing is turned on.';

  @override
  String get routingAuthDkimMissingRouting =>
      'Email Routing\'s signing key (cf2024-1) is missing. Copy it and add it as a TXT record at cf2024-1._domainkey.';

  @override
  String routingAuthDkimOther(String selectors) {
    return 'Keys published for: $selectors.';
  }

  @override
  String get routingAuthDmarcOk => 'Enforced: spoofed mail is quarantined or rejected.';

  @override
  String get routingAuthDmarcNoReports =>
      'Enforced. Reports don\'t reach Cloudflare; turn on DMARC Management in the dashboard to see who sends as this domain.';

  @override
  String get routingAuthDmarcCname => 'Published through a CNAME and valid.';

  @override
  String get routingAuthDmarcMissing =>
      'No DMARC policy. Add one at _dmarc: start with p=none to monitor, then move to quarantine.';

  @override
  String get routingAuthDmarcMultiple => 'More than one DMARC record, so receivers ignore them all. Keep one.';

  @override
  String get routingAuthDmarcNone =>
      'Policy is none, so spoofed mail still gets delivered. Move to p=quarantine once your senders pass.';

  @override
  String get routingAuthDmarcInvalid => 'The record has no valid policy (p=none, quarantine or reject). Replace it.';

  @override
  String routingAuthDmarcReportIssue(String status) {
    return 'DMARC reports need a fix ($status). Check DMARC Management in the Cloudflare dashboard.';
  }

  @override
  String routingAuthForeignMx(String hosts) {
    return 'Other MX hosts ($hosts) compete with Cloudflare\'s, so some mail skips your rules. Remove them in DNS.';
  }

  @override
  String get routingCopyRecordHint => 'Copies the record value';

  @override
  String get routingDnsHeader => 'Routing DNS records';

  @override
  String get routingDnsLockedFooter => 'Locked by Email Routing, so DNS edits can\'t change them.';

  @override
  String get routingDnsUnlockedFooter => 'Unlocked: DNS edits can change these records.';

  @override
  String routingDnsPriority(int priority) {
    return 'Priority $priority';
  }

  @override
  String get routingUnlockAction => 'Unlock records';

  @override
  String get routingUnlockConfirmTitle => 'Unlock routing records?';

  @override
  String get routingUnlockConfirmMessage =>
      'The MX and SPF records become editable. A wrong edit can stop mail from arriving. Lock them again when you\'re done.';

  @override
  String get routingDisableAction => 'Turn off Email Routing';

  @override
  String get routingDisableFooter =>
      'Removes the MX records Email Routing added. Mail to every address at this domain stops arriving.';

  @override
  String get routingDisableConfirmTitle => 'Turn off Email Routing?';

  @override
  String routingDisableConfirmMessage(String domain) {
    return 'Cloudflare removes the MX records it added for $domain. Mail to every address there, including your Edgepost mailbox, stops arriving until you turn routing back on.';
  }

  @override
  String get routingDisabledToast => 'Email routing is off.';

  @override
  String get routingEditorNewTitle => 'New address';

  @override
  String get routingEditorEditTitle => 'Edit address';

  @override
  String get routingEditorGoneTitle => 'This rule no longer exists';

  @override
  String get routingEditorGoneMessage => 'It was deleted, perhaps from another device or the Cloudflare dashboard.';

  @override
  String get routingEditorAddressLabel => 'Address';

  @override
  String get routingEditorAddressPlaceholder => 'contact';

  @override
  String get routingEditorAddressHelp => 'The part before the @.';

  @override
  String routingEditorAddressPreview(String address) {
    return 'Mail to $address';
  }

  @override
  String get routingEditorAddressRequired => 'Enter the part before the @.';

  @override
  String get routingEditorAddressTooLong => 'Too long: up to 64 characters before the @, and 90 for the whole address.';

  @override
  String get routingEditorAddressInvalid =>
      'Use letters, numbers and symbols like . _ + - with no spaces, and no dot at the start, the end or twice in a row.';

  @override
  String get routingEditorDuplicate => 'This address already has a rule. Edit that one instead.';

  @override
  String routingEditorLimit(int max) {
    return 'This domain has $max rules, Cloudflare\'s limit. Delete one, or use the catch-all.';
  }

  @override
  String get routingEditorActionLabel => 'When mail arrives';

  @override
  String get routingEditorForwardHelp => 'Forward it to an address you own, such as your personal inbox.';

  @override
  String routingEditorMailboxHelp(String worker) {
    return 'Keep it in your Edgepost mailbox, the $worker Worker in your account. Set up the mailbox in the Mail tab first.';
  }

  @override
  String routingEditorWorkerHelp(String worker) {
    return 'Handled by the Worker $worker.';
  }

  @override
  String get routingEditorDropHelp => 'Discard mail sent to this address.';

  @override
  String get routingEditorDeliverTo => 'Forward to';

  @override
  String get routingEditorDestFooter => 'Destination addresses belong to the account and work for every domain in it.';

  @override
  String routingEditorPendingFooter(String email) {
    return '$email isn\'t verified yet. The rule can\'t deliver until its owner clicks the link Cloudflare emailed.';
  }

  @override
  String get routingEditorPickDestination => 'Choose where to forward mail.';

  @override
  String get routingEditorEnabled => 'Rule on';

  @override
  String get routingEditorEnabledHelp => 'Turn off to pause this address without deleting it.';

  @override
  String get routingEditorDelete => 'Delete rule';

  @override
  String get routingSelected => 'Selected';

  @override
  String get routingAddressesTitle => 'Destination addresses';

  @override
  String get routingAddressesEmptyTitle => 'No destination addresses';

  @override
  String get routingAddressesEmptyMessage =>
      'Add an inbox you own. Cloudflare emails it a link, and forwarding starts once the owner clicks it.';

  @override
  String get routingAddressesPendingHeader => 'Waiting for verification';

  @override
  String get routingAddressesPendingFooter =>
      'Each owner must click the link Cloudflare emailed. Edgepost can\'t resend it, because Cloudflare\'s API has no way to; resend it from the Cloudflare dashboard.';

  @override
  String get routingAddressesVerifiedHeader => 'Verified';

  @override
  String routingAddressesAccountNote(String account) {
    return 'These addresses belong to the account $account and work for every domain in it.';
  }

  @override
  String get routingAddressVerified => 'Verified';

  @override
  String routingAddressVerifiedOn(String date) {
    return 'Verified $date';
  }

  @override
  String get routingAddressWaiting => 'Waiting for verification';

  @override
  String routingAddressWaitingSince(String date) {
    return 'Waiting for verification since $date';
  }

  @override
  String routingAddressDeleteTitle(String email) {
    return 'Delete $email?';
  }

  @override
  String get routingAddressDeleteMessage => 'Rules that forward to it stop delivering mail.';

  @override
  String routingAddressDeleteUsed(int count, String domain) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rules on $domain forward to it and will stop delivering mail.',
      one: '1 rule on $domain forwards to it and will stop delivering mail.',
    );
    return '$_temp0';
  }

  @override
  String routingAddressDeleted(String email) {
    return 'Deleted $email.';
  }

  @override
  String get mailAllInboxes => 'All inboxes';

  @override
  String get mailFolderInbox => 'Inbox';

  @override
  String get mailFolderSent => 'Sent';

  @override
  String get mailFolderArchive => 'Archive';

  @override
  String get mailFolderTrash => 'Trash';

  @override
  String get mailCompose => 'New message';

  @override
  String get mailReply => 'Reply';

  @override
  String get mailReplyAll => 'Reply all';

  @override
  String get mailForward => 'Forward';

  @override
  String get mailArchive => 'Archive';

  @override
  String get mailMoveToInbox => 'Move to inbox';

  @override
  String get mailTrash => 'Move to trash';

  @override
  String get mailDeleteForever => 'Delete forever';

  @override
  String get mailDeleteForeverConfirm => 'Delete this message forever? It can\'t be recovered.';

  @override
  String get mailMarkRead => 'Mark as read';

  @override
  String get mailMarkUnread => 'Mark as unread';

  @override
  String get mailStar => 'Star';

  @override
  String get mailUnstar => 'Remove star';

  @override
  String get mailArchived => 'Archived';

  @override
  String get mailTrashed => 'Moved to trash';

  @override
  String get mailMoved => 'Moved to inbox';

  @override
  String get mailDeleted => 'Deleted';

  @override
  String mailUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread',
      one: '1 unread',
      zero: 'No unread mail',
    );
    return '$_temp0';
  }

  @override
  String get mailEmptyInbox => 'Inbox zero. Nothing waiting on you.';

  @override
  String mailEmptyFolder(String folder) {
    return 'Nothing in $folder.';
  }

  @override
  String get mailLoadMore => 'Load older messages';

  @override
  String get mailFieldTo => 'To';

  @override
  String get mailFieldFrom => 'From';

  @override
  String get mailFieldCc => 'Cc';

  @override
  String get mailFieldBcc => 'Bcc';

  @override
  String get mailFieldSubject => 'Subject';

  @override
  String mailToPrefix(String name) {
    return 'To $name';
  }

  @override
  String get mailNoSubject => '(no subject)';

  @override
  String get mailSetupTitle => 'Your domain mailbox';

  @override
  String get mailSetupIntro =>
      'Read, reply to and send mail on your own domains. Edgepost deploys a small mail service into your Cloudflare account: incoming mail is stored in your account\'s D1 and R2, and you send through Cloudflare Email Sending. Nothing passes through anyone else\'s server.';

  @override
  String get mailSetupStart => 'Set up mailbox';

  @override
  String get mailSetupRequirements => 'What it needs';

  @override
  String get mailSetupReqToken => 'A token with Workers Scripts, D1, Workers R2 Storage and Email Routing permissions';

  @override
  String get mailSetupReqR2 => 'R2 turned on for the account (once, in the Cloudflare dashboard)';

  @override
  String get mailSetupReqPaid =>
      'To send to any address: the Workers Paid plan. Email Sending is in public beta. Receiving works on every plan.';

  @override
  String get mailSetupDomains => 'Domains';

  @override
  String get mailSetupDomainsHelp => 'Mail to these domains lands in Edgepost.';

  @override
  String get mailSetupRouting => 'Which addresses';

  @override
  String get mailSetupCatchAll => 'Every address (catch-all)';

  @override
  String get mailSetupSpecific => 'Only these addresses';

  @override
  String get mailSetupAddressesHelp => 'Local parts, separated by commas, e.g. contact, billing';

  @override
  String get mailSetupSending => 'Enable sending';

  @override
  String get mailSetupSendingHelp =>
      'Onboards each domain to Cloudflare Email Sending and adds its DNS records (cf-bounce MX, SPF and DKIM).';

  @override
  String get mailSetupRun => 'Deploy and connect';

  @override
  String get mailSetupRunning => 'Setting up…';

  @override
  String get mailSetupDone => 'Your mailbox is ready';

  @override
  String get mailSetupDoneBody => 'Send yourself a message at one of your addresses to see it arrive.';

  @override
  String get mailSetupOpenInbox => 'Open inbox';

  @override
  String get mailSetupRetry => 'Retry from this step';

  @override
  String get mailStepPermissions => 'Check token permissions';

  @override
  String get mailStepD1 => 'Create D1 database';

  @override
  String get mailStepR2 => 'Create R2 bucket';

  @override
  String get mailStepUpload => 'Upload mail Worker';

  @override
  String get mailStepPublish => 'Publish on workers.dev';

  @override
  String get mailStepSchedule => 'Schedule trash clean-up';

  @override
  String get mailStepConnect => 'Connect to the mail service';

  @override
  String mailStepRoute(String domain) {
    return 'Route mail for $domain';
  }

  @override
  String mailStepSending(String domain) {
    return 'Enable sending for $domain';
  }

  @override
  String get mailStepSave => 'Save on this device';

  @override
  String get mailErrNoSubdomain =>
      'This account has no workers.dev subdomain yet. In the Cloudflare dashboard open Workers & Pages once to choose one, then retry.';

  @override
  String get mailErrR2Disabled =>
      'R2 isn\'t turned on for this account. Open R2 in the Cloudflare dashboard and enable it (the free tier is enough), then retry.';

  @override
  String get mailErrHealth =>
      'The Worker was uploaded but isn\'t answering yet. New workers.dev addresses can take a minute. Retry shortly.';

  @override
  String get mailServiceTitle => 'Mail service';

  @override
  String mailServiceVersion(String version) {
    return 'Version $version';
  }

  @override
  String get mailServiceUpdate => 'Update mail service';

  @override
  String mailServiceUpdateAvailable(String version) {
    return 'An update is available ($version).';
  }

  @override
  String get mailServiceAddDomains => 'Add domains';

  @override
  String get mailServiceForget => 'Disconnect from this device';

  @override
  String get mailServiceForgetBody =>
      'Edgepost forgets this mail service on this device. The Worker and your stored mail stay in your Cloudflare account.';

  @override
  String get mailServiceUrl => 'Endpoint';

  @override
  String get mailServiceDomains => 'Domains';

  @override
  String get mailSetupNoService => 'No mailbox yet';

  @override
  String get mailSetupNoServiceBody =>
      'Deploy your mail service once and every domain you pick gets a real inbox you can answer from.';

  @override
  String get mailRemoteImagesBlocked => 'Remote images are blocked to stop tracking.';

  @override
  String get mailLoadImages => 'Load images';

  @override
  String get mailOpenLinkTitle => 'Open link?';

  @override
  String mailOpenLinkBody(String url) {
    return 'This link goes to:\n$url';
  }

  @override
  String mailAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String get mailShowQuoted => 'Show quoted text';

  @override
  String get mailIncludeQuote => 'Include original message';

  @override
  String get mailIncludeAttachments => 'Include original attachments';

  @override
  String get mailAddAttachment => 'Attach files';

  @override
  String get mailRecipientsRequired => 'Add at least one recipient.';

  @override
  String mailInvalidAddress(String value) {
    return '“$value” isn\'t a valid email address.';
  }

  @override
  String get mailSent => 'Sent';

  @override
  String get mailSending => 'Sending…';

  @override
  String get mailDiscardTitle => 'Discard this message?';

  @override
  String get mailDiscard => 'Discard';

  @override
  String get mailSaveDraft => 'Save draft';

  @override
  String get mailDraftRestored => 'Draft restored';

  @override
  String get mailBodyPlaceholder => 'Write your message';

  @override
  String get mailRecipientsPlaceholder => 'name@example.com';

  @override
  String get mailErrRecipientNotAllowed =>
      'Cloudflare refused this recipient. Sending to outside addresses needs the Workers Paid plan and the sending domain onboarded to Email Sending.';

  @override
  String mailErrSenderDomain(String domain) {
    return '$domain isn\'t onboarded to Email Sending yet. Run “Enable sending” in Mail service settings.';
  }

  @override
  String get mailErrSenderNotAllowed => 'You can only send from domains connected to your mail service.';

  @override
  String get mailErrSuppressed =>
      'This recipient is on Cloudflare\'s suppression list after earlier bounces or complaints.';

  @override
  String get mailErrSendingLimit => 'Sending limit reached. Cloudflare raises it gradually; try again later.';

  @override
  String get mailErrTooLarge => 'The message is too large to send (5 MB limit including attachments).';

  @override
  String get mailErrDelivery => 'Cloudflare couldn\'t deliver the message. Try again in a moment.';

  @override
  String mailErrInvalid(String detail) {
    return 'Cloudflare rejected the message format: $detail';
  }

  @override
  String mailNotifNewMany(int count) {
    return '$count new messages';
  }

  @override
  String get mailNotifChannel => 'New mail';

  @override
  String get mailNotifChannelDescription => 'A new message arrived at one of your domain addresses.';

  @override
  String get mailIdentityName => 'Display name';

  @override
  String get mailSearchPlaceholder => 'Search mail';

  @override
  String mailThreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String mailAttachmentFailed(String error) {
    return 'Couldn\'t open the attachment: $error';
  }

  @override
  String get mailYesterday => 'Yesterday';

  @override
  String get mailUnread => 'Unread';

  @override
  String get mailStarred => 'Starred';

  @override
  String get mailBudgetTitle => 'Sending budget';

  @override
  String get mailBudgetExplain =>
      'Workers Paid includes 3,000 sent emails a month. Beyond that Cloudflare charges \$0.35 per 1,000 and has no spending cap, so your mail service stops at the limit you set here. It counts every recipient over the last 31 days. Receiving is always free.';

  @override
  String get mailBudgetLimit => 'Monthly sending limit';

  @override
  String get mailBudgetOff => 'Off (receive only)';

  @override
  String mailBudgetValue(String count) {
    return '$count recipients';
  }

  @override
  String mailBudgetIncluded(String count) {
    return '$count recipients (included in Workers Paid)';
  }

  @override
  String mailBudgetUsage(String used, String limit) {
    return 'Sent in the last 31 days: $used of $limit';
  }

  @override
  String mailBudgetResets(String date) {
    return 'Room frees up from $date.';
  }

  @override
  String get mailBudgetSaved => 'Sending limit updated';

  @override
  String get mailErrMonthlyLimit =>
      'You\'ve reached your sending limit for the last 31 days. Raise it in Settings → Mail service, or wait for older sends to drop out of the window.';

  @override
  String get mailSetupBlockedDenied =>
      'The token is missing a permission mail needs. Add it in the Cloudflare dashboard (My Profile → API Tokens → Edit), then check again.';

  @override
  String get mailSetupBlockedR2 =>
      'Turn on R2 for this account first (one-time, free tier included), then check again.';

  @override
  String mailSendingPending(String records) {
    return 'Sending is set up. Cloudflare is still publishing these records: $records. This usually takes 5–15 minutes. If they don\'t appear, open the domain under Compute → Email Service → Email Sending in the dashboard.';
  }

  @override
  String mailCloudflareSaid(String message) {
    return 'Cloudflare said: $message';
  }

  @override
  String get mailDnsCheckTitle => 'Mail DNS check';

  @override
  String get mailDnsCheckHelp =>
      'Each domain must have exactly one DMARC record and one SPF record per name. Extra copies make receivers ignore them.';

  @override
  String get mailDnsCheckClean => 'No duplicate DMARC or SPF records.';

  @override
  String get mailDnsCheckRunning => 'Checking DNS…';

  @override
  String mailDnsDupDmarc(int count) {
    return '$count DMARC records at _dmarc: keep one, delete the others.';
  }

  @override
  String mailDnsDupSpf(int count, String name) {
    return '$count SPF records at $name: keep one, delete the others.';
  }

  @override
  String mailDnsAddedOn(String date) {
    return 'added $date';
  }

  @override
  String get mailHealthTitle => 'Sending health';

  @override
  String mailHealthIntro(int days) {
    return 'What happened to each email you sent in the last $days days. Cloudflare\'s targets: deliver above 95%, hard bounces under 2%.';
  }

  @override
  String get mailHealthDelivered => 'Delivered';

  @override
  String get mailHealthFailed => 'Failed';

  @override
  String get mailHealthRate => 'Rate';

  @override
  String mailHealthNoSends(int days) {
    return 'Nothing sent from this domain in the last $days days.';
  }

  @override
  String get mailHealthLowRate =>
      'Delivery is below Cloudflare\'s 95% target. Fix the causes below before sending more.';

  @override
  String get mailHealthAllGood => 'Every recent send was delivered.';

  @override
  String mailHealthAuth(String spf, String dkim, String dmarc) {
    return 'SPF $spf · DKIM $dkim · DMARC $dmarc';
  }

  @override
  String get mailHealthHintAuth =>
      'Authentication failed: receivers reject mail that fails SPF, DKIM or DMARC. Run the Mail DNS check, make sure each name has only one SPF and one DMARC record, and wait until the sending records are published.';

  @override
  String get mailHealthHintUnknownUser =>
      'The address doesn\'t exist. Check it for typos; Cloudflare stops sending to it for a while.';

  @override
  String get mailHealthHintSpam => 'The receiver flagged this message as spam.';

  @override
  String get mailHealthHintOther => 'Not delivered. The receiving server\'s reason is below.';

  @override
  String get mailHealthPause => 'Pause sending';

  @override
  String get mailHealthPauseBody =>
      'Sets your sending limit to Off, so nothing more is sent until you raise it again in Mail service. Receiving keeps working.';

  @override
  String get mailHealthPaused => 'Sending paused';

  @override
  String get mailHealthOpen => 'Sending health';

  @override
  String get mailHealthOpenHelp => 'Delivery rate, bounces and why each failed send failed.';

  @override
  String get mailFromTitle => 'Send from';

  @override
  String get mailFromSearch => 'Search addresses';

  @override
  String get mailFromRecent => 'Recent';

  @override
  String get mailFromOtherTitle => 'Another address';

  @override
  String get mailFromOtherHelp => 'Any address on your domains works. Replies to it land in Edgepost.';

  @override
  String get mailFromLocalHint => 'name';

  @override
  String get mailFromUse => 'Use this address';

  @override
  String get mailFromInvalid => 'Use letters, numbers, dots, dashes or underscores.';

  @override
  String get mailFromNameTitle => 'Name and signature';

  @override
  String mailFromNameHelp(String address) {
    return 'Shown to recipients for $address.';
  }

  @override
  String mailFromNoMatch(String query) {
    return 'No address matches “$query”.';
  }

  @override
  String get mailAttachPhoto => 'Photo or video';

  @override
  String get mailAttachFile => 'File';

  @override
  String mailAttachTooBig(String name, String size, String room) {
    return '$name is too big: $size won\'t fit. $room left in this message.';
  }

  @override
  String mailAttachFailed(String error) {
    return 'Couldn\'t add the file: $error';
  }

  @override
  String mailSizeAsSent(String used) {
    return '$used of 5 MB as sent';
  }

  @override
  String get mailSizeOver =>
      'Over Cloudflare\'s 5 MB limit (attachments grow about a third when encoded). Remove an attachment.';

  @override
  String get mailSendFailedTitle => 'Couldn\'t send';

  @override
  String mailErrorDetails(String details) {
    return 'Details: $details';
  }

  @override
  String get mailErrOffline => 'You\'re offline. The message is kept as a draft.';

  @override
  String get mailErrTimeout =>
      'Your mail service is taking too long. If the message went out it won\'t be sent twice: try again.';

  @override
  String mailErrUnavailable(int status) {
    return 'Your mail service is temporarily unavailable (Cloudflare $status). Try again in a moment.';
  }

  @override
  String mailToAddress(String address) {
    return 'to $address';
  }

  @override
  String mailFromAddress(String address) {
    return 'from $address';
  }

  @override
  String get mailHasAttachment => 'Has attachments';

  @override
  String get mailAddCcBcc => 'Add Cc or Bcc';

  @override
  String mailSendsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sends left before your sending limit.',
      one: '1 send left before your sending limit.',
      zero: 'Sending limit reached: this message won\'t go out until older sends leave the 31-day window.',
    );
    return '$_temp0';
  }

  @override
  String mailFromEditFor(String address) {
    return 'Name and signature for $address';
  }

  @override
  String mailChooseInbox(String scope) {
    return 'Showing $scope. Choose inbox';
  }

  @override
  String get mailHealthEmpty => 'No sending domains yet';

  @override
  String get mailHealthEmptyBody =>
      'Once you send from one of your domains, delivered, bounced and failed messages show up here.';

  @override
  String mailYouTo(String name) {
    return 'You → $name';
  }

  @override
  String get mailSignature => 'Signature';

  @override
  String get mailSignaturePlaceholder => 'Add a signature to this message';

  @override
  String get mailSignatureReset => 'Reset';

  @override
  String get mailSignatureThisMessage => 'Changes here are for this message only.';

  @override
  String get mailSignatureEditedHere => 'Changed for this message only.';

  @override
  String get mailSignatureLogo => 'Logo';

  @override
  String mailSignatureLogoLabel(String domain) {
    return 'The $domain logo';
  }

  @override
  String mailSignatureEditDefault(String domain) {
    return 'Edit the default for $domain';
  }

  @override
  String get mailBrandTitle => 'Signature & logo';

  @override
  String get mailBrandLogo => 'Logo';

  @override
  String get mailBrandLogoHelp =>
      'Shown above your signature in mail you send. Any photo or image works; it\'s resized to fit 240 × 48.';

  @override
  String get mailBrandChooseLogo => 'Choose image';

  @override
  String get mailBrandReplaceLogo => 'Replace image';

  @override
  String get mailBrandRemoveLogo => 'Remove logo';

  @override
  String get mailBrandSignaturePlaceholder => 'Your name, role, phone, website…';

  @override
  String get mailBrandSignature => 'Signature';

  @override
  String mailBrandSignatureHelp(String domain) {
    return 'Added to mail you send from $domain, on every device. Links and email addresses become clickable. You can still change it for a single message.';
  }

  @override
  String get mailBrandPreview => 'Preview';

  @override
  String get mailBrandSample => 'Thanks for your message, I\'ll get back to you today.';

  @override
  String mailBrandSaved(String domain) {
    return 'Saved for $domain';
  }

  @override
  String get mailBrandLogoUnreadable => 'That file isn\'t an image Edgepost can read. Try a PNG or JPEG.';

  @override
  String get mailBrandSummaryNone => 'Add a signature or logo';

  @override
  String get mailBrandSummarySignature => 'Signature';

  @override
  String get mailBrandSummaryLogo => 'Logo';

  @override
  String get mailBrandSummaryBoth => 'Signature and logo';

  @override
  String get mailSplitPlaceholder => 'Choose a message to read it here.';

  @override
  String get mailSuggestedRecipients => 'People you\'ve written to';

  @override
  String mailSuggestAdd(String recipient) {
    return 'Add $recipient';
  }

  @override
  String mailSuggestTypo(String domain) {
    return 'Did you mean this? You typed $domain';
  }

  @override
  String get mailErrServiceMissing => 'Your mail service is no longer in your Cloudflare account.';

  @override
  String get mailServiceMissingTitle => 'Your mail service is gone';

  @override
  String get mailServiceMissingBody =>
      'The edgepost-mail Worker isn\'t in your Cloudflare account any more. Set it up again to receive and send mail here. Mail it kept is gone if its database and bucket were deleted too.';

  @override
  String get mailServiceSetUpAgain => 'Set up again';

  @override
  String get welcomeTitle => 'Your domains, handled.';

  @override
  String get welcomeBody =>
      'Edgepost brings your Cloudflare® domains into one place: DNS, SSL and cache, traffic, Workers and Pages, and a real mailbox on each domain that you can read, reply to and send from.';

  @override
  String get welcomePrivacy =>
      'Your token stays in this device\'s secure storage. Edgepost talks only to Cloudflare and to a mail service that runs in your own Cloudflare account. No Edgepost server, no tracking.';

  @override
  String get welcomeAddToken => 'Add a Cloudflare API token';

  @override
  String get welcomeHowTo => 'How to create a token';

  @override
  String get welcomeNotAffiliated =>
      'Edgepost is an independent app. It isn\'t made, endorsed or supported by Cloudflare, Inc., and isn\'t affiliated with it.';

  @override
  String get addTokenTitle => 'Add API token';

  @override
  String get addTokenLabel => 'Name (optional)';

  @override
  String get addTokenLabelPlaceholder => 'e.g. Personal account';

  @override
  String get addTokenField => 'API token';

  @override
  String get addTokenFieldHelp =>
      'Create it under My Profile → API Tokens in the Cloudflare dashboard. Paste it here; it\'s stored only on this device.';

  @override
  String get addTokenPaste => 'Paste';

  @override
  String get addTokenVerify => 'Verify and add';

  @override
  String get addTokenVerifying => 'Checking the token and what it can reach…';

  @override
  String get addTokenEmpty => 'Paste a token first.';

  @override
  String get addTokenRecommended => 'Recommended permissions';

  @override
  String get addTokenRecommendedHelp =>
      'Grant only what you\'ll use. Each feature tells you if a permission is missing.';

  @override
  String get addTokenAddedTitle => 'Token added';

  @override
  String get addTokenWriteNote => 'Edit rights are confirmed the first time you change something.';

  @override
  String get capabilityAvailable => 'Available';

  @override
  String get capabilityMissing => 'Missing';

  @override
  String get capZones => 'See domains';

  @override
  String get capDns => 'DNS records';

  @override
  String get capZoneSettings => 'SSL, cache and security settings';

  @override
  String get capCachePurge => 'Purge cache';

  @override
  String get capAnalytics => 'Traffic analytics';

  @override
  String get capEmailRouting => 'Email routing rules';

  @override
  String get capEmailAddresses => 'Forwarding addresses';

  @override
  String get capDmarc => 'DMARC reports';

  @override
  String get capWorkers => 'Workers';

  @override
  String get capWorkerRoutes => 'Worker routes';

  @override
  String get capPages => 'Pages';

  @override
  String get capD1 => 'D1 (mailbox storage)';

  @override
  String get capR2 => 'R2 (mail attachments)';

  @override
  String get capRegistrar => 'Registrar renewals';

  @override
  String get lockTitle => 'Edgepost is locked';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get lockReason => 'Unlock to see your domains and mail';

  @override
  String get capabilityNotEnabled => 'Turn on in the dashboard';

  @override
  String get capabilityUnknown => 'Not confirmed yet: checked again when you use it';

  @override
  String get capR2NotEnabledHint =>
      'R2 needs a one-time subscription (free tier included). In the Cloudflare dashboard open Storage & databases → R2 → Overview and complete the checkout.';

  @override
  String capDeniedHint(String permission) {
    return 'Add this permission to the token in the Cloudflare dashboard: $permission';
  }

  @override
  String get capOpenDashboard => 'Open the Cloudflare dashboard';

  @override
  String get capCheckAgain => 'Check permissions again';

  @override
  String get capChecking => 'Checking permissions…';

  @override
  String get capBilling => 'Budget and usage cost';

  @override
  String get addAccountAvailable => 'Reachable with your tokens';

  @override
  String get addAccountAvailableHelp => 'Accounts your API tokens already reach. Adding one needs no new token.';

  @override
  String get addAccountNewToken => 'With a new API token';

  @override
  String get addAccountChoose => 'Choose accounts';

  @override
  String addAccountChooseHelp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'This token reaches $count accounts. Pick the ones to show in Edgepost; you can add the others later.',
      one: 'This token reaches 1 account.',
    );
    return '$_temp0';
  }

  @override
  String get addAccountAlready => 'Already added';

  @override
  String get addAccountAllAdded =>
      'Every account this token reaches is already in Edgepost. Keep it as another key for them (for example while you replace an expiring token).';

  @override
  String get addAccountKeepToken => 'Keep token';

  @override
  String addAccountConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count accounts',
      one: 'Add 1 account',
      zero: 'Choose an account',
    );
    return '$_temp0';
  }

  @override
  String addAccountChecking(int done, int total) {
    return 'Checking what the token can do: $done of $total';
  }

  @override
  String get settingsTokens => 'API tokens';

  @override
  String get settingsTokenKindUser => 'User token';

  @override
  String get settingsTokenKindAccount => 'Account token';

  @override
  String get settingsTokenRecheck => 'Check permissions again';

  @override
  String get settingsTokenRemove => 'Remove token';

  @override
  String settingsTokenRemoveConfirm(String label) {
    return 'Remove “$label”?';
  }

  @override
  String get settingsTokenRemoveBody =>
      'The token is deleted from this device. It stays valid in Cloudflare until you revoke it there.';

  @override
  String get settingsTokenCapabilities => 'What it can do';

  @override
  String get settingsTokenRechecked => 'Permissions updated';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsAppearanceSystem => 'System';

  @override
  String get settingsAppearanceSystemHelp => 'Follows your device\'s light or dark setting.';

  @override
  String get settingsAppLock => 'Require Face ID / fingerprint';

  @override
  String get settingsAppLockHelp =>
      'Locks Edgepost when you leave it for more than a minute and hides its content in the app switcher.';

  @override
  String get settingsAppLockUnavailable => 'Set up a device passcode to use app lock.';

  @override
  String get settingsMail => 'Mail';

  @override
  String get settingsMailService => 'Mail service';

  @override
  String get settingsMailNotSetUp => 'Not set up';

  @override
  String get settingsMailReady => 'Running';

  @override
  String get settingsNewMailAlerts => 'New mail alerts';

  @override
  String get settingsNewMailAlertsHelp =>
      'Checks for new mail in the background. The system decides how often, usually every 15 to 60 minutes.';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsLicenses => 'Open-source licenses';

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get settingsSourceCode => 'Source code';

  @override
  String get settingsSourceCodeLicense => 'MIT';

  @override
  String get settingsContact => 'Contact';

  @override
  String get settingsPrivacyBody =>
      'Edgepost has no server and collects no data. Your API tokens live in this device\'s secure storage. App traffic goes only to api.cloudflare.com and to the mail Worker in your own Cloudflare account. Cached lists and recent mail are stored on this device so they open instantly.';

  @override
  String get settingsNotAffiliated =>
      'Edgepost is an independent app. It isn\'t made, endorsed or supported by Cloudflare, Inc., and isn\'t affiliated with it. Cloudflare, Cloudflare Workers and Cloudflare Pages are trademarks and/or registered trademarks of Cloudflare, Inc. in the United States and other jurisdictions.';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsBudgetAlerts => 'Budget alerts';

  @override
  String get settingsBudgetAlertsHelp =>
      'When emails reach 80% and 100% of your sending limit, and the first time usage costs money in a billing period.';

  @override
  String get settingsDeliveryAlerts => 'Delivery alerts';

  @override
  String get settingsDeliveryAlertsHelp => 'When a domain\'s delivery rate drops below Cloudflare\'s 95% target.';

  @override
  String get settingsNotificationsDenied => 'Notifications are off for Edgepost. Turn them on in Settings.';

  @override
  String get settingsTokenExpiresTitle => 'Expires';

  @override
  String get settingsTokenNoExpiry => 'Never';

  @override
  String get settingsTokenExpiryHelp =>
      'Read from Cloudflare each time the app opens, so a date you change in the Cloudflare dashboard shows up here. To replace an expiring token, create or roll it in the dashboard and add the new one.';

  @override
  String get settingsTokenAddReplacement => 'Add the new token';

  @override
  String get accountsTitle => 'Accounts';

  @override
  String get accountTitle => 'Account';

  @override
  String get accountAdd => 'Add account';

  @override
  String get accountsManage => 'Manage accounts';

  @override
  String get accountNoAccess => 'No access: add a token for it';

  @override
  String get accountCurrent => 'current account';

  @override
  String get accountShowing => 'Showing now';

  @override
  String accountSwitched(String name) {
    return 'Switched to $name';
  }

  @override
  String accountButtonLabel(String name) {
    return 'Account: $name';
  }

  @override
  String get accountButtonHint => 'Shows your accounts';

  @override
  String accountSwitchBack(String name) {
    return 'Switch to $name';
  }

  @override
  String get accountOthersNeedYou => 'Another account needs you';

  @override
  String get accountOthersUnread => 'Another account has unread mail';

  @override
  String get accountName => 'Name';

  @override
  String get accountRename => 'Name this account';

  @override
  String accountRenameHelp(String name) {
    return 'Only on this device. Leave it empty to use Cloudflare\'s name, “$name”.';
  }

  @override
  String accountCloudflareName(String name) {
    return 'In Cloudflare: $name';
  }

  @override
  String accountSwitchTo(String name) {
    return 'Switch to $name';
  }

  @override
  String accountTokenAlsoReaches(String names) {
    return 'This token also gives access to $names; they\'ll keep working only if another token reaches them.';
  }

  @override
  String get accountRemove => 'Remove from Edgepost';

  @override
  String accountRemoveConfirm(String name) {
    return 'Remove $name from Edgepost?';
  }

  @override
  String get accountRemoveBody =>
      'Nothing changes in Cloudflare. This device forgets the account: its mail connection, what was kept for it offline, and any token that only reached it.';

  @override
  String accountRemoved(String name) {
    return '$name removed from Edgepost';
  }

  @override
  String get todayNeedsYou => 'Needs you';

  @override
  String get todayInbound => 'Inbound';

  @override
  String get todayDeploys => 'Deploys';

  @override
  String get todayTraffic => 'Traffic · 7 days';

  @override
  String get todayAllClear => 'Every strip is in line. Nothing needs you right now.';

  @override
  String todaySeeAll(int count) {
    return 'All $count';
  }

  @override
  String get todayNoUnread => 'No unread mail.';

  @override
  String get todaySetUpMail => 'Set up your domain mailbox';

  @override
  String get todayFieldRequests => 'Requests';

  @override
  String get todayFieldBandwidth => 'Bandwidth';

  @override
  String get todayFieldCached => 'Cached';

  @override
  String get todayFleetCallsign => 'All domains';

  @override
  String todayFleetCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count domains',
      one: '1 domain',
    );
    return '$_temp0';
  }

  @override
  String todayReasonRegistrar(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
      zero: 'less than a day',
    );
    return 'Registration expires in $_temp0 and auto-renew is off.';
  }

  @override
  String get todayReasonRegistrarExpired => 'Registration has expired. Renew it in the Cloudflare dashboard.';

  @override
  String todayReasonTokenExpiry(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
      zero: 'less than a day',
    );
    return 'This API token expires in $_temp0. Roll it in the Cloudflare dashboard, then add the new one.';
  }

  @override
  String todayReasonMailUpdate(String version) {
    return 'A newer mail service ($version) is ready to install.';
  }

  @override
  String get todayFieldExpires => 'Expires';

  @override
  String get todayFieldToken => 'Token';

  @override
  String get todayFieldMail => 'Mail service';

  @override
  String get todayFieldNeedsYou => 'Needs you';

  @override
  String get todayFieldUnread => 'Unread';

  @override
  String get todayNoAnalytics => 'Add “Zone · Analytics · Read” to a token to see traffic here.';

  @override
  String get budgetTitle => 'Budget';

  @override
  String get budgetCallsign => 'This period';

  @override
  String get budgetUsageCost => 'Usage cost';

  @override
  String budgetDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: 'ends tomorrow',
      zero: 'ends today',
    );
    return '$_temp0';
  }

  @override
  String budgetReasonSendCap(String percent) {
    return 'Emails at $percent of your sending limit. Sending stops at the limit.';
  }

  @override
  String budgetReasonCost(String amount) {
    return 'Usage beyond your plan this period: $amount. See what\'s billing.';
  }

  @override
  String get budgetNoBilling =>
      'Add “Account · Billing · Read” to your token to see usage cost. Emails sent are tracked either way.';

  @override
  String budgetUnavailable(String reason) {
    return 'Cloudflare\'s usage data isn\'t available right now ($reason). Emails sent are still tracked.';
  }

  @override
  String get budgetScreenTitle => 'Budget';

  @override
  String budgetPeriod(String start, String end) {
    return '$start – $end';
  }

  @override
  String get budgetServices => 'Usage this period';

  @override
  String get budgetServicesEmpty => 'No usage beyond what your plan includes so far.';

  @override
  String get budgetIncluded => 'Included in Workers Paid';

  @override
  String get budgetIncludedSource => 'From Cloudflare\'s pricing pages. Usage past these amounts is billed.';

  @override
  String get budgetIncWorkers => 'Workers: 10 M requests, 30 M CPU ms';

  @override
  String get budgetIncD1 => 'D1: 25 B rows read, 50 M written, 5 GB';

  @override
  String get budgetIncR2 => 'R2: 10 GB, 1 M Class A, 10 M Class B operations';

  @override
  String get budgetIncEmail => 'Email Sending: 3,000 emails';

  @override
  String get budgetSending => 'Sending limit';

  @override
  String get budgetOpenBilling => 'Billing in the Cloudflare dashboard';

  @override
  String get budgetAlpha =>
      'Usage cost comes from Cloudflare\'s billable-usage API (Alpha) and may lag by a few hours.';

  @override
  String get alertSend80Title => 'Sending at 80% of your limit';

  @override
  String alertSend80Body(String used, String limit) {
    return '$used of $limit emails in the last 31 days. Sending stops at the limit.';
  }

  @override
  String get alertSend100Title => 'Sending limit reached';

  @override
  String get alertSend100Body =>
      'No more emails go out until older sends leave the 31-day window, or you raise the limit.';

  @override
  String get alertCostTitle => 'Cloudflare usage is costing money';

  @override
  String alertCostBody(String amount) {
    return '$amount beyond your plan this period. Open Budget to see which service.';
  }

  @override
  String alertDeliveryTitle(String domain) {
    return 'Delivery problems on $domain';
  }

  @override
  String alertDeliveryBody(String rate) {
    return 'Delivered $rate of recent emails (target 95%). Open Sending health to see why.';
  }

  @override
  String todayReasonDelivery(String rate) {
    return 'Delivered $rate of recent emails, below Cloudflare\'s 95% target.';
  }

  @override
  String newMailFrom(String sender) {
    return 'New mail from $sender';
  }

  @override
  String get newMailOpen => 'Open';

  @override
  String get todayOtherAccounts => 'Other accounts';

  @override
  String newMailInFrom(String account, String sender) {
    return 'New mail in $account from $sender';
  }

  @override
  String newMailInMany(int count, String account) {
    return '$count new messages in $account';
  }

  @override
  String get alertChannelName => 'Budget and delivery';

  @override
  String get notifOfferAction => 'Turn on';

  @override
  String get notifOfferTitle => 'Get alerts on this device?';

  @override
  String get notifOfferLater => 'Not now';

  @override
  String get budgetSendsLeft => 'Sends left';

  @override
  String get budgetPeriodField => 'Period';

  @override
  String get budgetSendingOff => 'Off';

  @override
  String budgetMeterCaption(String sent, String limit) {
    return '$sent of $limit emails sent in the last 31 days';
  }

  @override
  String get budgetNoBillingShort => 'Usage cost needs “Account · Billing · Read” on your token.';

  @override
  String get budgetUsageUnavailableShort => 'Usage cost isn\'t available right now; emails are still counted.';

  @override
  String get budgetAlertsTitle => 'Alert me at 80% and 100%';

  @override
  String get budgetAlertsHelp =>
      'A notification when emails reach 80% and 100% of your sending limit, and the first time usage costs money in a period.';

  @override
  String budgetSemantic(String sent, String limit, String left) {
    return '$sent of $limit emails sent, $left left';
  }

  @override
  String get todayBackInLine => 'Back in line';

  @override
  String get budgetSendingLimit => 'Sending limit';

  @override
  String get todayMailServiceCallsign => 'Mail service';

  @override
  String get controlsTitle => 'SSL, cache & security';

  @override
  String get controlsSectionEncryption => 'Encryption';

  @override
  String get controlsSectionCache => 'Cache';

  @override
  String get controlsSectionSecurity => 'Security';

  @override
  String get controlsSectionCloudflare => 'Cloudflare';

  @override
  String get controlsSectionDnssec => 'DNSSEC';

  @override
  String get controlsSslMode => 'SSL/TLS mode';

  @override
  String get controlsSslOff => 'Off';

  @override
  String get controlsSslOffDetail => 'No HTTPS. Visitors and your server talk over plain HTTP.';

  @override
  String get controlsSslFlexible => 'Flexible';

  @override
  String get controlsSslFlexibleDetail => 'HTTPS for visitors, plain HTTP from Cloudflare to your server.';

  @override
  String get controlsSslFull => 'Full';

  @override
  String get controlsSslFullDetail => 'HTTPS all the way; your server\'s certificate isn\'t checked.';

  @override
  String get controlsSslStrict => 'Full (strict)';

  @override
  String get controlsSslStrictDetail => 'HTTPS all the way, with a valid certificate on your server.';

  @override
  String get controlsSslWeakWarning => 'Off and Flexible leave traffic between Cloudflare and your server unencrypted.';

  @override
  String controlsSslWeakReason(String mode) {
    return 'SSL is $mode: traffic to your server isn\'t encrypted.';
  }

  @override
  String get controlsAlwaysHttps => 'Always Use HTTPS';

  @override
  String get controlsAlwaysHttpsDetail => 'Redirects every HTTP request to HTTPS.';

  @override
  String get controlsHttpsRewrites => 'Automatic HTTPS Rewrites';

  @override
  String get controlsHttpsRewritesDetail => 'Rewrites http:// links in your pages to https:// where possible.';

  @override
  String get controlsMinTls => 'Minimum TLS version';

  @override
  String controlsMinTlsOption(String version) {
    return 'TLS $version';
  }

  @override
  String get controlsMinTls10Detail => 'Accepts every client, including very old ones.';

  @override
  String get controlsMinTls11Detail => 'Turns away clients that only speak TLS 1.0.';

  @override
  String get controlsMinTls12Detail => 'Turns away clients that only speak TLS 1.0 or 1.1.';

  @override
  String get controlsMinTls13Detail => 'Modern clients only. Some older devices and tools can\'t connect.';

  @override
  String get controlsTls13 => 'TLS 1.3';

  @override
  String get controlsTls13On => 'On';

  @override
  String get controlsTls13OnDetail => 'Faster, more private handshakes for clients that support it.';

  @override
  String get controlsTls13Off => 'Off';

  @override
  String get controlsTls13OffDetail => 'Clients connect with TLS 1.2 or older.';

  @override
  String get controlsTls13Zrt => 'On with 0-RTT';

  @override
  String get controlsTls13ZrtDetail => 'Also lets returning visitors resume a connection without a full handshake.';

  @override
  String get controlsPurgeEverything => 'Purge everything';

  @override
  String get controlsPurgeEverythingDetail => 'Removes every cached file. Your server answers the next requests.';

  @override
  String get controlsPurgeEverythingTitle => 'Purge all cached files?';

  @override
  String controlsPurgeEverythingMessage(String domain) {
    return 'Cloudflare fetches every file for $domain from your server again, which can slow the site and load your server for a while.';
  }

  @override
  String get controlsPurgeEverythingConfirm => 'Purge everything';

  @override
  String controlsPurgeEverythingDone(String domain) {
    return 'Cache purged for $domain. Your server answers the next requests.';
  }

  @override
  String controlsPurgeCooldown(int seconds) {
    return 'Wait $seconds s: the Free plan allows 5 full purges per minute.';
  }

  @override
  String get controlsPurgeRateLimited => 'Cloudflare is limiting purges for this account. Try again in a minute.';

  @override
  String get controlsPurgeUrls => 'Purge URLs';

  @override
  String get controlsPurgeUrlsDetail => 'Removes specific files from the cache.';

  @override
  String get controlsPurgeUrlsField => 'URLs, one per line';

  @override
  String controlsPurgeUrlsPlaceholder(String domain) {
    return 'https://$domain/styles.css';
  }

  @override
  String controlsPurgeUrlsHelp(String domain) {
    return 'Full URLs on $domain or its subdomains. Long lists go out in batches of 100.';
  }

  @override
  String controlsPurgeUrlsEmpty(String domain) {
    return 'Add at least one URL, like https://$domain/index.html.';
  }

  @override
  String controlsPurgeUrlNotUrl(String line) {
    return 'Not a full URL. Start it with https://: $line';
  }

  @override
  String controlsPurgeUrlNotHttp(String line) {
    return 'Only http:// and https:// URLs can be purged: $line';
  }

  @override
  String controlsPurgeUrlOtherDomain(String domain, String line) {
    return 'Not on $domain: $line';
  }

  @override
  String controlsPurgeUrlsMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more lines to fix',
      one: 'and 1 more line to fix',
    );
    return '$_temp0';
  }

  @override
  String controlsPurgeUrlsButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Purge $count URLs',
      one: 'Purge 1 URL',
      zero: 'Purge URLs',
    );
    return '$_temp0';
  }

  @override
  String controlsPurgeUrlsDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count URLs purged.',
      one: '1 URL purged.',
    );
    return '$_temp0';
  }

  @override
  String controlsPurgeUrlsPartial(int done, int total, String reason) {
    return '$done of $total URLs purged, then Cloudflare refused the rest: $reason';
  }

  @override
  String get controlsDevMode => 'Development mode';

  @override
  String get controlsDevModeOffDetail => 'Bypasses the cache so changes show at once. Turns itself off after 3 hours.';

  @override
  String controlsDevModeOnDetail(String time) {
    return 'Cache bypassed. $time left.';
  }

  @override
  String get controlsUnderAttack => 'Under Attack mode';

  @override
  String get controlsUnderAttackDetail =>
      'Shows every visitor a challenge before your site. Use it only during an attack: it can block APIs and apps.';

  @override
  String get controlsUnderAttackOnTitle => 'Turn on Under Attack mode?';

  @override
  String controlsUnderAttackOnMessage(String domain) {
    return 'Every visitor to $domain sees a challenge first. APIs, webhooks and apps that call this domain may stop working until you turn it off.';
  }

  @override
  String get controlsUnderAttackOnConfirm => 'Turn on';

  @override
  String get controlsSecurityLevel => 'Security level';

  @override
  String get controlsSecurityLevelOff => 'Off';

  @override
  String get controlsSecurityLevelEssentiallyOff => 'Essentially off';

  @override
  String get controlsSecurityLevelLow => 'Low';

  @override
  String get controlsSecurityLevelMedium => 'Medium';

  @override
  String get controlsSecurityLevelHigh => 'High';

  @override
  String get controlsSecurityLevelFooter =>
      'Cloudflare no longer scores visitor threat, so levels below Under Attack have little effect. Turning Under Attack mode off restores the level shown here.';

  @override
  String get controlsSecurityLevelLocked => 'Restored when Under Attack mode is turned off.';

  @override
  String get controlsPause => 'Pause Cloudflare';

  @override
  String get controlsPauseDetail =>
      'Traffic goes straight to your server: no cache, no Cloudflare SSL, no protection. DNS keeps working.';

  @override
  String get controlsPauseTitle => 'Pause Cloudflare?';

  @override
  String controlsPauseMessage(String domain) {
    return 'Visitors to $domain connect straight to your server. The cache, SSL and security stop applying, and your server\'s IP address becomes visible.';
  }

  @override
  String get controlsPauseConfirm => 'Pause';

  @override
  String controlsPauseDone(String domain) {
    return 'Cloudflare paused on $domain.';
  }

  @override
  String get controlsResume => 'Resume Cloudflare';

  @override
  String get controlsResumeDetail => 'Paused: traffic bypasses the proxy, cache and security.';

  @override
  String controlsResumeTitle(String domain) {
    return 'Resume Cloudflare on $domain?';
  }

  @override
  String get controlsResumeMessage => 'Traffic flows through Cloudflare\'s proxy, cache and security again.';

  @override
  String get controlsResumeConfirm => 'Resume';

  @override
  String controlsResumeDone(String domain) {
    return 'Cloudflare resumed on $domain.';
  }

  @override
  String get controlsDnssecStatus => 'Status';

  @override
  String get controlsDnssecActive => 'Active';

  @override
  String get controlsDnssecPending => 'Pending';

  @override
  String get controlsDnssecDisabled => 'Off';

  @override
  String get controlsDnssecPendingDisabled => 'Turning off';

  @override
  String get controlsDnssecError => 'Error';

  @override
  String get controlsDnssecDs => 'DS record';

  @override
  String get controlsDnssecDigest => 'Digest';

  @override
  String get controlsDnssecKeyTag => 'Key tag';

  @override
  String get controlsDnssecAlgorithm => 'Algorithm';

  @override
  String get controlsDnssecDigestType => 'Digest type';

  @override
  String get controlsDnssecPublicKey => 'Public key';

  @override
  String get controlsDnssecFooterActive =>
      'Your registrar publishes this DS record. Change it only when you move DNS to another provider.';

  @override
  String get controlsDnssecFooterPending =>
      'Add this DS record at your registrar. DNSSEC turns active once the registrar publishes it.';

  @override
  String get controlsDnssecFooterDisabled =>
      'DNSSEC is off. Turn it on in the Cloudflare dashboard, then add the DS record it shows at your registrar.';

  @override
  String get controlsDnssecFooterError =>
      'Cloudflare reports a DNSSEC problem. Check that the DS record at your registrar matches this one.';

  @override
  String controlsCopyValue(String label) {
    return 'Copy $label';
  }

  @override
  String controlsSaveFailed(String setting, String reason) {
    return 'Couldn\'t change $setting. $reason';
  }

  @override
  String get controlsNotEditable => 'Your plan can\'t change this setting.';

  @override
  String controlsUnreadable(String reason) {
    return 'Couldn\'t read this setting. $reason';
  }

  @override
  String get domainsFilterAll => 'All';

  @override
  String get domainsFilterAttention => 'Needs you';

  @override
  String get domainsFilterPinned => 'Pinned';

  @override
  String get domainsEmptyTitle => 'No domains yet';

  @override
  String get domainsEmptyMessage =>
      'This token can\'t see any zones. Add a token with “Zone · Zone · Read”, or add a domain in the Cloudflare dashboard.';

  @override
  String get domainsAttentionEmpty => 'Every domain is in line.';

  @override
  String get domainsPinnedEmpty => 'Pin a domain from its page to keep it on top.';

  @override
  String get zoneFieldStatus => 'Status';

  @override
  String get zoneFieldPlan => 'Plan';

  @override
  String get zoneStatusActive => 'Active';

  @override
  String get zoneStatusPending => 'Pending';

  @override
  String get zoneStatusPaused => 'Paused';

  @override
  String get zoneStatusMoved => 'Moved';

  @override
  String get zoneStatusOther => 'Inactive';

  @override
  String get zoneReasonPending => 'Nameservers not switched yet: Cloudflare isn\'t serving this domain.';

  @override
  String get zoneReasonPaused => 'Cloudflare is paused: traffic bypasses the proxy, cache and security.';

  @override
  String zoneReasonDevMode(int minutes) {
    return 'Development mode is on: the cache is bypassed for $minutes more min.';
  }

  @override
  String get zoneHubDns => 'DNS records';

  @override
  String get zoneHubControls => 'SSL, cache & security';

  @override
  String get zoneHubAnalytics => 'Traffic';

  @override
  String get zoneHubEmail => 'Email routing';

  @override
  String get zoneHubMailbox => 'Mailbox';

  @override
  String get zoneHubWorkers => 'Worker routes';

  @override
  String get zoneHubPin => 'Pin';

  @override
  String get zoneHubUnpin => 'Unpin';

  @override
  String get zoneHubNameservers => 'Nameservers';

  @override
  String get zoneHubNameserversHelp => 'Set these at your registrar to finish moving the domain to Cloudflare.';

  @override
  String get zoneHubOpenDashboard => 'Open in Cloudflare dashboard';

  @override
  String get zoneHubDetails => 'Details';

  @override
  String get zoneHubCreated => 'Added';

  @override
  String get zoneHubActivated => 'Activated';

  @override
  String get zoneHubRegistrar => 'Previous registrar';

  @override
  String get zoneHubManage => 'Manage';

  @override
  String get domainsFieldRequests => 'Requests · 7d';

  @override
  String get domainsSplitPlaceholder => 'Choose a domain to see its DNS, traffic and settings here.';
}
