import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @trafficTitle.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get trafficTitle;

  /// No description provided for @trafficRange24h.
  ///
  /// In en, this message translates to:
  /// **'24 hours'**
  String get trafficRange24h;

  /// No description provided for @trafficRange7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get trafficRange7d;

  /// No description provided for @trafficRange30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get trafficRange30d;

  /// No description provided for @trafficCaption24h.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours · UTC'**
  String get trafficCaption24h;

  /// No description provided for @trafficCaption7d.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days · UTC'**
  String get trafficCaption7d;

  /// No description provided for @trafficCaption30d.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days · UTC'**
  String get trafficCaption30d;

  /// No description provided for @trafficFieldRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get trafficFieldRequests;

  /// No description provided for @trafficFieldBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get trafficFieldBandwidth;

  /// No description provided for @trafficFieldCached.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get trafficFieldCached;

  /// No description provided for @trafficFieldThreats.
  ///
  /// In en, this message translates to:
  /// **'Threats'**
  String get trafficFieldThreats;

  /// No description provided for @trafficFieldVisitors.
  ///
  /// In en, this message translates to:
  /// **'Visitors'**
  String get trafficFieldVisitors;

  /// No description provided for @trafficChartHourly.
  ///
  /// In en, this message translates to:
  /// **'Requests per hour'**
  String get trafficChartHourly;

  /// No description provided for @trafficChartDaily.
  ///
  /// In en, this message translates to:
  /// **'Requests per day'**
  String get trafficChartDaily;

  /// No description provided for @trafficLegendAll.
  ///
  /// In en, this message translates to:
  /// **'Not cached'**
  String get trafficLegendAll;

  /// No description provided for @trafficLegendCached.
  ///
  /// In en, this message translates to:
  /// **'Served from cache'**
  String get trafficLegendCached;

  /// No description provided for @trafficTooltipRequests.
  ///
  /// In en, this message translates to:
  /// **'{count} requests'**
  String trafficTooltipRequests(String count);

  /// No description provided for @trafficTooltipCached.
  ///
  /// In en, this message translates to:
  /// **'{count} from cache ({percent})'**
  String trafficTooltipCached(String count, String percent);

  /// No description provided for @trafficChartSummary.
  ///
  /// In en, this message translates to:
  /// **'{chart}, {range}. {total} requests in all, {cached} served from cache. Busiest: {peak} requests, {when}.'**
  String trafficChartSummary(String chart, String range, String total, String cached, String peak, String when);

  /// No description provided for @trafficEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No traffic in this range'**
  String get trafficEmptyTitle;

  /// No description provided for @trafficEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare saw no requests for {domain}. Traffic shows here once its DNS records are proxied through Cloudflare and visitors arrive.'**
  String trafficEmptyMessage(String domain);

  /// No description provided for @trafficRangeUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This range isn\'t available on your plan'**
  String get trafficRangeUnavailableTitle;

  /// No description provided for @trafficRangeUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare keeps traffic history for a limited time on each plan, and this range reaches further back. Pick a shorter range.'**
  String get trafficRangeUnavailableMessage;

  /// No description provided for @trafficShowRange.
  ///
  /// In en, this message translates to:
  /// **'Show {range}'**
  String trafficShowRange(String range);

  /// No description provided for @trafficFieldPageViews.
  ///
  /// In en, this message translates to:
  /// **'Page views'**
  String get trafficFieldPageViews;

  /// No description provided for @computeBayWorkers.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get computeBayWorkers;

  /// No description provided for @computeBayPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get computeBayPages;

  /// No description provided for @computeGapPermission.
  ///
  /// In en, this message translates to:
  /// **'This token can\'t list these. Add “{permission}” to it in the Cloudflare dashboard, then pull to refresh.'**
  String computeGapPermission(String permission);

  /// No description provided for @computeGapFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load these: {message} Pull to refresh to try again.'**
  String computeGapFailed(String message);

  /// No description provided for @computeNoAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'No access to Workers or Pages'**
  String get computeNoAccessTitle;

  /// No description provided for @computeNoAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Your tokens can\'t read Workers or Pages. In the Cloudflare dashboard, add “{workers}” and “{pages}” to a token, then pull to refresh.'**
  String computeNoAccessMessage(String workers, String pages);

  /// No description provided for @computeZoneRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'Worker routes'**
  String get computeZoneRoutesTitle;

  /// No description provided for @computeZoneRoutesSectionRoutes.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get computeZoneRoutesSectionRoutes;

  /// No description provided for @computeZoneRoutesRoutesFooter.
  ///
  /// In en, this message translates to:
  /// **'Requests matching a route run the Worker before reaching your origin.'**
  String get computeZoneRoutesRoutesFooter;

  /// No description provided for @computeZoneRoutesSectionDomains.
  ///
  /// In en, this message translates to:
  /// **'Custom domains'**
  String get computeZoneRoutesSectionDomains;

  /// No description provided for @computeZoneRoutesDomainsFooter.
  ///
  /// In en, this message translates to:
  /// **'A custom domain points a whole hostname at a Worker, with no origin behind it.'**
  String get computeZoneRoutesDomainsFooter;

  /// No description provided for @computeZoneRoutesNoRoutes.
  ///
  /// In en, this message translates to:
  /// **'No routes on this domain.'**
  String get computeZoneRoutesNoRoutes;

  /// No description provided for @computeZoneRoutesNoDomains.
  ///
  /// In en, this message translates to:
  /// **'No Worker custom domains on this domain.'**
  String get computeZoneRoutesNoDomains;

  /// No description provided for @computeZoneRoutesNoScript.
  ///
  /// In en, this message translates to:
  /// **'No Worker: requests go straight to the origin'**
  String get computeZoneRoutesNoScript;

  /// No description provided for @computeZoneRoutesRunsScript.
  ///
  /// In en, this message translates to:
  /// **'Runs {script}'**
  String computeZoneRoutesRunsScript(String script);

  /// No description provided for @computeZoneRoutesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Workers on {zone}'**
  String computeZoneRoutesEmptyTitle(String zone);

  /// No description provided for @computeZoneRoutesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add a route or custom domain to a Worker in the Cloudflare dashboard or with wrangler, then pull to refresh.'**
  String get computeZoneRoutesEmptyMessage;

  /// No description provided for @workersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Workers in this account yet.'**
  String get workersEmpty;

  /// No description provided for @workersFieldModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get workersFieldModified;

  /// No description provided for @workersFieldRoutes.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get workersFieldRoutes;

  /// No description provided for @workersFieldCompat.
  ///
  /// In en, this message translates to:
  /// **'Compat date'**
  String get workersFieldCompat;

  /// No description provided for @workersFieldUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get workersFieldUsage;

  /// No description provided for @workersStripSemantics.
  ///
  /// In en, this message translates to:
  /// **'Worker {name}, modified {modified}, {routes, plural, =0{no routes} =1{1 route} other{{routes} routes}}'**
  String workersStripSemantics(String name, String modified, int routes);

  /// No description provided for @workersLiveLogs.
  ///
  /// In en, this message translates to:
  /// **'Live logs'**
  String get workersLiveLogs;

  /// No description provided for @workersLiveLogsHint.
  ///
  /// In en, this message translates to:
  /// **'Stream console output and requests as they happen'**
  String get workersLiveLogsHint;

  /// No description provided for @workersOpenWorkersDev.
  ///
  /// In en, this message translates to:
  /// **'Open on workers.dev'**
  String get workersOpenWorkersDev;

  /// No description provided for @workersSectionOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get workersSectionOverview;

  /// No description provided for @workersCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get workersCreated;

  /// No description provided for @workersModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get workersModified;

  /// No description provided for @workersCompatDate.
  ///
  /// In en, this message translates to:
  /// **'Compatibility date'**
  String get workersCompatDate;

  /// No description provided for @workersCompatFlags.
  ///
  /// In en, this message translates to:
  /// **'Compatibility flags'**
  String get workersCompatFlags;

  /// No description provided for @workersUsageModel.
  ///
  /// In en, this message translates to:
  /// **'Usage model'**
  String get workersUsageModel;

  /// No description provided for @workersDeployedFrom.
  ///
  /// In en, this message translates to:
  /// **'Last deployed from'**
  String get workersDeployedFrom;

  /// No description provided for @workersHandlers.
  ///
  /// In en, this message translates to:
  /// **'Handlers'**
  String get workersHandlers;

  /// No description provided for @workersSectionTriggers.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get workersSectionTriggers;

  /// No description provided for @workersDev.
  ///
  /// In en, this message translates to:
  /// **'workers.dev'**
  String get workersDev;

  /// No description provided for @workersStateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get workersStateOn;

  /// No description provided for @workersStateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get workersStateOff;

  /// No description provided for @workersPreviewsOn.
  ///
  /// In en, this message translates to:
  /// **'Preview URLs on'**
  String get workersPreviewsOn;

  /// No description provided for @workersPreviewsOff.
  ///
  /// In en, this message translates to:
  /// **'Preview URLs off'**
  String get workersPreviewsOff;

  /// No description provided for @workersCustomDomain.
  ///
  /// In en, this message translates to:
  /// **'Custom domain'**
  String get workersCustomDomain;

  /// No description provided for @workersRoute.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get workersRoute;

  /// No description provided for @workersNoTriggers.
  ///
  /// In en, this message translates to:
  /// **'This Worker has no route, custom domain or workers.dev address, so nothing on the internet reaches it.'**
  String get workersNoTriggers;

  /// No description provided for @workersSectionDeployment.
  ///
  /// In en, this message translates to:
  /// **'Deployment'**
  String get workersSectionDeployment;

  /// No description provided for @workersActiveDeployment.
  ///
  /// In en, this message translates to:
  /// **'Serving now'**
  String get workersActiveDeployment;

  /// No description provided for @workersNoDeployments.
  ///
  /// In en, this message translates to:
  /// **'Nothing is deployed yet.'**
  String get workersNoDeployments;

  /// No description provided for @workersGradualFooter.
  ///
  /// In en, this message translates to:
  /// **'Traffic is split between versions (a gradual deployment).'**
  String get workersGradualFooter;

  /// No description provided for @workersPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String workersPercent(String percent);

  /// No description provided for @workersLiveShare.
  ///
  /// In en, this message translates to:
  /// **'Live {percent}%'**
  String workersLiveShare(String percent);

  /// No description provided for @workersSectionVersions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get workersSectionVersions;

  /// No description provided for @workersNoVersions.
  ///
  /// In en, this message translates to:
  /// **'No versions uploaded yet.'**
  String get workersNoVersions;

  /// No description provided for @workersVersionsFooter.
  ///
  /// In en, this message translates to:
  /// **'Tap a version to roll back to it. Rolling back sends all traffic to that version; you can roll forward the same way.'**
  String get workersVersionsFooter;

  /// No description provided for @workersVersionNumber.
  ///
  /// In en, this message translates to:
  /// **'Version {number}'**
  String workersVersionNumber(int number);

  /// No description provided for @workersVersionShort.
  ///
  /// In en, this message translates to:
  /// **'Version {id}'**
  String workersVersionShort(String id);

  /// No description provided for @workersRollbackAction.
  ///
  /// In en, this message translates to:
  /// **'Roll back to this version'**
  String get workersRollbackAction;

  /// No description provided for @workersCopyVersionId.
  ///
  /// In en, this message translates to:
  /// **'Copy version ID'**
  String get workersCopyVersionId;

  /// No description provided for @workersRollbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Roll back to {version}?'**
  String workersRollbackTitle(String version);

  /// No description provided for @workersRollbackMessage.
  ///
  /// In en, this message translates to:
  /// **'All traffic to {script} will go to {version} ({id}). The version serving now stays available, so you can roll forward the same way.'**
  String workersRollbackMessage(String script, String version, String id);

  /// No description provided for @workersRollbackConfirm.
  ///
  /// In en, this message translates to:
  /// **'Roll back'**
  String get workersRollbackConfirm;

  /// No description provided for @workersRollbackDone.
  ///
  /// In en, this message translates to:
  /// **'{version} now serves all traffic.'**
  String workersRollbackDone(String version);

  /// No description provided for @workersRollbackBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare blocked this rollback'**
  String get workersRollbackBlockedTitle;

  /// No description provided for @workersRollbackBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare said: “{message}” You can force it, but that version may expect secrets or settings that have changed since.'**
  String workersRollbackBlockedMessage(String message);

  /// No description provided for @workersRollbackForce.
  ///
  /// In en, this message translates to:
  /// **'Roll back anyway'**
  String get workersRollbackForce;

  /// No description provided for @workersSectionSecrets.
  ///
  /// In en, this message translates to:
  /// **'Secrets'**
  String get workersSectionSecrets;

  /// No description provided for @workersSecretsFooter.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare never returns secret values, so only names are shown.'**
  String get workersSecretsFooter;

  /// No description provided for @workersNoSecrets.
  ///
  /// In en, this message translates to:
  /// **'No secrets on this Worker.'**
  String get workersNoSecrets;

  /// No description provided for @workersSecretText.
  ///
  /// In en, this message translates to:
  /// **'Secret text'**
  String get workersSecretText;

  /// No description provided for @workersSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret key'**
  String get workersSecretKey;

  /// No description provided for @workersLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Live logs'**
  String get workersLogsTitle;

  /// No description provided for @workersLogsConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get workersLogsConnecting;

  /// No description provided for @workersLogsLive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Live · waiting for events} =1{Live · 1 event} other{Live · {count} events}}'**
  String workersLogsLive(int count);

  /// No description provided for @workersLogsPaused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Paused} =1{Paused · 1 new event held} other{Paused · {count} new events held}}'**
  String workersLogsPaused(int count);

  /// No description provided for @workersLogsEnded.
  ///
  /// In en, this message translates to:
  /// **'Stream ended'**
  String get workersLogsEnded;

  /// No description provided for @workersLogsEndedHint.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare closed the log stream; log sessions expire after a while. Reconnect to keep watching.'**
  String get workersLogsEndedHint;

  /// No description provided for @workersLogsStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get workersLogsStopped;

  /// No description provided for @workersLogsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the log stream'**
  String get workersLogsFailed;

  /// No description provided for @workersLogsWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {script} to run…'**
  String workersLogsWaiting(String script);

  /// No description provided for @workersLogsWaitingHint.
  ///
  /// In en, this message translates to:
  /// **'Send a request to the Worker; its console output, exceptions and requests show up here as they happen.'**
  String get workersLogsWaitingHint;

  /// No description provided for @workersLogsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Logs stream straight from Cloudflare and are not saved.'**
  String get workersLogsPrivacy;

  /// No description provided for @workersLogsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get workersLogsPause;

  /// No description provided for @workersLogsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get workersLogsResume;

  /// No description provided for @workersLogsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get workersLogsClear;

  /// No description provided for @workersLogsStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get workersLogsStop;

  /// No description provided for @workersLogsReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get workersLogsReconnect;

  /// No description provided for @workersLogsNoUrl.
  ///
  /// In en, this message translates to:
  /// **'(no URL)'**
  String get workersLogsNoUrl;

  /// No description provided for @workersLogsCron.
  ///
  /// In en, this message translates to:
  /// **'Cron {cron}'**
  String workersLogsCron(String cron);

  /// No description provided for @workersLogsAlarm.
  ///
  /// In en, this message translates to:
  /// **'Durable Object alarm'**
  String get workersLogsAlarm;

  /// No description provided for @workersLogsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email {route}'**
  String workersLogsEmail(String route);

  /// No description provided for @workersLogsQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue {queue}'**
  String workersLogsQueue(String queue);

  /// No description provided for @workersLogsRpc.
  ///
  /// In en, this message translates to:
  /// **'RPC {method}'**
  String workersLogsRpc(String method);

  /// No description provided for @workersLogsTailEvent.
  ///
  /// In en, this message translates to:
  /// **'Tail {scripts}'**
  String workersLogsTailEvent(String scripts);

  /// No description provided for @workersLogsEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get workersLogsEvent;

  /// No description provided for @workersLogsOverload.
  ///
  /// In en, this message translates to:
  /// **'Too many events: Cloudflare is sampling this stream.'**
  String get workersLogsOverload;

  /// No description provided for @workersLogsOverloadStop.
  ///
  /// In en, this message translates to:
  /// **'Sampling stopped: every event is shown again.'**
  String get workersLogsOverloadStop;

  /// No description provided for @workersLogsLines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 log line} other{{count} log lines}}'**
  String workersLogsLines(int count);

  /// No description provided for @workersLogsExceptions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exception} other{{count} exceptions}}'**
  String workersLogsExceptions(int count);

  /// No description provided for @workersOutcomeOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get workersOutcomeOk;

  /// No description provided for @workersOutcomeCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get workersOutcomeCanceled;

  /// No description provided for @workersOutcomeException.
  ///
  /// In en, this message translates to:
  /// **'Exception thrown'**
  String get workersOutcomeException;

  /// No description provided for @workersOutcomeCpu.
  ///
  /// In en, this message translates to:
  /// **'Exceeded CPU limit'**
  String get workersOutcomeCpu;

  /// No description provided for @workersOutcomeMemory.
  ///
  /// In en, this message translates to:
  /// **'Exceeded memory limit'**
  String get workersOutcomeMemory;

  /// No description provided for @workersOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown outcome'**
  String get workersOutcomeUnknown;

  /// No description provided for @pagesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Pages projects in this account.'**
  String get pagesEmpty;

  /// No description provided for @pagesFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get pagesFieldStatus;

  /// No description provided for @pagesFieldBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get pagesFieldBranch;

  /// No description provided for @pagesFieldWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get pagesFieldWhen;

  /// No description provided for @pagesFieldEnv.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get pagesFieldEnv;

  /// No description provided for @pagesStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get pagesStatusSuccess;

  /// No description provided for @pagesStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pagesStatusFailed;

  /// No description provided for @pagesStatusBuilding.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get pagesStatusBuilding;

  /// No description provided for @pagesStatusQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get pagesStatusQueued;

  /// No description provided for @pagesStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get pagesStatusCanceled;

  /// No description provided for @pagesStatusSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get pagesStatusSkipped;

  /// No description provided for @pagesStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get pagesStatusUnknown;

  /// No description provided for @pagesStatusNone.
  ///
  /// In en, this message translates to:
  /// **'No deploys'**
  String get pagesStatusNone;

  /// No description provided for @pagesReasonFailed.
  ///
  /// In en, this message translates to:
  /// **'Last build on {branch} failed {time}.'**
  String pagesReasonFailed(String branch, String time);

  /// No description provided for @pagesReasonFailedNoBranch.
  ///
  /// In en, this message translates to:
  /// **'Last build failed {time}.'**
  String pagesReasonFailedNoBranch(String time);

  /// No description provided for @pagesWorkersNote.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare recommends starting new projects on Workers.'**
  String get pagesWorkersNote;

  /// No description provided for @pagesWorkersNoteLink.
  ///
  /// In en, this message translates to:
  /// **'Migration guide'**
  String get pagesWorkersNoteLink;

  /// No description provided for @pagesEnvProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get pagesEnvProduction;

  /// No description provided for @pagesEnvPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get pagesEnvPreview;

  /// No description provided for @pagesLiveMarker.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get pagesLiveMarker;

  /// No description provided for @pagesDeploymentSemantics.
  ///
  /// In en, this message translates to:
  /// **'Deployment {id}, {status}, {environment}, branch {branch}, {time}'**
  String pagesDeploymentSemantics(String id, String status, String environment, String branch, String time);

  /// No description provided for @pagesOpenSite.
  ///
  /// In en, this message translates to:
  /// **'Open site'**
  String get pagesOpenSite;

  /// No description provided for @pagesSectionProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get pagesSectionProject;

  /// No description provided for @pagesSite.
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get pagesSite;

  /// No description provided for @pagesProductionBranch.
  ///
  /// In en, this message translates to:
  /// **'Production branch'**
  String get pagesProductionBranch;

  /// No description provided for @pagesRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get pagesRepository;

  /// No description provided for @pagesCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get pagesCreated;

  /// No description provided for @pagesSectionDomains.
  ///
  /// In en, this message translates to:
  /// **'Custom domains'**
  String get pagesSectionDomains;

  /// No description provided for @pagesNoDomains.
  ///
  /// In en, this message translates to:
  /// **'No custom domains.'**
  String get pagesNoDomains;

  /// No description provided for @pagesDomainActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pagesDomainActive;

  /// No description provided for @pagesDomainPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pagesDomainPending;

  /// No description provided for @pagesDomainInitializing.
  ///
  /// In en, this message translates to:
  /// **'Setting up'**
  String get pagesDomainInitializing;

  /// No description provided for @pagesDomainBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get pagesDomainBlocked;

  /// No description provided for @pagesDomainDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get pagesDomainDeactivated;

  /// No description provided for @pagesDomainError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get pagesDomainError;

  /// No description provided for @pagesSectionDeployments.
  ///
  /// In en, this message translates to:
  /// **'Deployments'**
  String get pagesSectionDeployments;

  /// No description provided for @pagesNoDeployments.
  ///
  /// In en, this message translates to:
  /// **'No deployments yet.'**
  String get pagesNoDeployments;

  /// No description provided for @pagesDeploymentsHint.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold a deployment to retry, roll back or open it.'**
  String get pagesDeploymentsHint;

  /// No description provided for @pagesSectionDeployment.
  ///
  /// In en, this message translates to:
  /// **'Deployment'**
  String get pagesSectionDeployment;

  /// No description provided for @pagesCommit.
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get pagesCommit;

  /// No description provided for @pagesTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get pagesTrigger;

  /// No description provided for @pagesTriggerPush.
  ///
  /// In en, this message translates to:
  /// **'Git push'**
  String get pagesTriggerPush;

  /// No description provided for @pagesTriggerUpload.
  ///
  /// In en, this message translates to:
  /// **'Direct upload'**
  String get pagesTriggerUpload;

  /// No description provided for @pagesTriggerHook.
  ///
  /// In en, this message translates to:
  /// **'Deploy hook'**
  String get pagesTriggerHook;

  /// No description provided for @pagesAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get pagesAlias;

  /// No description provided for @pagesSectionStages.
  ///
  /// In en, this message translates to:
  /// **'Stages'**
  String get pagesSectionStages;

  /// No description provided for @pagesStageQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get pagesStageQueued;

  /// No description provided for @pagesStageInitialize.
  ///
  /// In en, this message translates to:
  /// **'Initialize'**
  String get pagesStageInitialize;

  /// No description provided for @pagesStageClone.
  ///
  /// In en, this message translates to:
  /// **'Clone repository'**
  String get pagesStageClone;

  /// No description provided for @pagesStageBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get pagesStageBuild;

  /// No description provided for @pagesStageDeploy.
  ///
  /// In en, this message translates to:
  /// **'Deploy'**
  String get pagesStageDeploy;

  /// No description provided for @pagesStageSuccess.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get pagesStageSuccess;

  /// No description provided for @pagesStageActive.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get pagesStageActive;

  /// No description provided for @pagesStageIdle.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get pagesStageIdle;

  /// No description provided for @pagesStageFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get pagesStageFailure;

  /// No description provided for @pagesStageCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get pagesStageCanceled;

  /// No description provided for @pagesStageSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get pagesStageSkipped;

  /// No description provided for @pagesSectionBuildLog.
  ///
  /// In en, this message translates to:
  /// **'Build log'**
  String get pagesSectionBuildLog;

  /// No description provided for @pagesLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'This build has no log lines.'**
  String get pagesLogEmpty;

  /// No description provided for @pagesLogUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare has no build log for this deployment (direct uploads don\'t build).'**
  String get pagesLogUnavailable;

  /// No description provided for @pagesLogPartial.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} lines.'**
  String pagesLogPartial(int shown, int total);

  /// No description provided for @pagesOpenDeployment.
  ///
  /// In en, this message translates to:
  /// **'Open this deployment'**
  String get pagesOpenDeployment;

  /// No description provided for @pagesRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry build'**
  String get pagesRetry;

  /// No description provided for @pagesRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Builds the same commit again as a new deployment'**
  String get pagesRetryHint;

  /// No description provided for @pagesRetryStarted.
  ///
  /// In en, this message translates to:
  /// **'New build started for {name}.'**
  String pagesRetryStarted(String name);

  /// No description provided for @pagesRollbackAction.
  ///
  /// In en, this message translates to:
  /// **'Roll back production to this'**
  String get pagesRollbackAction;

  /// No description provided for @pagesRollbackHint.
  ///
  /// In en, this message translates to:
  /// **'Production serves this deployment again'**
  String get pagesRollbackHint;

  /// No description provided for @pagesRollbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Roll back to {id}?'**
  String pagesRollbackTitle(String id);

  /// No description provided for @pagesRollbackMessage.
  ///
  /// In en, this message translates to:
  /// **'Production for {project} will serve {deployment} again. Newer deployments stay in the list, so you can roll forward the same way.'**
  String pagesRollbackMessage(String project, String deployment);

  /// No description provided for @pagesRollbackConfirm.
  ///
  /// In en, this message translates to:
  /// **'Roll back'**
  String get pagesRollbackConfirm;

  /// No description provided for @pagesRollbackDone.
  ///
  /// In en, this message translates to:
  /// **'Production now serves {id}.'**
  String pagesRollbackDone(String id);

  /// No description provided for @pagesCopyId.
  ///
  /// In en, this message translates to:
  /// **'Copy deployment ID'**
  String get pagesCopyId;

  /// No description provided for @pagesDeploymentOnBranch.
  ///
  /// In en, this message translates to:
  /// **'{id} on {branch}'**
  String pagesDeploymentOnBranch(String id, String branch);

  /// No description provided for @registrarTitle.
  ///
  /// In en, this message translates to:
  /// **'Registrar'**
  String get registrarTitle;

  /// No description provided for @registrarRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Registered domains'**
  String get registrarRowTitle;

  /// No description provided for @registrarSummary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 domain, in line} other{{count} domains, all in line}}'**
  String registrarSummary(int count);

  /// No description provided for @registrarSummaryAttention.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 domain needs you} other{{count} domains need you}}'**
  String registrarSummaryAttention(int count);

  /// No description provided for @registrarSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'No domains registered with Cloudflare'**
  String get registrarSummaryNone;

  /// No description provided for @registrarSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load registrations'**
  String get registrarSummaryFailed;

  /// No description provided for @registrarAccountTokenShort.
  ///
  /// In en, this message translates to:
  /// **'Not available with account-owned tokens'**
  String get registrarAccountTokenShort;

  /// No description provided for @registrarNeedsPermission.
  ///
  /// In en, this message translates to:
  /// **'Needs “{permission}” on the token'**
  String registrarNeedsPermission(String permission);

  /// No description provided for @registrarAccountTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Registrar needs a user API token'**
  String get registrarAccountTokenTitle;

  /// No description provided for @registrarAccountTokenMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare Registrar doesn\'t accept account-owned API tokens. To see expiry dates here, add a user API token with “{permission}” in Settings.'**
  String registrarAccountTokenMessage(String permission);

  /// No description provided for @registrarPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'No access to Registrar'**
  String get registrarPermissionTitle;

  /// No description provided for @registrarPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Add “{permission}” to a user API token in the Cloudflare dashboard, then pull to refresh.'**
  String registrarPermissionMessage(String permission);

  /// No description provided for @registrarFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load registered domains'**
  String get registrarFailedTitle;

  /// No description provided for @registrarEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No domains registered with Cloudflare'**
  String get registrarEmptyTitle;

  /// No description provided for @registrarEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Domains you register or transfer to Cloudflare Registrar show up here with their expiry dates.'**
  String get registrarEmptyMessage;

  /// No description provided for @registrarBayAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get registrarBayAttention;

  /// No description provided for @registrarBayAll.
  ///
  /// In en, this message translates to:
  /// **'In line'**
  String get registrarBayAll;

  /// No description provided for @registrarAllAttention.
  ///
  /// In en, this message translates to:
  /// **'Every registered domain needs a look.'**
  String get registrarAllAttention;

  /// No description provided for @registrarFieldExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get registrarFieldExpires;

  /// No description provided for @registrarFieldAutoRenew.
  ///
  /// In en, this message translates to:
  /// **'Auto-renew'**
  String get registrarFieldAutoRenew;

  /// No description provided for @registrarFieldLock.
  ///
  /// In en, this message translates to:
  /// **'Transfer lock'**
  String get registrarFieldLock;

  /// No description provided for @registrarAutoRenewOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get registrarAutoRenewOn;

  /// No description provided for @registrarAutoRenewOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get registrarAutoRenewOff;

  /// No description provided for @registrarLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get registrarLocked;

  /// No description provided for @registrarUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get registrarUnlocked;

  /// No description provided for @registrarExpiresSemantics.
  ///
  /// In en, this message translates to:
  /// **'expires {date}'**
  String registrarExpiresSemantics(String date);

  /// No description provided for @registrarReasonExpiring.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Expires tomorrow and won\'t renew automatically.} other{Expires in {days} days and won\'t renew automatically.}}'**
  String registrarReasonExpiring(int days);

  /// No description provided for @registrarReasonToday.
  ///
  /// In en, this message translates to:
  /// **'Expires today and won\'t renew automatically.'**
  String get registrarReasonToday;

  /// No description provided for @registrarReasonStatus.
  ///
  /// In en, this message translates to:
  /// **'{status}: renew or restore it in Cloudflare Registrar before it\'s lost.'**
  String registrarReasonStatus(String status);

  /// No description provided for @registrarStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get registrarStatusActive;

  /// No description provided for @registrarStatusRegistering.
  ///
  /// In en, this message translates to:
  /// **'Registering'**
  String get registrarStatusRegistering;

  /// No description provided for @registrarStatusTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring in'**
  String get registrarStatusTransferring;

  /// No description provided for @registrarStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get registrarStatusExpired;

  /// No description provided for @registrarStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get registrarStatusSuspended;

  /// No description provided for @registrarStatusRedemption.
  ///
  /// In en, this message translates to:
  /// **'In redemption period'**
  String get registrarStatusRedemption;

  /// No description provided for @registrarStatusPendingDelete.
  ///
  /// In en, this message translates to:
  /// **'Pending deletion'**
  String get registrarStatusPendingDelete;

  /// No description provided for @registrarStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get registrarStatusUnknown;

  /// No description provided for @registrarFooter.
  ///
  /// In en, this message translates to:
  /// **'Turn on auto-renew in the Cloudflare dashboard so a domain never lapses.'**
  String get registrarFooter;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Edgepost'**
  String get appName;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tabToday;

  /// No description provided for @tabDomains.
  ///
  /// In en, this message translates to:
  /// **'Domains'**
  String get tabDomains;

  /// No description provided for @tabMail.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get tabMail;

  /// No description provided for @tabCompute.
  ///
  /// In en, this message translates to:
  /// **'Compute'**
  String get tabCompute;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @sidebarShow.
  ///
  /// In en, this message translates to:
  /// **'Show sidebar'**
  String get sidebarShow;

  /// No description provided for @sidebarHide.
  ///
  /// In en, this message translates to:
  /// **'Hide sidebar'**
  String get sidebarHide;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedToClipboard;

  /// No description provided for @syncedAt.
  ///
  /// In en, this message translates to:
  /// **'Synced {time}'**
  String syncedAt(String time);

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. Showing data from {time}.'**
  String syncFailed(String time);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 h ago} other{{count} h ago}}'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{yesterday} other{{count} days ago}}'**
  String timeDaysAgo(int count);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again in a moment.'**
  String get errorGeneric;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'This token can\'t do that yet. In the Cloudflare dashboard, add the permission “{permission}” to the token, then pull to refresh.'**
  String errorPermission(String permission);

  /// No description provided for @errorPermissionGeneric.
  ///
  /// In en, this message translates to:
  /// **'This token doesn\'t have permission for this. Edit the token in the Cloudflare dashboard and add the missing permission.'**
  String get errorPermissionGeneric;

  /// No description provided for @typeToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Type {name} to confirm.'**
  String typeToConfirm(String name);

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @emptySearch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String emptySearch(String query);

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchPlaceholder;

  /// No description provided for @syntheticDataLabel.
  ///
  /// In en, this message translates to:
  /// **'Sample data'**
  String get syntheticDataLabel;

  /// No description provided for @actionShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get actionShow;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get actionHide;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @actionSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get actionSend;

  /// No description provided for @timeSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} s ago'**
  String timeSecondsAgo(int count);

  /// No description provided for @tabBadge.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread} other{{count} unread}}'**
  String tabBadge(int count);

  /// No description provided for @tabNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 needs you} other{{count} need you}}'**
  String tabNeedsYou(int count);

  /// No description provided for @errorNoToken.
  ///
  /// In en, this message translates to:
  /// **'None of your API tokens reaches this account any more. Add a token for it in Settings.'**
  String get errorNoToken;

  /// No description provided for @errorNeedsUserToken.
  ///
  /// In en, this message translates to:
  /// **'This needs a user API token: Cloudflare doesn\'t accept account-owned tokens here.'**
  String get errorNeedsUserToken;

  /// No description provided for @confirmAccount.
  ///
  /// In en, this message translates to:
  /// **'Account: {name}'**
  String confirmAccount(String name);

  /// No description provided for @dnsTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS records'**
  String get dnsTitle;

  /// No description provided for @dnsAddRecord.
  ///
  /// In en, this message translates to:
  /// **'Add record'**
  String get dnsAddRecord;

  /// No description provided for @dnsMoreActions.
  ///
  /// In en, this message translates to:
  /// **'Templates, import and export'**
  String get dnsMoreActions;

  /// No description provided for @dnsSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'{type} · {count}'**
  String dnsSectionHeader(String type, int count);

  /// No description provided for @dnsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dnsFilterAll;

  /// No description provided for @dnsFilterAddress.
  ///
  /// In en, this message translates to:
  /// **'A·AAAA'**
  String get dnsFilterAddress;

  /// No description provided for @dnsFilterOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get dnsFilterOther;

  /// No description provided for @dnsSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search names and values'**
  String get dnsSearchPlaceholder;

  /// No description provided for @dnsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No DNS records yet'**
  String get dnsEmptyTitle;

  /// No description provided for @dnsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing resolves for this domain yet. Add a record, start from a template, or import a BIND zone file.'**
  String get dnsEmptyMessage;

  /// No description provided for @dnsFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No records of this type.'**
  String get dnsFilterEmpty;

  /// No description provided for @dnsZoneMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Domain not found'**
  String get dnsZoneMissingTitle;

  /// No description provided for @dnsZoneMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'This domain isn\'t in your list anymore. Refresh the Domains tab, or check that its token is still added in Settings.'**
  String get dnsZoneMissingMessage;

  /// No description provided for @dnsProxied.
  ///
  /// In en, this message translates to:
  /// **'Proxied'**
  String get dnsProxied;

  /// No description provided for @dnsDnsOnly.
  ///
  /// In en, this message translates to:
  /// **'DNS only'**
  String get dnsDnsOnly;

  /// No description provided for @dnsPriorityShort.
  ///
  /// In en, this message translates to:
  /// **'Priority {value}'**
  String dnsPriorityShort(int value);

  /// No description provided for @dnsTtlAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get dnsTtlAuto;

  /// No description provided for @dnsTtlSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String dnsTtlSeconds(int count);

  /// No description provided for @dnsTtlMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String dnsTtlMinutes(int count);

  /// No description provided for @dnsTtlHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String dnsTtlHours(int count);

  /// No description provided for @dnsTtlDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String dnsTtlDays(int count);

  /// No description provided for @dnsRowHint.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold for more actions'**
  String get dnsRowHint;

  /// No description provided for @dnsActionCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy name'**
  String get dnsActionCopyName;

  /// No description provided for @dnsActionCopyContent.
  ///
  /// In en, this message translates to:
  /// **'Copy value'**
  String get dnsActionCopyContent;

  /// No description provided for @dnsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this record?'**
  String get dnsDeleteTitle;

  /// No description provided for @dnsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'The {type} record {name} stops resolving within its TTL. You can undo right after.'**
  String dnsDeleteMessage(String type, String name);

  /// No description provided for @dnsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Record deleted'**
  String get dnsDeleted;

  /// No description provided for @dnsRestored.
  ///
  /// In en, this message translates to:
  /// **'Record restored'**
  String get dnsRestored;

  /// No description provided for @dnsRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the record. {reason}'**
  String dnsRestoreFailed(String reason);

  /// No description provided for @dnsDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the record, so it\'s back in the list. {reason}'**
  String dnsDeleteFailed(String reason);

  /// No description provided for @dnsSaved.
  ///
  /// In en, this message translates to:
  /// **'Record saved'**
  String get dnsSaved;

  /// No description provided for @dnsCreated.
  ///
  /// In en, this message translates to:
  /// **'Record added'**
  String get dnsCreated;

  /// No description provided for @dnsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. {reason}'**
  String dnsSaveFailed(String reason);

  /// No description provided for @dnsMenuPointToIp.
  ///
  /// In en, this message translates to:
  /// **'Point domain to an IP'**
  String get dnsMenuPointToIp;

  /// No description provided for @dnsMenuVerifyTxt.
  ///
  /// In en, this message translates to:
  /// **'Add a verification TXT'**
  String get dnsMenuVerifyTxt;

  /// No description provided for @dnsMenuMailCheck.
  ///
  /// In en, this message translates to:
  /// **'Check mail records'**
  String get dnsMenuMailCheck;

  /// No description provided for @dnsMenuExport.
  ///
  /// In en, this message translates to:
  /// **'Export zone file'**
  String get dnsMenuExport;

  /// No description provided for @dnsMenuImport.
  ///
  /// In en, this message translates to:
  /// **'Import zone file'**
  String get dnsMenuImport;

  /// No description provided for @dnsExportSubject.
  ///
  /// In en, this message translates to:
  /// **'DNS records for {zone}'**
  String dnsExportSubject(String zone);

  /// No description provided for @dnsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export. {reason}'**
  String dnsExportFailed(String reason);

  /// No description provided for @dnsImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import {file}?'**
  String dnsImportTitle(String file);

  /// No description provided for @dnsImportMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare adds the records in this BIND file to {zone}. Zone files can be up to 256 KiB, and Cloudflare accepts 3 imports per minute.'**
  String dnsImportMessage(String zone);

  /// No description provided for @dnsImportDnsOnly.
  ///
  /// In en, this message translates to:
  /// **'Import as DNS only'**
  String get dnsImportDnsOnly;

  /// No description provided for @dnsImportProxied.
  ///
  /// In en, this message translates to:
  /// **'Import and proxy eligible records'**
  String get dnsImportProxied;

  /// No description provided for @dnsImportTooLarge.
  ///
  /// In en, this message translates to:
  /// **'This file is {size} KiB. Cloudflare accepts zone files up to 256 KiB: split it and import each part.'**
  String dnsImportTooLarge(int size);

  /// No description provided for @dnsImportThrottled.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare accepts 3 imports per minute. Try again in {seconds} s.'**
  String dnsImportThrottled(int seconds);

  /// No description provided for @dnsImportDone.
  ///
  /// In en, this message translates to:
  /// **'Added {added} of {parsed} records from the file.'**
  String dnsImportDone(int added, int parsed);

  /// No description provided for @dnsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import. {reason}'**
  String dnsImportFailed(String reason);

  /// No description provided for @dnsImportOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that file. Pick a plain-text BIND zone file.'**
  String get dnsImportOpenFailed;

  /// No description provided for @dnsEditorNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New record'**
  String get dnsEditorNewTitle;

  /// No description provided for @dnsEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit record'**
  String get dnsEditorEditTitle;

  /// No description provided for @dnsRecordMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Record not found'**
  String get dnsRecordMissingTitle;

  /// No description provided for @dnsRecordMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted or changed elsewhere. Go back and pull to refresh.'**
  String get dnsRecordMissingMessage;

  /// No description provided for @dnsSectionRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get dnsSectionRecord;

  /// No description provided for @dnsSectionOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get dnsSectionOptions;

  /// No description provided for @dnsFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get dnsFieldType;

  /// No description provided for @dnsTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get dnsTypeOther;

  /// No description provided for @dnsChooseType.
  ///
  /// In en, this message translates to:
  /// **'Record type'**
  String get dnsChooseType;

  /// No description provided for @dnsFieldTypeRaw.
  ///
  /// In en, this message translates to:
  /// **'Record type'**
  String get dnsFieldTypeRaw;

  /// No description provided for @dnsFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get dnsFieldName;

  /// No description provided for @dnsNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'@ or subdomain'**
  String get dnsNamePlaceholder;

  /// No description provided for @dnsNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Resolves as {name}'**
  String dnsNameHelper(String name);

  /// No description provided for @dnsFieldIpv4.
  ///
  /// In en, this message translates to:
  /// **'IPv4 address'**
  String get dnsFieldIpv4;

  /// No description provided for @dnsFieldIpv6.
  ///
  /// In en, this message translates to:
  /// **'IPv6 address'**
  String get dnsFieldIpv6;

  /// No description provided for @dnsFieldTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get dnsFieldTarget;

  /// No description provided for @dnsTargetHelper.
  ///
  /// In en, this message translates to:
  /// **'A hostname. Use @ for {zone}.'**
  String dnsTargetHelper(String zone);

  /// No description provided for @dnsFieldNameserver.
  ///
  /// In en, this message translates to:
  /// **'Nameserver'**
  String get dnsFieldNameserver;

  /// No description provided for @dnsFieldPtr.
  ///
  /// In en, this message translates to:
  /// **'Domain name'**
  String get dnsFieldPtr;

  /// No description provided for @dnsFieldMailServer.
  ///
  /// In en, this message translates to:
  /// **'Mail server'**
  String get dnsFieldMailServer;

  /// No description provided for @dnsFieldPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get dnsFieldPriority;

  /// No description provided for @dnsPriorityHelper.
  ///
  /// In en, this message translates to:
  /// **'0–65535. Lower numbers are tried first.'**
  String get dnsPriorityHelper;

  /// No description provided for @dnsFieldContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get dnsFieldContent;

  /// No description provided for @dnsTxtHelper.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 character} other{{count} characters}}. Values over 255 characters are split into several strings automatically.'**
  String dnsTxtHelper(int count);

  /// No description provided for @dnsFieldService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get dnsFieldService;

  /// No description provided for @dnsServiceHelper.
  ///
  /// In en, this message translates to:
  /// **'The service label, such as _sip or _imaps.'**
  String get dnsServiceHelper;

  /// No description provided for @dnsFieldProtocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get dnsFieldProtocol;

  /// No description provided for @dnsFieldWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get dnsFieldWeight;

  /// No description provided for @dnsFieldPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get dnsFieldPort;

  /// No description provided for @dnsSrvTargetHelper.
  ///
  /// In en, this message translates to:
  /// **'The host that offers the service. Use a single dot if it isn\'t offered.'**
  String get dnsSrvTargetHelper;

  /// No description provided for @dnsFieldCaaTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get dnsFieldCaaTag;

  /// No description provided for @dnsCaaIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get dnsCaaIssue;

  /// No description provided for @dnsCaaIssueWild.
  ///
  /// In en, this message translates to:
  /// **'Wildcard'**
  String get dnsCaaIssueWild;

  /// No description provided for @dnsCaaIodef.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get dnsCaaIodef;

  /// No description provided for @dnsCaaTagHelp.
  ///
  /// In en, this message translates to:
  /// **'Issue lets a certificate authority issue certificates for this name, Wildcard covers wildcard certificates, and Report says where to send violation reports.'**
  String get dnsCaaTagHelp;

  /// No description provided for @dnsFieldValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get dnsFieldValue;

  /// No description provided for @dnsFieldFlags.
  ///
  /// In en, this message translates to:
  /// **'Flags'**
  String get dnsFieldFlags;

  /// No description provided for @dnsFlagsHelper.
  ///
  /// In en, this message translates to:
  /// **'Usually 0. 128 marks the tag as critical.'**
  String get dnsFlagsHelper;

  /// No description provided for @dnsFieldHttpsValue.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get dnsFieldHttpsValue;

  /// No description provided for @dnsHttpsValueHelper.
  ///
  /// In en, this message translates to:
  /// **'Service parameters, for example alpn=\"h3,h2\". Optional.'**
  String get dnsHttpsValueHelper;

  /// No description provided for @dnsFieldUri.
  ///
  /// In en, this message translates to:
  /// **'URI'**
  String get dnsFieldUri;

  /// No description provided for @dnsOtherDataNote.
  ///
  /// In en, this message translates to:
  /// **'This type stores structured data. Change its value in the Cloudflare dashboard; you can still change the name, TTL and comment here.'**
  String get dnsOtherDataNote;

  /// No description provided for @dnsFieldProxied.
  ///
  /// In en, this message translates to:
  /// **'Proxy through Cloudflare'**
  String get dnsFieldProxied;

  /// No description provided for @dnsProxiedOnHelp.
  ///
  /// In en, this message translates to:
  /// **'Traffic passes through Cloudflare\'s cache and security. Visitors see Cloudflare\'s addresses.'**
  String get dnsProxiedOnHelp;

  /// No description provided for @dnsProxiedOffHelp.
  ///
  /// In en, this message translates to:
  /// **'DNS only: Cloudflare answers with this value and doesn\'t touch the traffic.'**
  String get dnsProxiedOffHelp;

  /// No description provided for @dnsProxiedOnFooter.
  ///
  /// In en, this message translates to:
  /// **'Traffic passes through Cloudflare\'s cache and security, and visitors see Cloudflare\'s addresses. Proxied records always use Auto TTL.'**
  String get dnsProxiedOnFooter;

  /// No description provided for @dnsFieldTtl.
  ///
  /// In en, this message translates to:
  /// **'TTL'**
  String get dnsFieldTtl;

  /// No description provided for @dnsChooseTtl.
  ///
  /// In en, this message translates to:
  /// **'Time to live'**
  String get dnsChooseTtl;

  /// No description provided for @dnsFieldComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get dnsFieldComment;

  /// No description provided for @dnsCommentPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'A note for yourself, not published in DNS'**
  String get dnsCommentPlaceholder;

  /// No description provided for @dnsTypeChangeNote.
  ///
  /// In en, this message translates to:
  /// **'Changing the type replaces the record: the {from} record is deleted and the new one created in a single step.'**
  String dnsTypeChangeNote(String from);

  /// No description provided for @dnsDeleteRecord.
  ///
  /// In en, this message translates to:
  /// **'Delete record'**
  String get dnsDeleteRecord;

  /// No description provided for @dnsErrorName.
  ///
  /// In en, this message translates to:
  /// **'Use @ for the domain itself, or letters, digits, hyphens and dots. Internationalized names go in punycode (xn--…).'**
  String get dnsErrorName;

  /// No description provided for @dnsErrorIpv4.
  ///
  /// In en, this message translates to:
  /// **'Enter an IPv4 address such as 203.0.113.10.'**
  String get dnsErrorIpv4;

  /// No description provided for @dnsErrorIpv6.
  ///
  /// In en, this message translates to:
  /// **'Enter an IPv6 address such as 2001:db8::1.'**
  String get dnsErrorIpv6;

  /// No description provided for @dnsErrorHostname.
  ///
  /// In en, this message translates to:
  /// **'Enter a hostname such as mail.example.com.'**
  String get dnsErrorHostname;

  /// No description provided for @dnsErrorRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 0 to 65535.'**
  String get dnsErrorRange;

  /// No description provided for @dnsErrorFlags.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 0 to 255.'**
  String get dnsErrorFlags;

  /// No description provided for @dnsErrorType.
  ///
  /// In en, this message translates to:
  /// **'Enter a record type in capitals, such as TLSA.'**
  String get dnsErrorType;

  /// No description provided for @dnsErrorQuotes.
  ///
  /// In en, this message translates to:
  /// **'The quotation marks don\'t pair up. Remove them, or wrap each part in its own pair.'**
  String get dnsErrorQuotes;

  /// No description provided for @dnsErrorTooLong.
  ///
  /// In en, this message translates to:
  /// **'The full name is longer than 253 characters.'**
  String get dnsErrorTooLong;

  /// No description provided for @dnsTemplatePointTitle.
  ///
  /// In en, this message translates to:
  /// **'Point to an IP'**
  String get dnsTemplatePointTitle;

  /// No description provided for @dnsTemplatePointIntro.
  ///
  /// In en, this message translates to:
  /// **'Sends {zone} to your server\'s IP address.'**
  String dnsTemplatePointIntro(String zone);

  /// No description provided for @dnsTemplateIpLabel.
  ///
  /// In en, this message translates to:
  /// **'Server IP address'**
  String get dnsTemplateIpLabel;

  /// No description provided for @dnsTemplateIpHelper.
  ///
  /// In en, this message translates to:
  /// **'IPv4 or IPv6.'**
  String get dnsTemplateIpHelper;

  /// No description provided for @dnsTemplateErrorIp.
  ///
  /// In en, this message translates to:
  /// **'Enter an IPv4 or IPv6 address.'**
  String get dnsTemplateErrorIp;

  /// No description provided for @dnsTemplateIncludeWww.
  ///
  /// In en, this message translates to:
  /// **'Also point www'**
  String get dnsTemplateIncludeWww;

  /// No description provided for @dnsTemplateIncludeWwwHelp.
  ///
  /// In en, this message translates to:
  /// **'Adds www.{zone} as a CNAME to {zone}.'**
  String dnsTemplateIncludeWwwHelp(String zone);

  /// No description provided for @dnsTemplateCreates.
  ///
  /// In en, this message translates to:
  /// **'Creates'**
  String get dnsTemplateCreates;

  /// No description provided for @dnsTemplateReplaces.
  ///
  /// In en, this message translates to:
  /// **'Replaces'**
  String get dnsTemplateReplaces;

  /// No description provided for @dnsTemplateReplacesFooter.
  ///
  /// In en, this message translates to:
  /// **'These records would conflict, so they\'re removed in the same step.'**
  String get dnsTemplateReplacesFooter;

  /// No description provided for @dnsTemplateReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace {count, plural, =1{1 record} other{{count} records}}?'**
  String dnsTemplateReplaceTitle(int count);

  /// No description provided for @dnsTemplateReplaceMessage.
  ///
  /// In en, this message translates to:
  /// **'The current address records for {zone} are deleted and the new ones created in a single step.'**
  String dnsTemplateReplaceMessage(String zone);

  /// No description provided for @dnsTemplateReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get dnsTemplateReplace;

  /// No description provided for @dnsTemplateApplied.
  ///
  /// In en, this message translates to:
  /// **'Records added'**
  String get dnsTemplateApplied;

  /// No description provided for @dnsTemplateVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification TXT'**
  String get dnsTemplateVerifyTitle;

  /// No description provided for @dnsTemplateVerifyIntro.
  ///
  /// In en, this message translates to:
  /// **'Services such as Google, Microsoft and Apple ask for a TXT record to prove you own {zone}.'**
  String dnsTemplateVerifyIntro(String zone);

  /// No description provided for @dnsTemplateVerifyHelper.
  ///
  /// In en, this message translates to:
  /// **'Paste the exact value the service gave you.'**
  String get dnsTemplateVerifyHelper;

  /// No description provided for @dnsMailTitle.
  ///
  /// In en, this message translates to:
  /// **'Mail records'**
  String get dnsMailTitle;

  /// No description provided for @dnsMailIntro.
  ///
  /// In en, this message translates to:
  /// **'A read-only check of the records that decide where mail for {zone} goes and whether mail from it is trusted.'**
  String dnsMailIntro(String zone);

  /// No description provided for @dnsMailMx.
  ///
  /// In en, this message translates to:
  /// **'Receiving (MX)'**
  String get dnsMailMx;

  /// No description provided for @dnsMailSpf.
  ///
  /// In en, this message translates to:
  /// **'Allowed senders (SPF)'**
  String get dnsMailSpf;

  /// No description provided for @dnsMailDmarc.
  ///
  /// In en, this message translates to:
  /// **'Policy (DMARC)'**
  String get dnsMailDmarc;

  /// No description provided for @dnsMailDkim.
  ///
  /// In en, this message translates to:
  /// **'Signatures (DKIM)'**
  String get dnsMailDkim;

  /// No description provided for @dnsMailStatusOk.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get dnsMailStatusOk;

  /// No description provided for @dnsMailStatusWarn.
  ///
  /// In en, this message translates to:
  /// **'Needs a look'**
  String get dnsMailStatusWarn;

  /// No description provided for @dnsMailStatusMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get dnsMailStatusMissing;

  /// No description provided for @dnsMailMxOk.
  ///
  /// In en, this message translates to:
  /// **'Mail for {zone} goes to the servers below, lowest priority first.'**
  String dnsMailMxOk(String zone);

  /// No description provided for @dnsMailMxRouting.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare Email Routing receives mail for {zone}.'**
  String dnsMailMxRouting(String zone);

  /// No description provided for @dnsMailMxMissing.
  ///
  /// In en, this message translates to:
  /// **'Nobody can send mail to {zone}. Turn on Email Routing, or add the MX records your mail provider gives you.'**
  String dnsMailMxMissing(String zone);

  /// No description provided for @dnsMailMxNull.
  ///
  /// In en, this message translates to:
  /// **'This null MX record says {zone} accepts no mail. Remove it if you want to receive mail here.'**
  String dnsMailMxNull(String zone);

  /// No description provided for @dnsMailSpfOk.
  ///
  /// In en, this message translates to:
  /// **'Receivers can check which servers may send mail as {zone}.'**
  String dnsMailSpfOk(String zone);

  /// No description provided for @dnsMailSpfMissing.
  ///
  /// In en, this message translates to:
  /// **'Without SPF, mail from {zone} is more likely to land in spam, and anyone can pose as you. Add the SPF record your mail provider gives you, or v=spf1 -all if this domain never sends mail.'**
  String dnsMailSpfMissing(String zone);

  /// No description provided for @dnsMailSpfMultiple.
  ///
  /// In en, this message translates to:
  /// **'There are several SPF records. Receivers treat that as an error, so merge them into one.'**
  String get dnsMailSpfMultiple;

  /// No description provided for @dnsMailSpfPassAll.
  ///
  /// In en, this message translates to:
  /// **'This SPF record lets any server send as {zone}. End it with ~all or -all instead.'**
  String dnsMailSpfPassAll(String zone);

  /// No description provided for @dnsMailDmarcOk.
  ///
  /// In en, this message translates to:
  /// **'Receivers know what to do with mail that fails SPF and DKIM.'**
  String get dnsMailDmarcOk;

  /// No description provided for @dnsMailDmarcNone.
  ///
  /// In en, this message translates to:
  /// **'The policy is p=none, so receivers only report failures. Move to quarantine or reject once the reports look clean.'**
  String get dnsMailDmarcNone;

  /// No description provided for @dnsMailDmarcMissing.
  ///
  /// In en, this message translates to:
  /// **'Without DMARC, receivers decide on their own what to do with forged mail from {zone}. Start with a monitoring policy.'**
  String dnsMailDmarcMissing(String zone);

  /// No description provided for @dnsMailDmarcMultiple.
  ///
  /// In en, this message translates to:
  /// **'There are several DMARC records at _dmarc. Keep exactly one.'**
  String get dnsMailDmarcMultiple;

  /// No description provided for @dnsMailDkimOk.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 signing key published.} other{{count} signing keys published.}}'**
  String dnsMailDkimOk(int count);

  /// No description provided for @dnsMailDkimMissing.
  ///
  /// In en, this message translates to:
  /// **'No DKIM keys under _domainkey. If you send mail from {zone}, add the DKIM record your mail provider gives you.'**
  String dnsMailDkimMissing(String zone);

  /// No description provided for @dnsMailAddDmarc.
  ///
  /// In en, this message translates to:
  /// **'Add a monitoring DMARC record'**
  String get dnsMailAddDmarc;

  /// No description provided for @routingTitle.
  ///
  /// In en, this message translates to:
  /// **'Email routing'**
  String get routingTitle;

  /// No description provided for @routingStripCaption.
  ///
  /// In en, this message translates to:
  /// **'Email routing'**
  String get routingStripCaption;

  /// No description provided for @routingFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get routingFieldStatus;

  /// No description provided for @routingFieldRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get routingFieldRules;

  /// No description provided for @routingFieldCatchAll.
  ///
  /// In en, this message translates to:
  /// **'Catch-all'**
  String get routingFieldCatchAll;

  /// No description provided for @routingStatusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get routingStatusReady;

  /// No description provided for @routingStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get routingStatusOff;

  /// No description provided for @routingStatusMisconfigured.
  ///
  /// In en, this message translates to:
  /// **'Misconfigured'**
  String get routingStatusMisconfigured;

  /// No description provided for @routingStatusUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get routingStatusUnlocked;

  /// No description provided for @routingReasonOff.
  ///
  /// In en, this message translates to:
  /// **'Routing is off. Turn it on to receive mail at this domain through Cloudflare.'**
  String get routingReasonOff;

  /// No description provided for @routingReasonMisconfigured.
  ///
  /// In en, this message translates to:
  /// **'DNS records don\'t match what Email Routing needs, so mail may not arrive. Add the missing records below.'**
  String get routingReasonMisconfigured;

  /// No description provided for @routingReasonUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Routing records are unlocked and can be changed. Lock them again when you\'re done.'**
  String get routingReasonUnlocked;

  /// No description provided for @routingReasonUnverified.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 rule waits on an unverified destination and can\'t deliver yet.} other{{count} rules wait on unverified destinations and can\'t deliver yet.}}'**
  String routingReasonUnverified(int count);

  /// No description provided for @routingEnableHeader.
  ///
  /// In en, this message translates to:
  /// **'Turn on Email Routing'**
  String get routingEnableHeader;

  /// No description provided for @routingEnableExplain.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare adds the MX and SPF records {domain} needs and locks them so other DNS edits can\'t break delivery. Mail for {domain} then arrives at Cloudflare instead of any other mail provider.'**
  String routingEnableExplain(String domain);

  /// No description provided for @routingEnableRecordsFooter.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare adds these records when you turn routing on.'**
  String get routingEnableRecordsFooter;

  /// No description provided for @routingEnableAction.
  ///
  /// In en, this message translates to:
  /// **'Turn on routing'**
  String get routingEnableAction;

  /// No description provided for @routingEnableConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on routing for {domain}?'**
  String routingEnableConfirmTitle(String domain);

  /// No description provided for @routingEnableConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare adds and locks the routing records. Mail for {domain} stops reaching any other mail provider.'**
  String routingEnableConfirmMessage(String domain);

  /// No description provided for @routingEnabledToast.
  ///
  /// In en, this message translates to:
  /// **'Email routing is on.'**
  String get routingEnabledToast;

  /// No description provided for @routingMisconfiguredExplain.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare can add the missing MX and SPF records and lock them. If this domain used another mail provider, remove its MX records in DNS first.'**
  String get routingMisconfiguredExplain;

  /// No description provided for @routingRepairAction.
  ///
  /// In en, this message translates to:
  /// **'Add missing records'**
  String get routingRepairAction;

  /// No description provided for @routingRepairedToast.
  ///
  /// In en, this message translates to:
  /// **'Records added and locked.'**
  String get routingRepairedToast;

  /// No description provided for @routingUnlockedExplain.
  ///
  /// In en, this message translates to:
  /// **'The MX and SPF records are unlocked, so DNS edits can change them. Lock them again to protect mail delivery.'**
  String get routingUnlockedExplain;

  /// No description provided for @routingLockAction.
  ///
  /// In en, this message translates to:
  /// **'Lock records'**
  String get routingLockAction;

  /// No description provided for @routingRulesHeader.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get routingRulesHeader;

  /// No description provided for @routingRulesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} rules used.'**
  String routingRulesCount(int count, int max);

  /// No description provided for @routingRulesOffFooter.
  ///
  /// In en, this message translates to:
  /// **'Rules take effect once routing is on.'**
  String get routingRulesOffFooter;

  /// No description provided for @routingRulesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No address rules yet'**
  String get routingRulesEmptyTitle;

  /// No description provided for @routingRulesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add one to send mail for an address at {domain} to an inbox, your Edgepost mailbox, or nowhere.'**
  String routingRulesEmptyMessage(String domain);

  /// No description provided for @routingAddRule.
  ///
  /// In en, this message translates to:
  /// **'New address rule'**
  String get routingAddRule;

  /// No description provided for @routingRuleArrow.
  ///
  /// In en, this message translates to:
  /// **'→'**
  String get routingRuleArrow;

  /// No description provided for @routingRuleOffNote.
  ///
  /// In en, this message translates to:
  /// **'Off.'**
  String get routingRuleOffNote;

  /// No description provided for @routingRuleUnverifiedNote.
  ///
  /// In en, this message translates to:
  /// **'Destination not verified, so this rule can\'t deliver yet.'**
  String get routingRuleUnverifiedNote;

  /// No description provided for @routingRuleWranglerNote.
  ///
  /// In en, this message translates to:
  /// **'Managed by a Worker\'s Wrangler config.'**
  String get routingRuleWranglerNote;

  /// No description provided for @routingRuleTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get routingRuleTurnOff;

  /// No description provided for @routingRuleTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get routingRuleTurnOn;

  /// No description provided for @routingRuleTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'{address} is off.'**
  String routingRuleTurnedOff(String address);

  /// No description provided for @routingRuleTurnedOn.
  ///
  /// In en, this message translates to:
  /// **'{address} is on.'**
  String routingRuleTurnedOn(String address);

  /// No description provided for @routingRuleDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {address}?'**
  String routingRuleDeleteTitle(String address);

  /// No description provided for @routingRuleDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Mail to this address is no longer routed by this rule. The catch-all handles it if it\'s on.'**
  String get routingRuleDeleteMessage;

  /// No description provided for @routingRuleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {address}.'**
  String routingRuleDeleted(String address);

  /// No description provided for @routingRuleSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved {address}.'**
  String routingRuleSaved(String address);

  /// No description provided for @routingCatchAllHeader.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get routingCatchAllHeader;

  /// No description provided for @routingCatchAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Catch-all'**
  String get routingCatchAllTitle;

  /// No description provided for @routingCatchAllFooter.
  ///
  /// In en, this message translates to:
  /// **'Handles mail to any address at {domain} that has no rule of its own, including typos.'**
  String routingCatchAllFooter(String domain);

  /// No description provided for @routingCatchAllOffLine.
  ///
  /// In en, this message translates to:
  /// **'Off. Mail to addresses without a rule isn\'t delivered.'**
  String get routingCatchAllOffLine;

  /// No description provided for @routingCatchAllOffShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get routingCatchAllOffShort;

  /// No description provided for @routingCatchAllSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Catch-all'**
  String get routingCatchAllSheetTitle;

  /// No description provided for @routingCatchAllSheetMessage.
  ///
  /// In en, this message translates to:
  /// **'What happens to mail for addresses at {domain} that have no rule?'**
  String routingCatchAllSheetMessage(String domain);

  /// No description provided for @routingCatchAllOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get routingCatchAllOff;

  /// No description provided for @routingCatchAllForward.
  ///
  /// In en, this message translates to:
  /// **'Forward to…'**
  String get routingCatchAllForward;

  /// No description provided for @routingCatchAllDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get routingCatchAllDrop;

  /// No description provided for @routingCatchAllSaved.
  ///
  /// In en, this message translates to:
  /// **'Catch-all updated.'**
  String get routingCatchAllSaved;

  /// No description provided for @routingActionForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get routingActionForward;

  /// No description provided for @routingActionMailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox'**
  String get routingActionMailbox;

  /// No description provided for @routingActionWorker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get routingActionWorker;

  /// No description provided for @routingActionDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get routingActionDrop;

  /// No description provided for @routingActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get routingActionUnknown;

  /// No description provided for @routingDestMailbox.
  ///
  /// In en, this message translates to:
  /// **'Edgepost mailbox'**
  String get routingDestMailbox;

  /// No description provided for @routingDestWorker.
  ///
  /// In en, this message translates to:
  /// **'Worker {name}'**
  String routingDestWorker(String name);

  /// No description provided for @routingDestDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get routingDestDropped;

  /// No description provided for @routingDestinationsLink.
  ///
  /// In en, this message translates to:
  /// **'Destination addresses'**
  String get routingDestinationsLink;

  /// No description provided for @routingPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting for verification'**
  String routingPendingCount(int count);

  /// No description provided for @routingPickDestinationTitle.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get routingPickDestinationTitle;

  /// No description provided for @routingPickDestinationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Destination addresses couldn\'t be loaded. Add one here, or check that the token has Email Routing Addresses permission.'**
  String get routingPickDestinationUnavailable;

  /// No description provided for @routingPendingAddress.
  ///
  /// In en, this message translates to:
  /// **'{address} (waiting for verification)'**
  String routingPendingAddress(String address);

  /// No description provided for @routingAddAddressEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Add address…'**
  String get routingAddAddressEllipsis;

  /// No description provided for @routingAddAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get routingAddAddress;

  /// No description provided for @routingAddAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Add destination address'**
  String get routingAddAddressTitle;

  /// No description provided for @routingAddAddressMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare emails this address a link. Mail is forwarded to it only after the owner clicks it.'**
  String get routingAddAddressMessage;

  /// No description provided for @routingAddressPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get routingAddressPlaceholder;

  /// No description provided for @routingAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a full email address, like you@example.com.'**
  String get routingAddressInvalid;

  /// No description provided for @routingAddressAddedToast.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare sent a verification link to {email}.'**
  String routingAddressAddedToast(String email);

  /// No description provided for @routingAuthHeader.
  ///
  /// In en, this message translates to:
  /// **'Mail authentication'**
  String get routingAuthHeader;

  /// No description provided for @routingAuthLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check mail authentication'**
  String get routingAuthLoadFailed;

  /// No description provided for @routingAuthNeedsDnsTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS access needed to check SPF, DKIM and DMARC'**
  String get routingAuthNeedsDnsTitle;

  /// No description provided for @routingAuthNoDmarcPermission.
  ///
  /// In en, this message translates to:
  /// **'Add “{permission}” to the token to also see SPF lookup counts and DMARC report status.'**
  String routingAuthNoDmarcPermission(String permission);

  /// No description provided for @routingAuthSpf.
  ///
  /// In en, this message translates to:
  /// **'SPF'**
  String get routingAuthSpf;

  /// No description provided for @routingAuthDkim.
  ///
  /// In en, this message translates to:
  /// **'DKIM'**
  String get routingAuthDkim;

  /// No description provided for @routingAuthDmarc.
  ///
  /// In en, this message translates to:
  /// **'DMARC'**
  String get routingAuthDmarc;

  /// No description provided for @routingAuthMx.
  ///
  /// In en, this message translates to:
  /// **'MX'**
  String get routingAuthMx;

  /// No description provided for @routingAuthStateOk.
  ///
  /// In en, this message translates to:
  /// **'Passing'**
  String get routingAuthStateOk;

  /// No description provided for @routingAuthStateAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get routingAuthStateAttention;

  /// No description provided for @routingAuthStateMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get routingAuthStateMissing;

  /// No description provided for @routingAuthStateUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get routingAuthStateUnknown;

  /// No description provided for @routingAuthCopySuggestion.
  ///
  /// In en, this message translates to:
  /// **'Copy suggested {kind} record'**
  String routingAuthCopySuggestion(String kind);

  /// No description provided for @routingAuthUnknownAdvice.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t be checked.'**
  String get routingAuthUnknownAdvice;

  /// No description provided for @routingAuthSpfOk.
  ///
  /// In en, this message translates to:
  /// **'Published and valid.'**
  String get routingAuthSpfOk;

  /// No description provided for @routingAuthSpfOkLookups.
  ///
  /// In en, this message translates to:
  /// **'Published and valid. Uses {count} of 10 DNS lookups.'**
  String routingAuthSpfOkLookups(int count);

  /// No description provided for @routingAuthSpfMissing.
  ///
  /// In en, this message translates to:
  /// **'No SPF record, so receivers can\'t tell which servers may send as this domain.'**
  String get routingAuthSpfMissing;

  /// No description provided for @routingAuthSpfMissingRouting.
  ///
  /// In en, this message translates to:
  /// **'No SPF record. Copy Cloudflare\'s record and add it as a TXT record on the domain.'**
  String get routingAuthSpfMissingRouting;

  /// No description provided for @routingAuthSpfMultiple.
  ///
  /// In en, this message translates to:
  /// **'More than one SPF record, which receivers treat as an error. Replace them with the merged record.'**
  String get routingAuthSpfMultiple;

  /// No description provided for @routingAuthSpfNoCloudflare.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t include Cloudflare\'s mail servers. Copy the updated record, which adds include:_spf.mx.cloudflare.net.'**
  String get routingAuthSpfNoCloudflare;

  /// No description provided for @routingAuthSpfPassAll.
  ///
  /// In en, this message translates to:
  /// **'Ends in +all, which lets any server send as this domain. Copy the record ending in ~all instead.'**
  String get routingAuthSpfPassAll;

  /// No description provided for @routingAuthSpfTooManyLookups.
  ///
  /// In en, this message translates to:
  /// **'Needs {count} DNS lookups; the limit is 10, so SPF fails. Remove includes you no longer use.'**
  String routingAuthSpfTooManyLookups(int count);

  /// No description provided for @routingAuthSpfInvalid.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare couldn\'t evaluate it: {detail}'**
  String routingAuthSpfInvalid(String detail);

  /// No description provided for @routingAuthDkimOk.
  ///
  /// In en, this message translates to:
  /// **'Email Routing\'s signing key (cf2024-1) is published.'**
  String get routingAuthDkimOk;

  /// No description provided for @routingAuthDkimMissing.
  ///
  /// In en, this message translates to:
  /// **'No Email Routing signing key. Cloudflare adds it when routing is turned on.'**
  String get routingAuthDkimMissing;

  /// No description provided for @routingAuthDkimMissingRouting.
  ///
  /// In en, this message translates to:
  /// **'Email Routing\'s signing key (cf2024-1) is missing. Copy it and add it as a TXT record at cf2024-1._domainkey.'**
  String get routingAuthDkimMissingRouting;

  /// No description provided for @routingAuthDkimOther.
  ///
  /// In en, this message translates to:
  /// **'Keys published for: {selectors}.'**
  String routingAuthDkimOther(String selectors);

  /// No description provided for @routingAuthDmarcOk.
  ///
  /// In en, this message translates to:
  /// **'Enforced: spoofed mail is quarantined or rejected.'**
  String get routingAuthDmarcOk;

  /// No description provided for @routingAuthDmarcNoReports.
  ///
  /// In en, this message translates to:
  /// **'Enforced. Reports don\'t reach Cloudflare; turn on DMARC Management in the dashboard to see who sends as this domain.'**
  String get routingAuthDmarcNoReports;

  /// No description provided for @routingAuthDmarcCname.
  ///
  /// In en, this message translates to:
  /// **'Published through a CNAME and valid.'**
  String get routingAuthDmarcCname;

  /// No description provided for @routingAuthDmarcMissing.
  ///
  /// In en, this message translates to:
  /// **'No DMARC policy. Add one at _dmarc: start with p=none to monitor, then move to quarantine.'**
  String get routingAuthDmarcMissing;

  /// No description provided for @routingAuthDmarcMultiple.
  ///
  /// In en, this message translates to:
  /// **'More than one DMARC record, so receivers ignore them all. Keep one.'**
  String get routingAuthDmarcMultiple;

  /// No description provided for @routingAuthDmarcNone.
  ///
  /// In en, this message translates to:
  /// **'Policy is none, so spoofed mail still gets delivered. Move to p=quarantine once your senders pass.'**
  String get routingAuthDmarcNone;

  /// No description provided for @routingAuthDmarcInvalid.
  ///
  /// In en, this message translates to:
  /// **'The record has no valid policy (p=none, quarantine or reject). Replace it.'**
  String get routingAuthDmarcInvalid;

  /// No description provided for @routingAuthDmarcReportIssue.
  ///
  /// In en, this message translates to:
  /// **'DMARC reports need a fix ({status}). Check DMARC Management in the Cloudflare dashboard.'**
  String routingAuthDmarcReportIssue(String status);

  /// No description provided for @routingAuthForeignMx.
  ///
  /// In en, this message translates to:
  /// **'Other MX hosts ({hosts}) compete with Cloudflare\'s, so some mail skips your rules. Remove them in DNS.'**
  String routingAuthForeignMx(String hosts);

  /// No description provided for @routingCopyRecordHint.
  ///
  /// In en, this message translates to:
  /// **'Copies the record value'**
  String get routingCopyRecordHint;

  /// No description provided for @routingDnsHeader.
  ///
  /// In en, this message translates to:
  /// **'Routing DNS records'**
  String get routingDnsHeader;

  /// No description provided for @routingDnsLockedFooter.
  ///
  /// In en, this message translates to:
  /// **'Locked by Email Routing, so DNS edits can\'t change them.'**
  String get routingDnsLockedFooter;

  /// No description provided for @routingDnsUnlockedFooter.
  ///
  /// In en, this message translates to:
  /// **'Unlocked: DNS edits can change these records.'**
  String get routingDnsUnlockedFooter;

  /// No description provided for @routingDnsPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String routingDnsPriority(int priority);

  /// No description provided for @routingUnlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock records'**
  String get routingUnlockAction;

  /// No description provided for @routingUnlockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock routing records?'**
  String get routingUnlockConfirmTitle;

  /// No description provided for @routingUnlockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The MX and SPF records become editable. A wrong edit can stop mail from arriving. Lock them again when you\'re done.'**
  String get routingUnlockConfirmMessage;

  /// No description provided for @routingDisableAction.
  ///
  /// In en, this message translates to:
  /// **'Turn off Email Routing'**
  String get routingDisableAction;

  /// No description provided for @routingDisableFooter.
  ///
  /// In en, this message translates to:
  /// **'Removes the MX records Email Routing added. Mail to every address at this domain stops arriving.'**
  String get routingDisableFooter;

  /// No description provided for @routingDisableConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off Email Routing?'**
  String get routingDisableConfirmTitle;

  /// No description provided for @routingDisableConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare removes the MX records it added for {domain}. Mail to every address there, including your Edgepost mailbox, stops arriving until you turn routing back on.'**
  String routingDisableConfirmMessage(String domain);

  /// No description provided for @routingDisabledToast.
  ///
  /// In en, this message translates to:
  /// **'Email routing is off.'**
  String get routingDisabledToast;

  /// No description provided for @routingEditorNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New address'**
  String get routingEditorNewTitle;

  /// No description provided for @routingEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit address'**
  String get routingEditorEditTitle;

  /// No description provided for @routingEditorGoneTitle.
  ///
  /// In en, this message translates to:
  /// **'This rule no longer exists'**
  String get routingEditorGoneTitle;

  /// No description provided for @routingEditorGoneMessage.
  ///
  /// In en, this message translates to:
  /// **'It was deleted, perhaps from another device or the Cloudflare dashboard.'**
  String get routingEditorGoneMessage;

  /// No description provided for @routingEditorAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get routingEditorAddressLabel;

  /// No description provided for @routingEditorAddressPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'contact'**
  String get routingEditorAddressPlaceholder;

  /// No description provided for @routingEditorAddressHelp.
  ///
  /// In en, this message translates to:
  /// **'The part before the @.'**
  String get routingEditorAddressHelp;

  /// No description provided for @routingEditorAddressPreview.
  ///
  /// In en, this message translates to:
  /// **'Mail to {address}'**
  String routingEditorAddressPreview(String address);

  /// No description provided for @routingEditorAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the part before the @.'**
  String get routingEditorAddressRequired;

  /// No description provided for @routingEditorAddressTooLong.
  ///
  /// In en, this message translates to:
  /// **'Too long: up to 64 characters before the @, and 90 for the whole address.'**
  String get routingEditorAddressTooLong;

  /// No description provided for @routingEditorAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers and symbols like . _ + - with no spaces, and no dot at the start, the end or twice in a row.'**
  String get routingEditorAddressInvalid;

  /// No description provided for @routingEditorDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This address already has a rule. Edit that one instead.'**
  String get routingEditorDuplicate;

  /// No description provided for @routingEditorLimit.
  ///
  /// In en, this message translates to:
  /// **'This domain has {max} rules, Cloudflare\'s limit. Delete one, or use the catch-all.'**
  String routingEditorLimit(int max);

  /// No description provided for @routingEditorActionLabel.
  ///
  /// In en, this message translates to:
  /// **'When mail arrives'**
  String get routingEditorActionLabel;

  /// No description provided for @routingEditorForwardHelp.
  ///
  /// In en, this message translates to:
  /// **'Forward it to an address you own, such as your personal inbox.'**
  String get routingEditorForwardHelp;

  /// No description provided for @routingEditorMailboxHelp.
  ///
  /// In en, this message translates to:
  /// **'Keep it in your Edgepost mailbox, the {worker} Worker in your account. Set up the mailbox in the Mail tab first.'**
  String routingEditorMailboxHelp(String worker);

  /// No description provided for @routingEditorWorkerHelp.
  ///
  /// In en, this message translates to:
  /// **'Handled by the Worker {worker}.'**
  String routingEditorWorkerHelp(String worker);

  /// No description provided for @routingEditorDropHelp.
  ///
  /// In en, this message translates to:
  /// **'Discard mail sent to this address.'**
  String get routingEditorDropHelp;

  /// No description provided for @routingEditorDeliverTo.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get routingEditorDeliverTo;

  /// No description provided for @routingEditorDestFooter.
  ///
  /// In en, this message translates to:
  /// **'Destination addresses belong to the account and work for every domain in it.'**
  String get routingEditorDestFooter;

  /// No description provided for @routingEditorPendingFooter.
  ///
  /// In en, this message translates to:
  /// **'{email} isn\'t verified yet. The rule can\'t deliver until its owner clicks the link Cloudflare emailed.'**
  String routingEditorPendingFooter(String email);

  /// No description provided for @routingEditorPickDestination.
  ///
  /// In en, this message translates to:
  /// **'Choose where to forward mail.'**
  String get routingEditorPickDestination;

  /// No description provided for @routingEditorEnabled.
  ///
  /// In en, this message translates to:
  /// **'Rule on'**
  String get routingEditorEnabled;

  /// No description provided for @routingEditorEnabledHelp.
  ///
  /// In en, this message translates to:
  /// **'Turn off to pause this address without deleting it.'**
  String get routingEditorEnabledHelp;

  /// No description provided for @routingEditorDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete rule'**
  String get routingEditorDelete;

  /// No description provided for @routingSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get routingSelected;

  /// No description provided for @routingAddressesTitle.
  ///
  /// In en, this message translates to:
  /// **'Destination addresses'**
  String get routingAddressesTitle;

  /// No description provided for @routingAddressesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No destination addresses'**
  String get routingAddressesEmptyTitle;

  /// No description provided for @routingAddressesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add an inbox you own. Cloudflare emails it a link, and forwarding starts once the owner clicks it.'**
  String get routingAddressesEmptyMessage;

  /// No description provided for @routingAddressesPendingHeader.
  ///
  /// In en, this message translates to:
  /// **'Waiting for verification'**
  String get routingAddressesPendingHeader;

  /// No description provided for @routingAddressesPendingFooter.
  ///
  /// In en, this message translates to:
  /// **'Each owner must click the link Cloudflare emailed. Edgepost can\'t resend it, because Cloudflare\'s API has no way to; resend it from the Cloudflare dashboard.'**
  String get routingAddressesPendingFooter;

  /// No description provided for @routingAddressesVerifiedHeader.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get routingAddressesVerifiedHeader;

  /// No description provided for @routingAddressesAccountNote.
  ///
  /// In en, this message translates to:
  /// **'These addresses belong to the account {account} and work for every domain in it.'**
  String routingAddressesAccountNote(String account);

  /// No description provided for @routingAddressVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get routingAddressVerified;

  /// No description provided for @routingAddressVerifiedOn.
  ///
  /// In en, this message translates to:
  /// **'Verified {date}'**
  String routingAddressVerifiedOn(String date);

  /// No description provided for @routingAddressWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for verification'**
  String get routingAddressWaiting;

  /// No description provided for @routingAddressWaitingSince.
  ///
  /// In en, this message translates to:
  /// **'Waiting for verification since {date}'**
  String routingAddressWaitingSince(String date);

  /// No description provided for @routingAddressDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {email}?'**
  String routingAddressDeleteTitle(String email);

  /// No description provided for @routingAddressDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Rules that forward to it stop delivering mail.'**
  String get routingAddressDeleteMessage;

  /// No description provided for @routingAddressDeleteUsed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 rule on {domain} forwards to it and will stop delivering mail.} other{{count} rules on {domain} forward to it and will stop delivering mail.}}'**
  String routingAddressDeleteUsed(int count, String domain);

  /// No description provided for @routingAddressDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {email}.'**
  String routingAddressDeleted(String email);

  /// No description provided for @mailAllInboxes.
  ///
  /// In en, this message translates to:
  /// **'All inboxes'**
  String get mailAllInboxes;

  /// No description provided for @mailFolderInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get mailFolderInbox;

  /// No description provided for @mailFolderSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get mailFolderSent;

  /// No description provided for @mailFolderArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get mailFolderArchive;

  /// No description provided for @mailFolderTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get mailFolderTrash;

  /// No description provided for @mailCompose.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get mailCompose;

  /// No description provided for @mailReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get mailReply;

  /// No description provided for @mailReplyAll.
  ///
  /// In en, this message translates to:
  /// **'Reply all'**
  String get mailReplyAll;

  /// No description provided for @mailForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get mailForward;

  /// No description provided for @mailArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get mailArchive;

  /// No description provided for @mailMoveToInbox.
  ///
  /// In en, this message translates to:
  /// **'Move to inbox'**
  String get mailMoveToInbox;

  /// No description provided for @mailTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get mailTrash;

  /// No description provided for @mailDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get mailDeleteForever;

  /// No description provided for @mailDeleteForeverConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this message forever? It can\'t be recovered.'**
  String get mailDeleteForeverConfirm;

  /// No description provided for @mailMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get mailMarkRead;

  /// No description provided for @mailMarkUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get mailMarkUnread;

  /// No description provided for @mailStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get mailStar;

  /// No description provided for @mailUnstar.
  ///
  /// In en, this message translates to:
  /// **'Remove star'**
  String get mailUnstar;

  /// No description provided for @mailArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get mailArchived;

  /// No description provided for @mailTrashed.
  ///
  /// In en, this message translates to:
  /// **'Moved to trash'**
  String get mailTrashed;

  /// No description provided for @mailMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved to inbox'**
  String get mailMoved;

  /// No description provided for @mailDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get mailDeleted;

  /// No description provided for @mailUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No unread mail} =1{1 unread} other{{count} unread}}'**
  String mailUnreadCount(int count);

  /// No description provided for @mailEmptyInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox zero. Nothing waiting on you.'**
  String get mailEmptyInbox;

  /// No description provided for @mailEmptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Nothing in {folder}.'**
  String mailEmptyFolder(String folder);

  /// No description provided for @mailLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get mailLoadMore;

  /// No description provided for @mailFieldTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get mailFieldTo;

  /// No description provided for @mailFieldFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get mailFieldFrom;

  /// No description provided for @mailFieldCc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get mailFieldCc;

  /// No description provided for @mailFieldBcc.
  ///
  /// In en, this message translates to:
  /// **'Bcc'**
  String get mailFieldBcc;

  /// No description provided for @mailFieldSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get mailFieldSubject;

  /// No description provided for @mailToPrefix.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String mailToPrefix(String name);

  /// No description provided for @mailNoSubject.
  ///
  /// In en, this message translates to:
  /// **'(no subject)'**
  String get mailNoSubject;

  /// No description provided for @mailSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Your domain mailbox'**
  String get mailSetupTitle;

  /// No description provided for @mailSetupIntro.
  ///
  /// In en, this message translates to:
  /// **'Read, reply to and send mail on your own domains. Edgepost deploys a small mail service into your Cloudflare account: incoming mail is stored in your account\'s D1 and R2, and you send through Cloudflare Email Sending. Nothing passes through anyone else\'s server.'**
  String get mailSetupIntro;

  /// No description provided for @mailSetupStart.
  ///
  /// In en, this message translates to:
  /// **'Set up mailbox'**
  String get mailSetupStart;

  /// No description provided for @mailSetupRequirements.
  ///
  /// In en, this message translates to:
  /// **'What it needs'**
  String get mailSetupRequirements;

  /// No description provided for @mailSetupReqToken.
  ///
  /// In en, this message translates to:
  /// **'A token with Workers Scripts, D1, Workers R2 Storage and Email Routing permissions'**
  String get mailSetupReqToken;

  /// No description provided for @mailSetupReqR2.
  ///
  /// In en, this message translates to:
  /// **'R2 turned on for the account (once, in the Cloudflare dashboard)'**
  String get mailSetupReqR2;

  /// No description provided for @mailSetupReqPaid.
  ///
  /// In en, this message translates to:
  /// **'To send to any address: the Workers Paid plan. Email Sending is in public beta. Receiving works on every plan.'**
  String get mailSetupReqPaid;

  /// No description provided for @mailSetupDomains.
  ///
  /// In en, this message translates to:
  /// **'Domains'**
  String get mailSetupDomains;

  /// No description provided for @mailSetupDomainsHelp.
  ///
  /// In en, this message translates to:
  /// **'Mail to these domains lands in Edgepost.'**
  String get mailSetupDomainsHelp;

  /// No description provided for @mailSetupRouting.
  ///
  /// In en, this message translates to:
  /// **'Which addresses'**
  String get mailSetupRouting;

  /// No description provided for @mailSetupCatchAll.
  ///
  /// In en, this message translates to:
  /// **'Every address (catch-all)'**
  String get mailSetupCatchAll;

  /// No description provided for @mailSetupSpecific.
  ///
  /// In en, this message translates to:
  /// **'Only these addresses'**
  String get mailSetupSpecific;

  /// No description provided for @mailSetupAddressesHelp.
  ///
  /// In en, this message translates to:
  /// **'Local parts, separated by commas, e.g. contact, billing'**
  String get mailSetupAddressesHelp;

  /// No description provided for @mailSetupSending.
  ///
  /// In en, this message translates to:
  /// **'Enable sending'**
  String get mailSetupSending;

  /// No description provided for @mailSetupSendingHelp.
  ///
  /// In en, this message translates to:
  /// **'Onboards each domain to Cloudflare Email Sending and adds its DNS records (cf-bounce MX, SPF and DKIM).'**
  String get mailSetupSendingHelp;

  /// No description provided for @mailSetupRun.
  ///
  /// In en, this message translates to:
  /// **'Deploy and connect'**
  String get mailSetupRun;

  /// No description provided for @mailSetupRunning.
  ///
  /// In en, this message translates to:
  /// **'Setting up…'**
  String get mailSetupRunning;

  /// No description provided for @mailSetupDone.
  ///
  /// In en, this message translates to:
  /// **'Your mailbox is ready'**
  String get mailSetupDone;

  /// No description provided for @mailSetupDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Send yourself a message at one of your addresses to see it arrive.'**
  String get mailSetupDoneBody;

  /// No description provided for @mailSetupOpenInbox.
  ///
  /// In en, this message translates to:
  /// **'Open inbox'**
  String get mailSetupOpenInbox;

  /// No description provided for @mailSetupRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry from this step'**
  String get mailSetupRetry;

  /// No description provided for @mailStepPermissions.
  ///
  /// In en, this message translates to:
  /// **'Check token permissions'**
  String get mailStepPermissions;

  /// No description provided for @mailStepD1.
  ///
  /// In en, this message translates to:
  /// **'Create D1 database'**
  String get mailStepD1;

  /// No description provided for @mailStepR2.
  ///
  /// In en, this message translates to:
  /// **'Create R2 bucket'**
  String get mailStepR2;

  /// No description provided for @mailStepUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload mail Worker'**
  String get mailStepUpload;

  /// No description provided for @mailStepPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish on workers.dev'**
  String get mailStepPublish;

  /// No description provided for @mailStepSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule trash clean-up'**
  String get mailStepSchedule;

  /// No description provided for @mailStepConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect to the mail service'**
  String get mailStepConnect;

  /// No description provided for @mailStepRoute.
  ///
  /// In en, this message translates to:
  /// **'Route mail for {domain}'**
  String mailStepRoute(String domain);

  /// No description provided for @mailStepSending.
  ///
  /// In en, this message translates to:
  /// **'Enable sending for {domain}'**
  String mailStepSending(String domain);

  /// No description provided for @mailStepSave.
  ///
  /// In en, this message translates to:
  /// **'Save on this device'**
  String get mailStepSave;

  /// No description provided for @mailErrNoSubdomain.
  ///
  /// In en, this message translates to:
  /// **'This account has no workers.dev subdomain yet. In the Cloudflare dashboard open Workers & Pages once to choose one, then retry.'**
  String get mailErrNoSubdomain;

  /// No description provided for @mailErrR2Disabled.
  ///
  /// In en, this message translates to:
  /// **'R2 isn\'t turned on for this account. Open R2 in the Cloudflare dashboard and enable it (the free tier is enough), then retry.'**
  String get mailErrR2Disabled;

  /// No description provided for @mailErrHealth.
  ///
  /// In en, this message translates to:
  /// **'The Worker was uploaded but isn\'t answering yet. New workers.dev addresses can take a minute. Retry shortly.'**
  String get mailErrHealth;

  /// No description provided for @mailServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Mail service'**
  String get mailServiceTitle;

  /// No description provided for @mailServiceVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String mailServiceVersion(String version);

  /// No description provided for @mailServiceUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update mail service'**
  String get mailServiceUpdate;

  /// No description provided for @mailServiceUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'An update is available ({version}).'**
  String mailServiceUpdateAvailable(String version);

  /// No description provided for @mailServiceAddDomains.
  ///
  /// In en, this message translates to:
  /// **'Add domains'**
  String get mailServiceAddDomains;

  /// No description provided for @mailServiceForget.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from this device'**
  String get mailServiceForget;

  /// No description provided for @mailServiceForgetBody.
  ///
  /// In en, this message translates to:
  /// **'Edgepost forgets this mail service on this device. The Worker and your stored mail stay in your Cloudflare account.'**
  String get mailServiceForgetBody;

  /// No description provided for @mailServiceUrl.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get mailServiceUrl;

  /// No description provided for @mailServiceDomains.
  ///
  /// In en, this message translates to:
  /// **'Domains'**
  String get mailServiceDomains;

  /// No description provided for @mailSetupNoService.
  ///
  /// In en, this message translates to:
  /// **'No mailbox yet'**
  String get mailSetupNoService;

  /// No description provided for @mailSetupNoServiceBody.
  ///
  /// In en, this message translates to:
  /// **'Deploy your mail service once and every domain you pick gets a real inbox you can answer from.'**
  String get mailSetupNoServiceBody;

  /// No description provided for @mailRemoteImagesBlocked.
  ///
  /// In en, this message translates to:
  /// **'Remote images are blocked to stop tracking.'**
  String get mailRemoteImagesBlocked;

  /// No description provided for @mailLoadImages.
  ///
  /// In en, this message translates to:
  /// **'Load images'**
  String get mailLoadImages;

  /// No description provided for @mailOpenLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Open link?'**
  String get mailOpenLinkTitle;

  /// No description provided for @mailOpenLinkBody.
  ///
  /// In en, this message translates to:
  /// **'This link goes to:\n{url}'**
  String mailOpenLinkBody(String url);

  /// No description provided for @mailAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment} other{{count} attachments}}'**
  String mailAttachments(int count);

  /// No description provided for @mailShowQuoted.
  ///
  /// In en, this message translates to:
  /// **'Show quoted text'**
  String get mailShowQuoted;

  /// No description provided for @mailIncludeQuote.
  ///
  /// In en, this message translates to:
  /// **'Include original message'**
  String get mailIncludeQuote;

  /// No description provided for @mailIncludeAttachments.
  ///
  /// In en, this message translates to:
  /// **'Include original attachments'**
  String get mailIncludeAttachments;

  /// No description provided for @mailAddAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attach files'**
  String get mailAddAttachment;

  /// No description provided for @mailRecipientsRequired.
  ///
  /// In en, this message translates to:
  /// **'Add at least one recipient.'**
  String get mailRecipientsRequired;

  /// No description provided for @mailInvalidAddress.
  ///
  /// In en, this message translates to:
  /// **'“{value}” isn\'t a valid email address.'**
  String mailInvalidAddress(String value);

  /// No description provided for @mailSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get mailSent;

  /// No description provided for @mailSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get mailSending;

  /// No description provided for @mailDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this message?'**
  String get mailDiscardTitle;

  /// No description provided for @mailDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get mailDiscard;

  /// No description provided for @mailSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get mailSaveDraft;

  /// No description provided for @mailDraftRestored.
  ///
  /// In en, this message translates to:
  /// **'Draft restored'**
  String get mailDraftRestored;

  /// No description provided for @mailBodyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Write your message'**
  String get mailBodyPlaceholder;

  /// No description provided for @mailRecipientsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'name@example.com'**
  String get mailRecipientsPlaceholder;

  /// No description provided for @mailErrRecipientNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare refused this recipient. Sending to outside addresses needs the Workers Paid plan and the sending domain onboarded to Email Sending.'**
  String get mailErrRecipientNotAllowed;

  /// No description provided for @mailErrSenderDomain.
  ///
  /// In en, this message translates to:
  /// **'{domain} isn\'t onboarded to Email Sending yet. Run “Enable sending” in Mail service settings.'**
  String mailErrSenderDomain(String domain);

  /// No description provided for @mailErrSenderNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'You can only send from domains connected to your mail service.'**
  String get mailErrSenderNotAllowed;

  /// No description provided for @mailErrSuppressed.
  ///
  /// In en, this message translates to:
  /// **'This recipient is on Cloudflare\'s suppression list after earlier bounces or complaints.'**
  String get mailErrSuppressed;

  /// No description provided for @mailErrSendingLimit.
  ///
  /// In en, this message translates to:
  /// **'Sending limit reached. Cloudflare raises it gradually; try again later.'**
  String get mailErrSendingLimit;

  /// No description provided for @mailErrTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The message is too large to send (5 MB limit including attachments).'**
  String get mailErrTooLarge;

  /// No description provided for @mailErrDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare couldn\'t deliver the message. Try again in a moment.'**
  String get mailErrDelivery;

  /// No description provided for @mailErrInvalid.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare rejected the message format: {detail}'**
  String mailErrInvalid(String detail);

  /// No description provided for @mailNotifNewMany.
  ///
  /// In en, this message translates to:
  /// **'{count} new messages'**
  String mailNotifNewMany(int count);

  /// No description provided for @mailNotifChannel.
  ///
  /// In en, this message translates to:
  /// **'New mail'**
  String get mailNotifChannel;

  /// No description provided for @mailNotifChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'A new message arrived at one of your domain addresses.'**
  String get mailNotifChannelDescription;

  /// No description provided for @mailIdentityName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get mailIdentityName;

  /// No description provided for @mailSearchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search mail'**
  String get mailSearchPlaceholder;

  /// No description provided for @mailThreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}}'**
  String mailThreadCount(int count);

  /// No description provided for @mailAttachmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the attachment: {error}'**
  String mailAttachmentFailed(String error);

  /// No description provided for @mailYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get mailYesterday;

  /// No description provided for @mailUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get mailUnread;

  /// No description provided for @mailStarred.
  ///
  /// In en, this message translates to:
  /// **'Starred'**
  String get mailStarred;

  /// No description provided for @mailBudgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Sending budget'**
  String get mailBudgetTitle;

  /// No description provided for @mailBudgetExplain.
  ///
  /// In en, this message translates to:
  /// **'Workers Paid includes 3,000 sent emails a month. Beyond that Cloudflare charges \$0.35 per 1,000 and has no spending cap, so your mail service stops at the limit you set here. It counts every recipient over the last 31 days. Receiving is always free.'**
  String get mailBudgetExplain;

  /// No description provided for @mailBudgetLimit.
  ///
  /// In en, this message translates to:
  /// **'Monthly sending limit'**
  String get mailBudgetLimit;

  /// No description provided for @mailBudgetOff.
  ///
  /// In en, this message translates to:
  /// **'Off (receive only)'**
  String get mailBudgetOff;

  /// No description provided for @mailBudgetValue.
  ///
  /// In en, this message translates to:
  /// **'{count} recipients'**
  String mailBudgetValue(String count);

  /// No description provided for @mailBudgetIncluded.
  ///
  /// In en, this message translates to:
  /// **'{count} recipients (included in Workers Paid)'**
  String mailBudgetIncluded(String count);

  /// No description provided for @mailBudgetUsage.
  ///
  /// In en, this message translates to:
  /// **'Sent in the last 31 days: {used} of {limit}'**
  String mailBudgetUsage(String used, String limit);

  /// No description provided for @mailBudgetResets.
  ///
  /// In en, this message translates to:
  /// **'Room frees up from {date}.'**
  String mailBudgetResets(String date);

  /// No description provided for @mailBudgetSaved.
  ///
  /// In en, this message translates to:
  /// **'Sending limit updated'**
  String get mailBudgetSaved;

  /// No description provided for @mailErrMonthlyLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached your sending limit for the last 31 days. Raise it in Settings → Mail service, or wait for older sends to drop out of the window.'**
  String get mailErrMonthlyLimit;

  /// No description provided for @mailSetupBlockedDenied.
  ///
  /// In en, this message translates to:
  /// **'The token is missing a permission mail needs. Add it in the Cloudflare dashboard (My Profile → API Tokens → Edit), then check again.'**
  String get mailSetupBlockedDenied;

  /// No description provided for @mailSetupBlockedR2.
  ///
  /// In en, this message translates to:
  /// **'Turn on R2 for this account first (one-time, free tier included), then check again.'**
  String get mailSetupBlockedR2;

  /// No description provided for @mailSendingPending.
  ///
  /// In en, this message translates to:
  /// **'Sending is set up. Cloudflare is still publishing these records: {records}. This usually takes 5–15 minutes. If they don\'t appear, open the domain under Compute → Email Service → Email Sending in the dashboard.'**
  String mailSendingPending(String records);

  /// No description provided for @mailCloudflareSaid.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare said: {message}'**
  String mailCloudflareSaid(String message);

  /// No description provided for @mailDnsCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Mail DNS check'**
  String get mailDnsCheckTitle;

  /// No description provided for @mailDnsCheckHelp.
  ///
  /// In en, this message translates to:
  /// **'Each domain must have exactly one DMARC record and one SPF record per name. Extra copies make receivers ignore them.'**
  String get mailDnsCheckHelp;

  /// No description provided for @mailDnsCheckClean.
  ///
  /// In en, this message translates to:
  /// **'No duplicate DMARC or SPF records.'**
  String get mailDnsCheckClean;

  /// No description provided for @mailDnsCheckRunning.
  ///
  /// In en, this message translates to:
  /// **'Checking DNS…'**
  String get mailDnsCheckRunning;

  /// No description provided for @mailDnsDupDmarc.
  ///
  /// In en, this message translates to:
  /// **'{count} DMARC records at _dmarc: keep one, delete the others.'**
  String mailDnsDupDmarc(int count);

  /// No description provided for @mailDnsDupSpf.
  ///
  /// In en, this message translates to:
  /// **'{count} SPF records at {name}: keep one, delete the others.'**
  String mailDnsDupSpf(int count, String name);

  /// No description provided for @mailDnsAddedOn.
  ///
  /// In en, this message translates to:
  /// **'added {date}'**
  String mailDnsAddedOn(String date);

  /// No description provided for @mailHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'Sending health'**
  String get mailHealthTitle;

  /// No description provided for @mailHealthIntro.
  ///
  /// In en, this message translates to:
  /// **'What happened to each email you sent in the last {days} days. Cloudflare\'s targets: deliver above 95%, hard bounces under 2%.'**
  String mailHealthIntro(int days);

  /// No description provided for @mailHealthDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get mailHealthDelivered;

  /// No description provided for @mailHealthFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get mailHealthFailed;

  /// No description provided for @mailHealthRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get mailHealthRate;

  /// No description provided for @mailHealthNoSends.
  ///
  /// In en, this message translates to:
  /// **'Nothing sent from this domain in the last {days} days.'**
  String mailHealthNoSends(int days);

  /// No description provided for @mailHealthLowRate.
  ///
  /// In en, this message translates to:
  /// **'Delivery is below Cloudflare\'s 95% target. Fix the causes below before sending more.'**
  String get mailHealthLowRate;

  /// No description provided for @mailHealthAllGood.
  ///
  /// In en, this message translates to:
  /// **'Every recent send was delivered.'**
  String get mailHealthAllGood;

  /// No description provided for @mailHealthAuth.
  ///
  /// In en, this message translates to:
  /// **'SPF {spf} · DKIM {dkim} · DMARC {dmarc}'**
  String mailHealthAuth(String spf, String dkim, String dmarc);

  /// No description provided for @mailHealthHintAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed: receivers reject mail that fails SPF, DKIM or DMARC. Run the Mail DNS check, make sure each name has only one SPF and one DMARC record, and wait until the sending records are published.'**
  String get mailHealthHintAuth;

  /// No description provided for @mailHealthHintUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'The address doesn\'t exist. Check it for typos; Cloudflare stops sending to it for a while.'**
  String get mailHealthHintUnknownUser;

  /// No description provided for @mailHealthHintSpam.
  ///
  /// In en, this message translates to:
  /// **'The receiver flagged this message as spam.'**
  String get mailHealthHintSpam;

  /// No description provided for @mailHealthHintOther.
  ///
  /// In en, this message translates to:
  /// **'Not delivered. The receiving server\'s reason is below.'**
  String get mailHealthHintOther;

  /// No description provided for @mailHealthPause.
  ///
  /// In en, this message translates to:
  /// **'Pause sending'**
  String get mailHealthPause;

  /// No description provided for @mailHealthPauseBody.
  ///
  /// In en, this message translates to:
  /// **'Sets your sending limit to Off, so nothing more is sent until you raise it again in Mail service. Receiving keeps working.'**
  String get mailHealthPauseBody;

  /// No description provided for @mailHealthPaused.
  ///
  /// In en, this message translates to:
  /// **'Sending paused'**
  String get mailHealthPaused;

  /// No description provided for @mailHealthOpen.
  ///
  /// In en, this message translates to:
  /// **'Sending health'**
  String get mailHealthOpen;

  /// No description provided for @mailHealthOpenHelp.
  ///
  /// In en, this message translates to:
  /// **'Delivery rate, bounces and why each failed send failed.'**
  String get mailHealthOpenHelp;

  /// No description provided for @mailFromTitle.
  ///
  /// In en, this message translates to:
  /// **'Send from'**
  String get mailFromTitle;

  /// No description provided for @mailFromSearch.
  ///
  /// In en, this message translates to:
  /// **'Search addresses'**
  String get mailFromSearch;

  /// No description provided for @mailFromRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get mailFromRecent;

  /// No description provided for @mailFromOtherTitle.
  ///
  /// In en, this message translates to:
  /// **'Another address'**
  String get mailFromOtherTitle;

  /// No description provided for @mailFromOtherHelp.
  ///
  /// In en, this message translates to:
  /// **'Any address on your domains works. Replies to it land in Edgepost.'**
  String get mailFromOtherHelp;

  /// No description provided for @mailFromLocalHint.
  ///
  /// In en, this message translates to:
  /// **'name'**
  String get mailFromLocalHint;

  /// No description provided for @mailFromUse.
  ///
  /// In en, this message translates to:
  /// **'Use this address'**
  String get mailFromUse;

  /// No description provided for @mailFromInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers, dots, dashes or underscores.'**
  String get mailFromInvalid;

  /// No description provided for @mailFromNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Name and signature'**
  String get mailFromNameTitle;

  /// No description provided for @mailFromNameHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown to recipients for {address}.'**
  String mailFromNameHelp(String address);

  /// No description provided for @mailFromNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No address matches “{query}”.'**
  String mailFromNoMatch(String query);

  /// No description provided for @mailAttachPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo or video'**
  String get mailAttachPhoto;

  /// No description provided for @mailAttachFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get mailAttachFile;

  /// No description provided for @mailAttachTooBig.
  ///
  /// In en, this message translates to:
  /// **'{name} is too big: {size} won\'t fit. {room} left in this message.'**
  String mailAttachTooBig(String name, String size, String room);

  /// No description provided for @mailAttachFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the file: {error}'**
  String mailAttachFailed(String error);

  /// No description provided for @mailSizeAsSent.
  ///
  /// In en, this message translates to:
  /// **'{used} of 5 MB as sent'**
  String mailSizeAsSent(String used);

  /// No description provided for @mailSizeOver.
  ///
  /// In en, this message translates to:
  /// **'Over Cloudflare\'s 5 MB limit (attachments grow about a third when encoded). Remove an attachment.'**
  String get mailSizeOver;

  /// No description provided for @mailSendFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send'**
  String get mailSendFailedTitle;

  /// No description provided for @mailErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Details: {details}'**
  String mailErrorDetails(String details);

  /// No description provided for @mailErrOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. The message is kept as a draft.'**
  String get mailErrOffline;

  /// No description provided for @mailErrTimeout.
  ///
  /// In en, this message translates to:
  /// **'Your mail service is taking too long. If the message went out it won\'t be sent twice: try again.'**
  String get mailErrTimeout;

  /// No description provided for @mailErrUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your mail service is temporarily unavailable (Cloudflare {status}). Try again in a moment.'**
  String mailErrUnavailable(int status);

  /// No description provided for @mailToAddress.
  ///
  /// In en, this message translates to:
  /// **'to {address}'**
  String mailToAddress(String address);

  /// No description provided for @mailFromAddress.
  ///
  /// In en, this message translates to:
  /// **'from {address}'**
  String mailFromAddress(String address);

  /// No description provided for @mailHasAttachment.
  ///
  /// In en, this message translates to:
  /// **'Has attachments'**
  String get mailHasAttachment;

  /// No description provided for @mailAddCcBcc.
  ///
  /// In en, this message translates to:
  /// **'Add Cc or Bcc'**
  String get mailAddCcBcc;

  /// No description provided for @mailSendsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Sending limit reached: this message won\'t go out until older sends leave the 31-day window.} =1{1 send left before your sending limit.} other{{count} sends left before your sending limit.}}'**
  String mailSendsLeft(int count);

  /// No description provided for @mailFromEditFor.
  ///
  /// In en, this message translates to:
  /// **'Name and signature for {address}'**
  String mailFromEditFor(String address);

  /// No description provided for @mailChooseInbox.
  ///
  /// In en, this message translates to:
  /// **'Showing {scope}. Choose inbox'**
  String mailChooseInbox(String scope);

  /// No description provided for @mailHealthEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sending domains yet'**
  String get mailHealthEmpty;

  /// No description provided for @mailHealthEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Once you send from one of your domains, delivered, bounced and failed messages show up here.'**
  String get mailHealthEmptyBody;

  /// No description provided for @mailYouTo.
  ///
  /// In en, this message translates to:
  /// **'You → {name}'**
  String mailYouTo(String name);

  /// No description provided for @mailSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get mailSignature;

  /// No description provided for @mailSignaturePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Add a signature to this message'**
  String get mailSignaturePlaceholder;

  /// No description provided for @mailSignatureReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get mailSignatureReset;

  /// No description provided for @mailSignatureThisMessage.
  ///
  /// In en, this message translates to:
  /// **'Changes here are for this message only.'**
  String get mailSignatureThisMessage;

  /// No description provided for @mailSignatureEditedHere.
  ///
  /// In en, this message translates to:
  /// **'Changed for this message only.'**
  String get mailSignatureEditedHere;

  /// No description provided for @mailSignatureLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get mailSignatureLogo;

  /// No description provided for @mailSignatureLogoLabel.
  ///
  /// In en, this message translates to:
  /// **'The {domain} logo'**
  String mailSignatureLogoLabel(String domain);

  /// No description provided for @mailSignatureEditDefault.
  ///
  /// In en, this message translates to:
  /// **'Edit the default for {domain}'**
  String mailSignatureEditDefault(String domain);

  /// No description provided for @mailBrandTitle.
  ///
  /// In en, this message translates to:
  /// **'Signature & logo'**
  String get mailBrandTitle;

  /// No description provided for @mailBrandLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get mailBrandLogo;

  /// No description provided for @mailBrandLogoHelp.
  ///
  /// In en, this message translates to:
  /// **'Shown above your signature in mail you send. Any photo or image works; it\'s resized to fit 240 × 48.'**
  String get mailBrandLogoHelp;

  /// No description provided for @mailBrandChooseLogo.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get mailBrandChooseLogo;

  /// No description provided for @mailBrandReplaceLogo.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get mailBrandReplaceLogo;

  /// No description provided for @mailBrandRemoveLogo.
  ///
  /// In en, this message translates to:
  /// **'Remove logo'**
  String get mailBrandRemoveLogo;

  /// No description provided for @mailBrandSignaturePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your name, role, phone, website…'**
  String get mailBrandSignaturePlaceholder;

  /// No description provided for @mailBrandSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get mailBrandSignature;

  /// No description provided for @mailBrandSignatureHelp.
  ///
  /// In en, this message translates to:
  /// **'Added to mail you send from {domain}, on every device. Links and email addresses become clickable. You can still change it for a single message.'**
  String mailBrandSignatureHelp(String domain);

  /// No description provided for @mailBrandPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get mailBrandPreview;

  /// No description provided for @mailBrandSample.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your message, I\'ll get back to you today.'**
  String get mailBrandSample;

  /// No description provided for @mailBrandSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved for {domain}'**
  String mailBrandSaved(String domain);

  /// No description provided for @mailBrandLogoUnreadable.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t an image Edgepost can read. Try a PNG or JPEG.'**
  String get mailBrandLogoUnreadable;

  /// No description provided for @mailBrandSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'Add a signature or logo'**
  String get mailBrandSummaryNone;

  /// No description provided for @mailBrandSummarySignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get mailBrandSummarySignature;

  /// No description provided for @mailBrandSummaryLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get mailBrandSummaryLogo;

  /// No description provided for @mailBrandSummaryBoth.
  ///
  /// In en, this message translates to:
  /// **'Signature and logo'**
  String get mailBrandSummaryBoth;

  /// No description provided for @mailSplitPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Choose a message to read it here.'**
  String get mailSplitPlaceholder;

  /// No description provided for @mailSuggestedRecipients.
  ///
  /// In en, this message translates to:
  /// **'People you\'ve written to'**
  String get mailSuggestedRecipients;

  /// No description provided for @mailSuggestAdd.
  ///
  /// In en, this message translates to:
  /// **'Add {recipient}'**
  String mailSuggestAdd(String recipient);

  /// No description provided for @mailSuggestTypo.
  ///
  /// In en, this message translates to:
  /// **'Did you mean this? You typed {domain}'**
  String mailSuggestTypo(String domain);

  /// No description provided for @mailErrServiceMissing.
  ///
  /// In en, this message translates to:
  /// **'Your mail service is no longer in your Cloudflare account.'**
  String get mailErrServiceMissing;

  /// No description provided for @mailServiceMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Your mail service is gone'**
  String get mailServiceMissingTitle;

  /// No description provided for @mailServiceMissingBody.
  ///
  /// In en, this message translates to:
  /// **'The edgepost-mail Worker isn\'t in your Cloudflare account any more. Set it up again to receive and send mail here. Mail it kept is gone if its database and bucket were deleted too.'**
  String get mailServiceMissingBody;

  /// No description provided for @mailServiceSetUpAgain.
  ///
  /// In en, this message translates to:
  /// **'Set up again'**
  String get mailServiceSetUpAgain;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your domains, handled.'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Edgepost brings your Cloudflare® domains into one place: DNS, SSL and cache, traffic, Workers and Pages, and a real mailbox on each domain that you can read, reply to and send from.'**
  String get welcomeBody;

  /// No description provided for @welcomePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your token stays in this device\'s secure storage. Edgepost talks only to Cloudflare and to a mail service that runs in your own Cloudflare account. No Edgepost server, no tracking.'**
  String get welcomePrivacy;

  /// No description provided for @welcomeAddToken.
  ///
  /// In en, this message translates to:
  /// **'Add a Cloudflare API token'**
  String get welcomeAddToken;

  /// No description provided for @welcomeHowTo.
  ///
  /// In en, this message translates to:
  /// **'How to create a token'**
  String get welcomeHowTo;

  /// No description provided for @welcomeNotAffiliated.
  ///
  /// In en, this message translates to:
  /// **'Edgepost is an independent app. It isn\'t made, endorsed or supported by Cloudflare, Inc., and isn\'t affiliated with it.'**
  String get welcomeNotAffiliated;

  /// No description provided for @addTokenTitle.
  ///
  /// In en, this message translates to:
  /// **'Add API token'**
  String get addTokenTitle;

  /// No description provided for @addTokenLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get addTokenLabel;

  /// No description provided for @addTokenLabelPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'e.g. Personal account'**
  String get addTokenLabelPlaceholder;

  /// No description provided for @addTokenField.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get addTokenField;

  /// No description provided for @addTokenFieldHelp.
  ///
  /// In en, this message translates to:
  /// **'Create it under My Profile → API Tokens in the Cloudflare dashboard. Paste it here; it\'s stored only on this device.'**
  String get addTokenFieldHelp;

  /// No description provided for @addTokenPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get addTokenPaste;

  /// No description provided for @addTokenVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify and add'**
  String get addTokenVerify;

  /// No description provided for @addTokenVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the token and what it can reach…'**
  String get addTokenVerifying;

  /// No description provided for @addTokenEmpty.
  ///
  /// In en, this message translates to:
  /// **'Paste a token first.'**
  String get addTokenEmpty;

  /// No description provided for @addTokenRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended permissions'**
  String get addTokenRecommended;

  /// No description provided for @addTokenRecommendedHelp.
  ///
  /// In en, this message translates to:
  /// **'Grant only what you\'ll use. Each feature tells you if a permission is missing.'**
  String get addTokenRecommendedHelp;

  /// No description provided for @addTokenAddedTitle.
  ///
  /// In en, this message translates to:
  /// **'Token added'**
  String get addTokenAddedTitle;

  /// No description provided for @addTokenWriteNote.
  ///
  /// In en, this message translates to:
  /// **'Edit rights are confirmed the first time you change something.'**
  String get addTokenWriteNote;

  /// No description provided for @capabilityAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get capabilityAvailable;

  /// No description provided for @capabilityMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get capabilityMissing;

  /// No description provided for @capZones.
  ///
  /// In en, this message translates to:
  /// **'See domains'**
  String get capZones;

  /// No description provided for @capDns.
  ///
  /// In en, this message translates to:
  /// **'DNS records'**
  String get capDns;

  /// No description provided for @capZoneSettings.
  ///
  /// In en, this message translates to:
  /// **'SSL, cache and security settings'**
  String get capZoneSettings;

  /// No description provided for @capCachePurge.
  ///
  /// In en, this message translates to:
  /// **'Purge cache'**
  String get capCachePurge;

  /// No description provided for @capAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Traffic analytics'**
  String get capAnalytics;

  /// No description provided for @capEmailRouting.
  ///
  /// In en, this message translates to:
  /// **'Email routing rules'**
  String get capEmailRouting;

  /// No description provided for @capEmailAddresses.
  ///
  /// In en, this message translates to:
  /// **'Forwarding addresses'**
  String get capEmailAddresses;

  /// No description provided for @capDmarc.
  ///
  /// In en, this message translates to:
  /// **'DMARC reports'**
  String get capDmarc;

  /// No description provided for @capWorkers.
  ///
  /// In en, this message translates to:
  /// **'Workers'**
  String get capWorkers;

  /// No description provided for @capWorkerRoutes.
  ///
  /// In en, this message translates to:
  /// **'Worker routes'**
  String get capWorkerRoutes;

  /// No description provided for @capPages.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get capPages;

  /// No description provided for @capD1.
  ///
  /// In en, this message translates to:
  /// **'D1 (mailbox storage)'**
  String get capD1;

  /// No description provided for @capR2.
  ///
  /// In en, this message translates to:
  /// **'R2 (mail attachments)'**
  String get capR2;

  /// No description provided for @capRegistrar.
  ///
  /// In en, this message translates to:
  /// **'Registrar renewals'**
  String get capRegistrar;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Edgepost is locked'**
  String get lockTitle;

  /// No description provided for @lockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlock;

  /// No description provided for @lockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock to see your domains and mail'**
  String get lockReason;

  /// No description provided for @capabilityNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Turn on in the dashboard'**
  String get capabilityNotEnabled;

  /// No description provided for @capabilityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not confirmed yet: checked again when you use it'**
  String get capabilityUnknown;

  /// No description provided for @capR2NotEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'R2 needs a one-time subscription (free tier included). In the Cloudflare dashboard open Storage & databases → R2 → Overview and complete the checkout.'**
  String get capR2NotEnabledHint;

  /// No description provided for @capDeniedHint.
  ///
  /// In en, this message translates to:
  /// **'Add this permission to the token in the Cloudflare dashboard: {permission}'**
  String capDeniedHint(String permission);

  /// No description provided for @capOpenDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open the Cloudflare dashboard'**
  String get capOpenDashboard;

  /// No description provided for @capCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check permissions again'**
  String get capCheckAgain;

  /// No description provided for @capChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking permissions…'**
  String get capChecking;

  /// No description provided for @capBilling.
  ///
  /// In en, this message translates to:
  /// **'Budget and usage cost'**
  String get capBilling;

  /// No description provided for @addAccountAvailable.
  ///
  /// In en, this message translates to:
  /// **'Reachable with your tokens'**
  String get addAccountAvailable;

  /// No description provided for @addAccountAvailableHelp.
  ///
  /// In en, this message translates to:
  /// **'Accounts your API tokens already reach. Adding one needs no new token.'**
  String get addAccountAvailableHelp;

  /// No description provided for @addAccountNewToken.
  ///
  /// In en, this message translates to:
  /// **'With a new API token'**
  String get addAccountNewToken;

  /// No description provided for @addAccountChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose accounts'**
  String get addAccountChoose;

  /// No description provided for @addAccountChooseHelp.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This token reaches 1 account.} other{This token reaches {count} accounts. Pick the ones to show in Edgepost; you can add the others later.}}'**
  String addAccountChooseHelp(int count);

  /// No description provided for @addAccountAlready.
  ///
  /// In en, this message translates to:
  /// **'Already added'**
  String get addAccountAlready;

  /// No description provided for @addAccountAllAdded.
  ///
  /// In en, this message translates to:
  /// **'Every account this token reaches is already in Edgepost. Keep it as another key for them (for example while you replace an expiring token).'**
  String get addAccountAllAdded;

  /// No description provided for @addAccountKeepToken.
  ///
  /// In en, this message translates to:
  /// **'Keep token'**
  String get addAccountKeepToken;

  /// No description provided for @addAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Choose an account} =1{Add 1 account} other{Add {count} accounts}}'**
  String addAccountConfirm(int count);

  /// No description provided for @addAccountChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking what the token can do: {done} of {total}'**
  String addAccountChecking(int done, int total);

  /// No description provided for @settingsTokens.
  ///
  /// In en, this message translates to:
  /// **'API tokens'**
  String get settingsTokens;

  /// No description provided for @settingsTokenKindUser.
  ///
  /// In en, this message translates to:
  /// **'User token'**
  String get settingsTokenKindUser;

  /// No description provided for @settingsTokenKindAccount.
  ///
  /// In en, this message translates to:
  /// **'Account token'**
  String get settingsTokenKindAccount;

  /// No description provided for @settingsTokenRecheck.
  ///
  /// In en, this message translates to:
  /// **'Check permissions again'**
  String get settingsTokenRecheck;

  /// No description provided for @settingsTokenRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove token'**
  String get settingsTokenRemove;

  /// No description provided for @settingsTokenRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove “{label}”?'**
  String settingsTokenRemoveConfirm(String label);

  /// No description provided for @settingsTokenRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'The token is deleted from this device. It stays valid in Cloudflare until you revoke it there.'**
  String get settingsTokenRemoveBody;

  /// No description provided for @settingsTokenCapabilities.
  ///
  /// In en, this message translates to:
  /// **'What it can do'**
  String get settingsTokenCapabilities;

  /// No description provided for @settingsTokenRechecked.
  ///
  /// In en, this message translates to:
  /// **'Permissions updated'**
  String get settingsTokenRechecked;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAppearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// No description provided for @settingsAppearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// No description provided for @settingsAppearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAppearanceSystem;

  /// No description provided for @settingsAppearanceSystemHelp.
  ///
  /// In en, this message translates to:
  /// **'Follows your device\'s light or dark setting.'**
  String get settingsAppearanceSystemHelp;

  /// No description provided for @settingsAppLock.
  ///
  /// In en, this message translates to:
  /// **'Require Face ID / fingerprint'**
  String get settingsAppLock;

  /// No description provided for @settingsAppLockHelp.
  ///
  /// In en, this message translates to:
  /// **'Locks Edgepost when you leave it for more than a minute and hides its content in the app switcher.'**
  String get settingsAppLockHelp;

  /// No description provided for @settingsAppLockUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Set up a device passcode to use app lock.'**
  String get settingsAppLockUnavailable;

  /// No description provided for @settingsMail.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get settingsMail;

  /// No description provided for @settingsMailService.
  ///
  /// In en, this message translates to:
  /// **'Mail service'**
  String get settingsMailService;

  /// No description provided for @settingsMailNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get settingsMailNotSetUp;

  /// No description provided for @settingsMailReady.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get settingsMailReady;

  /// No description provided for @settingsNewMailAlerts.
  ///
  /// In en, this message translates to:
  /// **'New mail alerts'**
  String get settingsNewMailAlerts;

  /// No description provided for @settingsNewMailAlertsHelp.
  ///
  /// In en, this message translates to:
  /// **'Checks for new mail in the background. The system decides how often, usually every 15 to 60 minutes.'**
  String get settingsNewMailAlertsHelp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get settingsLicenses;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get settingsPrivacy;

  /// No description provided for @settingsSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get settingsSourceCode;

  /// No description provided for @settingsSourceCodeLicense.
  ///
  /// In en, this message translates to:
  /// **'MIT'**
  String get settingsSourceCodeLicense;

  /// No description provided for @settingsContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get settingsContact;

  /// No description provided for @settingsPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Edgepost has no server and collects no data. Your API tokens live in this device\'s secure storage. App traffic goes only to api.cloudflare.com and to the mail Worker in your own Cloudflare account. Cached lists and recent mail are stored on this device so they open instantly.'**
  String get settingsPrivacyBody;

  /// No description provided for @settingsNotAffiliated.
  ///
  /// In en, this message translates to:
  /// **'Edgepost is an independent app. It isn\'t made, endorsed or supported by Cloudflare, Inc., and isn\'t affiliated with it. Cloudflare, Cloudflare Workers and Cloudflare Pages are trademarks and/or registered trademarks of Cloudflare, Inc. in the United States and other jurisdictions.'**
  String get settingsNotAffiliated;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsBudgetAlerts.
  ///
  /// In en, this message translates to:
  /// **'Budget alerts'**
  String get settingsBudgetAlerts;

  /// No description provided for @settingsBudgetAlertsHelp.
  ///
  /// In en, this message translates to:
  /// **'When emails reach 80% and 100% of your sending limit, and the first time usage costs money in a billing period.'**
  String get settingsBudgetAlertsHelp;

  /// No description provided for @settingsDeliveryAlerts.
  ///
  /// In en, this message translates to:
  /// **'Delivery alerts'**
  String get settingsDeliveryAlerts;

  /// No description provided for @settingsDeliveryAlertsHelp.
  ///
  /// In en, this message translates to:
  /// **'When a domain\'s delivery rate drops below Cloudflare\'s 95% target.'**
  String get settingsDeliveryAlertsHelp;

  /// No description provided for @settingsNotificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off for Edgepost. Turn them on in Settings.'**
  String get settingsNotificationsDenied;

  /// No description provided for @settingsTokenExpiresTitle.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get settingsTokenExpiresTitle;

  /// No description provided for @settingsTokenNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settingsTokenNoExpiry;

  /// No description provided for @settingsTokenExpiryHelp.
  ///
  /// In en, this message translates to:
  /// **'Read from Cloudflare each time the app opens, so a date you change in the Cloudflare dashboard shows up here. To replace an expiring token, create or roll it in the dashboard and add the new one.'**
  String get settingsTokenExpiryHelp;

  /// No description provided for @settingsTokenAddReplacement.
  ///
  /// In en, this message translates to:
  /// **'Add the new token'**
  String get settingsTokenAddReplacement;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accountsTitle;

  /// No description provided for @accountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// No description provided for @accountAdd.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get accountAdd;

  /// No description provided for @accountsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts'**
  String get accountsManage;

  /// No description provided for @accountNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No access: add a token for it'**
  String get accountNoAccess;

  /// No description provided for @accountCurrent.
  ///
  /// In en, this message translates to:
  /// **'current account'**
  String get accountCurrent;

  /// No description provided for @accountShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing now'**
  String get accountShowing;

  /// No description provided for @accountSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String accountSwitched(String name);

  /// No description provided for @accountButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Account: {name}'**
  String accountButtonLabel(String name);

  /// No description provided for @accountButtonHint.
  ///
  /// In en, this message translates to:
  /// **'Shows your accounts'**
  String get accountButtonHint;

  /// No description provided for @accountSwitchBack.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String accountSwitchBack(String name);

  /// No description provided for @accountOthersNeedYou.
  ///
  /// In en, this message translates to:
  /// **'Another account needs you'**
  String get accountOthersNeedYou;

  /// No description provided for @accountOthersUnread.
  ///
  /// In en, this message translates to:
  /// **'Another account has unread mail'**
  String get accountOthersUnread;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountName;

  /// No description provided for @accountRename.
  ///
  /// In en, this message translates to:
  /// **'Name this account'**
  String get accountRename;

  /// No description provided for @accountRenameHelp.
  ///
  /// In en, this message translates to:
  /// **'Only on this device. Leave it empty to use Cloudflare\'s name, “{name}”.'**
  String accountRenameHelp(String name);

  /// No description provided for @accountCloudflareName.
  ///
  /// In en, this message translates to:
  /// **'In Cloudflare: {name}'**
  String accountCloudflareName(String name);

  /// No description provided for @accountSwitchTo.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String accountSwitchTo(String name);

  /// No description provided for @accountTokenAlsoReaches.
  ///
  /// In en, this message translates to:
  /// **'This token also gives access to {names}; they\'ll keep working only if another token reaches them.'**
  String accountTokenAlsoReaches(String names);

  /// No description provided for @accountRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from Edgepost'**
  String get accountRemove;

  /// No description provided for @accountRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from Edgepost?'**
  String accountRemoveConfirm(String name);

  /// No description provided for @accountRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing changes in Cloudflare. This device forgets the account: its mail connection, what was kept for it offline, and any token that only reached it.'**
  String get accountRemoveBody;

  /// No description provided for @accountRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed from Edgepost'**
  String accountRemoved(String name);

  /// No description provided for @todayNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get todayNeedsYou;

  /// No description provided for @todayInbound.
  ///
  /// In en, this message translates to:
  /// **'Inbound'**
  String get todayInbound;

  /// No description provided for @todayDeploys.
  ///
  /// In en, this message translates to:
  /// **'Deploys'**
  String get todayDeploys;

  /// No description provided for @todayTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic · 7 days'**
  String get todayTraffic;

  /// No description provided for @todayAllClear.
  ///
  /// In en, this message translates to:
  /// **'Every strip is in line. Nothing needs you right now.'**
  String get todayAllClear;

  /// No description provided for @todaySeeAll.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String todaySeeAll(int count);

  /// No description provided for @todayNoUnread.
  ///
  /// In en, this message translates to:
  /// **'No unread mail.'**
  String get todayNoUnread;

  /// No description provided for @todaySetUpMail.
  ///
  /// In en, this message translates to:
  /// **'Set up your domain mailbox'**
  String get todaySetUpMail;

  /// No description provided for @todayFieldRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get todayFieldRequests;

  /// No description provided for @todayFieldBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get todayFieldBandwidth;

  /// No description provided for @todayFieldCached.
  ///
  /// In en, this message translates to:
  /// **'Cached'**
  String get todayFieldCached;

  /// No description provided for @todayFleetCallsign.
  ///
  /// In en, this message translates to:
  /// **'All domains'**
  String get todayFleetCallsign;

  /// No description provided for @todayFleetCaption.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 domain} other{{count} domains}}'**
  String todayFleetCaption(int count);

  /// No description provided for @todayReasonRegistrar.
  ///
  /// In en, this message translates to:
  /// **'Registration expires in {days, plural, =0{less than a day} =1{1 day} other{{days} days}} and auto-renew is off.'**
  String todayReasonRegistrar(int days);

  /// No description provided for @todayReasonRegistrarExpired.
  ///
  /// In en, this message translates to:
  /// **'Registration has expired. Renew it in the Cloudflare dashboard.'**
  String get todayReasonRegistrarExpired;

  /// No description provided for @todayReasonTokenExpiry.
  ///
  /// In en, this message translates to:
  /// **'This API token expires in {days, plural, =0{less than a day} =1{1 day} other{{days} days}}. Roll it in the Cloudflare dashboard, then add the new one.'**
  String todayReasonTokenExpiry(int days);

  /// No description provided for @todayReasonMailUpdate.
  ///
  /// In en, this message translates to:
  /// **'A newer mail service ({version}) is ready to install.'**
  String todayReasonMailUpdate(String version);

  /// No description provided for @todayFieldExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get todayFieldExpires;

  /// No description provided for @todayFieldToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get todayFieldToken;

  /// No description provided for @todayFieldMail.
  ///
  /// In en, this message translates to:
  /// **'Mail service'**
  String get todayFieldMail;

  /// No description provided for @todayFieldNeedsYou.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get todayFieldNeedsYou;

  /// No description provided for @todayFieldUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get todayFieldUnread;

  /// No description provided for @todayNoAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Add “Zone · Analytics · Read” to a token to see traffic here.'**
  String get todayNoAnalytics;

  /// No description provided for @budgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budgetTitle;

  /// No description provided for @budgetCallsign.
  ///
  /// In en, this message translates to:
  /// **'This period'**
  String get budgetCallsign;

  /// No description provided for @budgetUsageCost.
  ///
  /// In en, this message translates to:
  /// **'Usage cost'**
  String get budgetUsageCost;

  /// No description provided for @budgetDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{ends today} =1{ends tomorrow} other{{count} days left}}'**
  String budgetDaysLeft(int count);

  /// No description provided for @budgetReasonSendCap.
  ///
  /// In en, this message translates to:
  /// **'Emails at {percent} of your sending limit. Sending stops at the limit.'**
  String budgetReasonSendCap(String percent);

  /// No description provided for @budgetReasonCost.
  ///
  /// In en, this message translates to:
  /// **'Usage beyond your plan this period: {amount}. See what\'s billing.'**
  String budgetReasonCost(String amount);

  /// No description provided for @budgetNoBilling.
  ///
  /// In en, this message translates to:
  /// **'Add “Account · Billing · Read” to your token to see usage cost. Emails sent are tracked either way.'**
  String get budgetNoBilling;

  /// No description provided for @budgetUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare\'s usage data isn\'t available right now ({reason}). Emails sent are still tracked.'**
  String budgetUnavailable(String reason);

  /// No description provided for @budgetScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budgetScreenTitle;

  /// No description provided for @budgetPeriod.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String budgetPeriod(String start, String end);

  /// No description provided for @budgetServices.
  ///
  /// In en, this message translates to:
  /// **'Usage this period'**
  String get budgetServices;

  /// No description provided for @budgetServicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usage beyond what your plan includes so far.'**
  String get budgetServicesEmpty;

  /// No description provided for @budgetIncluded.
  ///
  /// In en, this message translates to:
  /// **'Included in Workers Paid'**
  String get budgetIncluded;

  /// No description provided for @budgetIncludedSource.
  ///
  /// In en, this message translates to:
  /// **'From Cloudflare\'s pricing pages. Usage past these amounts is billed.'**
  String get budgetIncludedSource;

  /// No description provided for @budgetIncWorkers.
  ///
  /// In en, this message translates to:
  /// **'Workers: 10 M requests, 30 M CPU ms'**
  String get budgetIncWorkers;

  /// No description provided for @budgetIncD1.
  ///
  /// In en, this message translates to:
  /// **'D1: 25 B rows read, 50 M written, 5 GB'**
  String get budgetIncD1;

  /// No description provided for @budgetIncR2.
  ///
  /// In en, this message translates to:
  /// **'R2: 10 GB, 1 M Class A, 10 M Class B operations'**
  String get budgetIncR2;

  /// No description provided for @budgetIncEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Sending: 3,000 emails'**
  String get budgetIncEmail;

  /// No description provided for @budgetSending.
  ///
  /// In en, this message translates to:
  /// **'Sending limit'**
  String get budgetSending;

  /// No description provided for @budgetOpenBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing in the Cloudflare dashboard'**
  String get budgetOpenBilling;

  /// No description provided for @budgetAlpha.
  ///
  /// In en, this message translates to:
  /// **'Usage cost comes from Cloudflare\'s billable-usage API (Alpha) and may lag by a few hours.'**
  String get budgetAlpha;

  /// No description provided for @alertSend80Title.
  ///
  /// In en, this message translates to:
  /// **'Sending at 80% of your limit'**
  String get alertSend80Title;

  /// No description provided for @alertSend80Body.
  ///
  /// In en, this message translates to:
  /// **'{used} of {limit} emails in the last 31 days. Sending stops at the limit.'**
  String alertSend80Body(String used, String limit);

  /// No description provided for @alertSend100Title.
  ///
  /// In en, this message translates to:
  /// **'Sending limit reached'**
  String get alertSend100Title;

  /// No description provided for @alertSend100Body.
  ///
  /// In en, this message translates to:
  /// **'No more emails go out until older sends leave the 31-day window, or you raise the limit.'**
  String get alertSend100Body;

  /// No description provided for @alertCostTitle.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare usage is costing money'**
  String get alertCostTitle;

  /// No description provided for @alertCostBody.
  ///
  /// In en, this message translates to:
  /// **'{amount} beyond your plan this period. Open Budget to see which service.'**
  String alertCostBody(String amount);

  /// No description provided for @alertDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery problems on {domain}'**
  String alertDeliveryTitle(String domain);

  /// No description provided for @alertDeliveryBody.
  ///
  /// In en, this message translates to:
  /// **'Delivered {rate} of recent emails (target 95%). Open Sending health to see why.'**
  String alertDeliveryBody(String rate);

  /// No description provided for @todayReasonDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivered {rate} of recent emails, below Cloudflare\'s 95% target.'**
  String todayReasonDelivery(String rate);

  /// No description provided for @newMailFrom.
  ///
  /// In en, this message translates to:
  /// **'New mail from {sender}'**
  String newMailFrom(String sender);

  /// No description provided for @newMailOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get newMailOpen;

  /// No description provided for @todayOtherAccounts.
  ///
  /// In en, this message translates to:
  /// **'Other accounts'**
  String get todayOtherAccounts;

  /// No description provided for @newMailInFrom.
  ///
  /// In en, this message translates to:
  /// **'New mail in {account} from {sender}'**
  String newMailInFrom(String account, String sender);

  /// No description provided for @newMailInMany.
  ///
  /// In en, this message translates to:
  /// **'{count} new messages in {account}'**
  String newMailInMany(int count, String account);

  /// No description provided for @alertChannelName.
  ///
  /// In en, this message translates to:
  /// **'Budget and delivery'**
  String get alertChannelName;

  /// No description provided for @notifOfferAction.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get notifOfferAction;

  /// No description provided for @notifOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Get alerts on this device?'**
  String get notifOfferTitle;

  /// No description provided for @notifOfferLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notifOfferLater;

  /// No description provided for @budgetSendsLeft.
  ///
  /// In en, this message translates to:
  /// **'Sends left'**
  String get budgetSendsLeft;

  /// No description provided for @budgetPeriodField.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get budgetPeriodField;

  /// No description provided for @budgetSendingOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get budgetSendingOff;

  /// No description provided for @budgetMeterCaption.
  ///
  /// In en, this message translates to:
  /// **'{sent} of {limit} emails sent in the last 31 days'**
  String budgetMeterCaption(String sent, String limit);

  /// No description provided for @budgetNoBillingShort.
  ///
  /// In en, this message translates to:
  /// **'Usage cost needs “Account · Billing · Read” on your token.'**
  String get budgetNoBillingShort;

  /// No description provided for @budgetUsageUnavailableShort.
  ///
  /// In en, this message translates to:
  /// **'Usage cost isn\'t available right now; emails are still counted.'**
  String get budgetUsageUnavailableShort;

  /// No description provided for @budgetAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Alert me at 80% and 100%'**
  String get budgetAlertsTitle;

  /// No description provided for @budgetAlertsHelp.
  ///
  /// In en, this message translates to:
  /// **'A notification when emails reach 80% and 100% of your sending limit, and the first time usage costs money in a period.'**
  String get budgetAlertsHelp;

  /// No description provided for @budgetSemantic.
  ///
  /// In en, this message translates to:
  /// **'{sent} of {limit} emails sent, {left} left'**
  String budgetSemantic(String sent, String limit, String left);

  /// No description provided for @todayBackInLine.
  ///
  /// In en, this message translates to:
  /// **'Back in line'**
  String get todayBackInLine;

  /// No description provided for @budgetSendingLimit.
  ///
  /// In en, this message translates to:
  /// **'Sending limit'**
  String get budgetSendingLimit;

  /// No description provided for @todayMailServiceCallsign.
  ///
  /// In en, this message translates to:
  /// **'Mail service'**
  String get todayMailServiceCallsign;

  /// No description provided for @controlsTitle.
  ///
  /// In en, this message translates to:
  /// **'SSL, cache & security'**
  String get controlsTitle;

  /// No description provided for @controlsSectionEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get controlsSectionEncryption;

  /// No description provided for @controlsSectionCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get controlsSectionCache;

  /// No description provided for @controlsSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get controlsSectionSecurity;

  /// No description provided for @controlsSectionCloudflare.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare'**
  String get controlsSectionCloudflare;

  /// No description provided for @controlsSectionDnssec.
  ///
  /// In en, this message translates to:
  /// **'DNSSEC'**
  String get controlsSectionDnssec;

  /// No description provided for @controlsSslMode.
  ///
  /// In en, this message translates to:
  /// **'SSL/TLS mode'**
  String get controlsSslMode;

  /// No description provided for @controlsSslOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get controlsSslOff;

  /// No description provided for @controlsSslOffDetail.
  ///
  /// In en, this message translates to:
  /// **'No HTTPS. Visitors and your server talk over plain HTTP.'**
  String get controlsSslOffDetail;

  /// No description provided for @controlsSslFlexible.
  ///
  /// In en, this message translates to:
  /// **'Flexible'**
  String get controlsSslFlexible;

  /// No description provided for @controlsSslFlexibleDetail.
  ///
  /// In en, this message translates to:
  /// **'HTTPS for visitors, plain HTTP from Cloudflare to your server.'**
  String get controlsSslFlexibleDetail;

  /// No description provided for @controlsSslFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get controlsSslFull;

  /// No description provided for @controlsSslFullDetail.
  ///
  /// In en, this message translates to:
  /// **'HTTPS all the way; your server\'s certificate isn\'t checked.'**
  String get controlsSslFullDetail;

  /// No description provided for @controlsSslStrict.
  ///
  /// In en, this message translates to:
  /// **'Full (strict)'**
  String get controlsSslStrict;

  /// No description provided for @controlsSslStrictDetail.
  ///
  /// In en, this message translates to:
  /// **'HTTPS all the way, with a valid certificate on your server.'**
  String get controlsSslStrictDetail;

  /// No description provided for @controlsSslWeakWarning.
  ///
  /// In en, this message translates to:
  /// **'Off and Flexible leave traffic between Cloudflare and your server unencrypted.'**
  String get controlsSslWeakWarning;

  /// No description provided for @controlsSslWeakReason.
  ///
  /// In en, this message translates to:
  /// **'SSL is {mode}: traffic to your server isn\'t encrypted.'**
  String controlsSslWeakReason(String mode);

  /// No description provided for @controlsAlwaysHttps.
  ///
  /// In en, this message translates to:
  /// **'Always Use HTTPS'**
  String get controlsAlwaysHttps;

  /// No description provided for @controlsAlwaysHttpsDetail.
  ///
  /// In en, this message translates to:
  /// **'Redirects every HTTP request to HTTPS.'**
  String get controlsAlwaysHttpsDetail;

  /// No description provided for @controlsHttpsRewrites.
  ///
  /// In en, this message translates to:
  /// **'Automatic HTTPS Rewrites'**
  String get controlsHttpsRewrites;

  /// No description provided for @controlsHttpsRewritesDetail.
  ///
  /// In en, this message translates to:
  /// **'Rewrites http:// links in your pages to https:// where possible.'**
  String get controlsHttpsRewritesDetail;

  /// No description provided for @controlsMinTls.
  ///
  /// In en, this message translates to:
  /// **'Minimum TLS version'**
  String get controlsMinTls;

  /// No description provided for @controlsMinTlsOption.
  ///
  /// In en, this message translates to:
  /// **'TLS {version}'**
  String controlsMinTlsOption(String version);

  /// No description provided for @controlsMinTls10Detail.
  ///
  /// In en, this message translates to:
  /// **'Accepts every client, including very old ones.'**
  String get controlsMinTls10Detail;

  /// No description provided for @controlsMinTls11Detail.
  ///
  /// In en, this message translates to:
  /// **'Turns away clients that only speak TLS 1.0.'**
  String get controlsMinTls11Detail;

  /// No description provided for @controlsMinTls12Detail.
  ///
  /// In en, this message translates to:
  /// **'Turns away clients that only speak TLS 1.0 or 1.1.'**
  String get controlsMinTls12Detail;

  /// No description provided for @controlsMinTls13Detail.
  ///
  /// In en, this message translates to:
  /// **'Modern clients only. Some older devices and tools can\'t connect.'**
  String get controlsMinTls13Detail;

  /// No description provided for @controlsTls13.
  ///
  /// In en, this message translates to:
  /// **'TLS 1.3'**
  String get controlsTls13;

  /// No description provided for @controlsTls13On.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get controlsTls13On;

  /// No description provided for @controlsTls13OnDetail.
  ///
  /// In en, this message translates to:
  /// **'Faster, more private handshakes for clients that support it.'**
  String get controlsTls13OnDetail;

  /// No description provided for @controlsTls13Off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get controlsTls13Off;

  /// No description provided for @controlsTls13OffDetail.
  ///
  /// In en, this message translates to:
  /// **'Clients connect with TLS 1.2 or older.'**
  String get controlsTls13OffDetail;

  /// No description provided for @controlsTls13Zrt.
  ///
  /// In en, this message translates to:
  /// **'On with 0-RTT'**
  String get controlsTls13Zrt;

  /// No description provided for @controlsTls13ZrtDetail.
  ///
  /// In en, this message translates to:
  /// **'Also lets returning visitors resume a connection without a full handshake.'**
  String get controlsTls13ZrtDetail;

  /// No description provided for @controlsPurgeEverything.
  ///
  /// In en, this message translates to:
  /// **'Purge everything'**
  String get controlsPurgeEverything;

  /// No description provided for @controlsPurgeEverythingDetail.
  ///
  /// In en, this message translates to:
  /// **'Removes every cached file. Your server answers the next requests.'**
  String get controlsPurgeEverythingDetail;

  /// No description provided for @controlsPurgeEverythingTitle.
  ///
  /// In en, this message translates to:
  /// **'Purge all cached files?'**
  String get controlsPurgeEverythingTitle;

  /// No description provided for @controlsPurgeEverythingMessage.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare fetches every file for {domain} from your server again, which can slow the site and load your server for a while.'**
  String controlsPurgeEverythingMessage(String domain);

  /// No description provided for @controlsPurgeEverythingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Purge everything'**
  String get controlsPurgeEverythingConfirm;

  /// No description provided for @controlsPurgeEverythingDone.
  ///
  /// In en, this message translates to:
  /// **'Cache purged for {domain}. Your server answers the next requests.'**
  String controlsPurgeEverythingDone(String domain);

  /// No description provided for @controlsPurgeCooldown.
  ///
  /// In en, this message translates to:
  /// **'Wait {seconds} s: the Free plan allows 5 full purges per minute.'**
  String controlsPurgeCooldown(int seconds);

  /// No description provided for @controlsPurgeRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare is limiting purges for this account. Try again in a minute.'**
  String get controlsPurgeRateLimited;

  /// No description provided for @controlsPurgeUrls.
  ///
  /// In en, this message translates to:
  /// **'Purge URLs'**
  String get controlsPurgeUrls;

  /// No description provided for @controlsPurgeUrlsDetail.
  ///
  /// In en, this message translates to:
  /// **'Removes specific files from the cache.'**
  String get controlsPurgeUrlsDetail;

  /// No description provided for @controlsPurgeUrlsField.
  ///
  /// In en, this message translates to:
  /// **'URLs, one per line'**
  String get controlsPurgeUrlsField;

  /// No description provided for @controlsPurgeUrlsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'https://{domain}/styles.css'**
  String controlsPurgeUrlsPlaceholder(String domain);

  /// No description provided for @controlsPurgeUrlsHelp.
  ///
  /// In en, this message translates to:
  /// **'Full URLs on {domain} or its subdomains. Long lists go out in batches of 100.'**
  String controlsPurgeUrlsHelp(String domain);

  /// No description provided for @controlsPurgeUrlsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add at least one URL, like https://{domain}/index.html.'**
  String controlsPurgeUrlsEmpty(String domain);

  /// No description provided for @controlsPurgeUrlNotUrl.
  ///
  /// In en, this message translates to:
  /// **'Not a full URL. Start it with https://: {line}'**
  String controlsPurgeUrlNotUrl(String line);

  /// No description provided for @controlsPurgeUrlNotHttp.
  ///
  /// In en, this message translates to:
  /// **'Only http:// and https:// URLs can be purged: {line}'**
  String controlsPurgeUrlNotHttp(String line);

  /// No description provided for @controlsPurgeUrlOtherDomain.
  ///
  /// In en, this message translates to:
  /// **'Not on {domain}: {line}'**
  String controlsPurgeUrlOtherDomain(String domain, String line);

  /// No description provided for @controlsPurgeUrlsMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more line to fix} other{and {count} more lines to fix}}'**
  String controlsPurgeUrlsMore(int count);

  /// No description provided for @controlsPurgeUrlsButton.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Purge URLs} =1{Purge 1 URL} other{Purge {count} URLs}}'**
  String controlsPurgeUrlsButton(int count);

  /// No description provided for @controlsPurgeUrlsDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 URL purged.} other{{count} URLs purged.}}'**
  String controlsPurgeUrlsDone(int count);

  /// No description provided for @controlsPurgeUrlsPartial.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} URLs purged, then Cloudflare refused the rest: {reason}'**
  String controlsPurgeUrlsPartial(int done, int total, String reason);

  /// No description provided for @controlsDevMode.
  ///
  /// In en, this message translates to:
  /// **'Development mode'**
  String get controlsDevMode;

  /// No description provided for @controlsDevModeOffDetail.
  ///
  /// In en, this message translates to:
  /// **'Bypasses the cache so changes show at once. Turns itself off after 3 hours.'**
  String get controlsDevModeOffDetail;

  /// No description provided for @controlsDevModeOnDetail.
  ///
  /// In en, this message translates to:
  /// **'Cache bypassed. {time} left.'**
  String controlsDevModeOnDetail(String time);

  /// No description provided for @controlsUnderAttack.
  ///
  /// In en, this message translates to:
  /// **'Under Attack mode'**
  String get controlsUnderAttack;

  /// No description provided for @controlsUnderAttackDetail.
  ///
  /// In en, this message translates to:
  /// **'Shows every visitor a challenge before your site. Use it only during an attack: it can block APIs and apps.'**
  String get controlsUnderAttackDetail;

  /// No description provided for @controlsUnderAttackOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on Under Attack mode?'**
  String get controlsUnderAttackOnTitle;

  /// No description provided for @controlsUnderAttackOnMessage.
  ///
  /// In en, this message translates to:
  /// **'Every visitor to {domain} sees a challenge first. APIs, webhooks and apps that call this domain may stop working until you turn it off.'**
  String controlsUnderAttackOnMessage(String domain);

  /// No description provided for @controlsUnderAttackOnConfirm.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get controlsUnderAttackOnConfirm;

  /// No description provided for @controlsSecurityLevel.
  ///
  /// In en, this message translates to:
  /// **'Security level'**
  String get controlsSecurityLevel;

  /// No description provided for @controlsSecurityLevelOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get controlsSecurityLevelOff;

  /// No description provided for @controlsSecurityLevelEssentiallyOff.
  ///
  /// In en, this message translates to:
  /// **'Essentially off'**
  String get controlsSecurityLevelEssentiallyOff;

  /// No description provided for @controlsSecurityLevelLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get controlsSecurityLevelLow;

  /// No description provided for @controlsSecurityLevelMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get controlsSecurityLevelMedium;

  /// No description provided for @controlsSecurityLevelHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get controlsSecurityLevelHigh;

  /// No description provided for @controlsSecurityLevelFooter.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare no longer scores visitor threat, so levels below Under Attack have little effect. Turning Under Attack mode off restores the level shown here.'**
  String get controlsSecurityLevelFooter;

  /// No description provided for @controlsSecurityLevelLocked.
  ///
  /// In en, this message translates to:
  /// **'Restored when Under Attack mode is turned off.'**
  String get controlsSecurityLevelLocked;

  /// No description provided for @controlsPause.
  ///
  /// In en, this message translates to:
  /// **'Pause Cloudflare'**
  String get controlsPause;

  /// No description provided for @controlsPauseDetail.
  ///
  /// In en, this message translates to:
  /// **'Traffic goes straight to your server: no cache, no Cloudflare SSL, no protection. DNS keeps working.'**
  String get controlsPauseDetail;

  /// No description provided for @controlsPauseTitle.
  ///
  /// In en, this message translates to:
  /// **'Pause Cloudflare?'**
  String get controlsPauseTitle;

  /// No description provided for @controlsPauseMessage.
  ///
  /// In en, this message translates to:
  /// **'Visitors to {domain} connect straight to your server. The cache, SSL and security stop applying, and your server\'s IP address becomes visible.'**
  String controlsPauseMessage(String domain);

  /// No description provided for @controlsPauseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get controlsPauseConfirm;

  /// No description provided for @controlsPauseDone.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare paused on {domain}.'**
  String controlsPauseDone(String domain);

  /// No description provided for @controlsResume.
  ///
  /// In en, this message translates to:
  /// **'Resume Cloudflare'**
  String get controlsResume;

  /// No description provided for @controlsResumeDetail.
  ///
  /// In en, this message translates to:
  /// **'Paused: traffic bypasses the proxy, cache and security.'**
  String get controlsResumeDetail;

  /// No description provided for @controlsResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Resume Cloudflare on {domain}?'**
  String controlsResumeTitle(String domain);

  /// No description provided for @controlsResumeMessage.
  ///
  /// In en, this message translates to:
  /// **'Traffic flows through Cloudflare\'s proxy, cache and security again.'**
  String get controlsResumeMessage;

  /// No description provided for @controlsResumeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get controlsResumeConfirm;

  /// No description provided for @controlsResumeDone.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare resumed on {domain}.'**
  String controlsResumeDone(String domain);

  /// No description provided for @controlsDnssecStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get controlsDnssecStatus;

  /// No description provided for @controlsDnssecActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get controlsDnssecActive;

  /// No description provided for @controlsDnssecPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get controlsDnssecPending;

  /// No description provided for @controlsDnssecDisabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get controlsDnssecDisabled;

  /// No description provided for @controlsDnssecPendingDisabled.
  ///
  /// In en, this message translates to:
  /// **'Turning off'**
  String get controlsDnssecPendingDisabled;

  /// No description provided for @controlsDnssecError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get controlsDnssecError;

  /// No description provided for @controlsDnssecDs.
  ///
  /// In en, this message translates to:
  /// **'DS record'**
  String get controlsDnssecDs;

  /// No description provided for @controlsDnssecDigest.
  ///
  /// In en, this message translates to:
  /// **'Digest'**
  String get controlsDnssecDigest;

  /// No description provided for @controlsDnssecKeyTag.
  ///
  /// In en, this message translates to:
  /// **'Key tag'**
  String get controlsDnssecKeyTag;

  /// No description provided for @controlsDnssecAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Algorithm'**
  String get controlsDnssecAlgorithm;

  /// No description provided for @controlsDnssecDigestType.
  ///
  /// In en, this message translates to:
  /// **'Digest type'**
  String get controlsDnssecDigestType;

  /// No description provided for @controlsDnssecPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get controlsDnssecPublicKey;

  /// No description provided for @controlsDnssecFooterActive.
  ///
  /// In en, this message translates to:
  /// **'Your registrar publishes this DS record. Change it only when you move DNS to another provider.'**
  String get controlsDnssecFooterActive;

  /// No description provided for @controlsDnssecFooterPending.
  ///
  /// In en, this message translates to:
  /// **'Add this DS record at your registrar. DNSSEC turns active once the registrar publishes it.'**
  String get controlsDnssecFooterPending;

  /// No description provided for @controlsDnssecFooterDisabled.
  ///
  /// In en, this message translates to:
  /// **'DNSSEC is off. Turn it on in the Cloudflare dashboard, then add the DS record it shows at your registrar.'**
  String get controlsDnssecFooterDisabled;

  /// No description provided for @controlsDnssecFooterError.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare reports a DNSSEC problem. Check that the DS record at your registrar matches this one.'**
  String get controlsDnssecFooterError;

  /// No description provided for @controlsCopyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy {label}'**
  String controlsCopyValue(String label);

  /// No description provided for @controlsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change {setting}. {reason}'**
  String controlsSaveFailed(String setting, String reason);

  /// No description provided for @controlsNotEditable.
  ///
  /// In en, this message translates to:
  /// **'Your plan can\'t change this setting.'**
  String get controlsNotEditable;

  /// No description provided for @controlsUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read this setting. {reason}'**
  String controlsUnreadable(String reason);

  /// No description provided for @domainsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get domainsFilterAll;

  /// No description provided for @domainsFilterAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs you'**
  String get domainsFilterAttention;

  /// No description provided for @domainsFilterPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get domainsFilterPinned;

  /// No description provided for @domainsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No domains yet'**
  String get domainsEmptyTitle;

  /// No description provided for @domainsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'This token can\'t see any zones. Add a token with “Zone · Zone · Read”, or add a domain in the Cloudflare dashboard.'**
  String get domainsEmptyMessage;

  /// No description provided for @domainsAttentionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Every domain is in line.'**
  String get domainsAttentionEmpty;

  /// No description provided for @domainsPinnedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pin a domain from its page to keep it on top.'**
  String get domainsPinnedEmpty;

  /// No description provided for @zoneFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get zoneFieldStatus;

  /// No description provided for @zoneFieldPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get zoneFieldPlan;

  /// No description provided for @zoneStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get zoneStatusActive;

  /// No description provided for @zoneStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get zoneStatusPending;

  /// No description provided for @zoneStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get zoneStatusPaused;

  /// No description provided for @zoneStatusMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get zoneStatusMoved;

  /// No description provided for @zoneStatusOther.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get zoneStatusOther;

  /// No description provided for @zoneReasonPending.
  ///
  /// In en, this message translates to:
  /// **'Nameservers not switched yet: Cloudflare isn\'t serving this domain.'**
  String get zoneReasonPending;

  /// No description provided for @zoneReasonPaused.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare is paused: traffic bypasses the proxy, cache and security.'**
  String get zoneReasonPaused;

  /// No description provided for @zoneReasonDevMode.
  ///
  /// In en, this message translates to:
  /// **'Development mode is on: the cache is bypassed for {minutes} more min.'**
  String zoneReasonDevMode(int minutes);

  /// No description provided for @zoneHubDns.
  ///
  /// In en, this message translates to:
  /// **'DNS records'**
  String get zoneHubDns;

  /// No description provided for @zoneHubControls.
  ///
  /// In en, this message translates to:
  /// **'SSL, cache & security'**
  String get zoneHubControls;

  /// No description provided for @zoneHubAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get zoneHubAnalytics;

  /// No description provided for @zoneHubEmail.
  ///
  /// In en, this message translates to:
  /// **'Email routing'**
  String get zoneHubEmail;

  /// No description provided for @zoneHubMailbox.
  ///
  /// In en, this message translates to:
  /// **'Mailbox'**
  String get zoneHubMailbox;

  /// No description provided for @zoneHubWorkers.
  ///
  /// In en, this message translates to:
  /// **'Worker routes'**
  String get zoneHubWorkers;

  /// No description provided for @zoneHubPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get zoneHubPin;

  /// No description provided for @zoneHubUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get zoneHubUnpin;

  /// No description provided for @zoneHubNameservers.
  ///
  /// In en, this message translates to:
  /// **'Nameservers'**
  String get zoneHubNameservers;

  /// No description provided for @zoneHubNameserversHelp.
  ///
  /// In en, this message translates to:
  /// **'Set these at your registrar to finish moving the domain to Cloudflare.'**
  String get zoneHubNameserversHelp;

  /// No description provided for @zoneHubOpenDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open in Cloudflare dashboard'**
  String get zoneHubOpenDashboard;

  /// No description provided for @zoneHubDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get zoneHubDetails;

  /// No description provided for @zoneHubCreated.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get zoneHubCreated;

  /// No description provided for @zoneHubActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get zoneHubActivated;

  /// No description provided for @zoneHubRegistrar.
  ///
  /// In en, this message translates to:
  /// **'Previous registrar'**
  String get zoneHubRegistrar;

  /// No description provided for @zoneHubManage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get zoneHubManage;

  /// No description provided for @domainsFieldRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests · 7d'**
  String get domainsFieldRequests;

  /// No description provided for @domainsSplitPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Choose a domain to see its DNS, traffic and settings here.'**
  String get domainsSplitPlaceholder;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
