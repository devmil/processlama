import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
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
/// import 'l10n/app_localizations.dart';
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
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// The application title shown in the title bar and taskbar.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama'**
  String get appTitle;

  /// Subtitle shown next to the app title in the window header.
  ///
  /// In en, this message translates to:
  /// **'Process Explorer'**
  String get processExplorer;

  /// Tooltip for the button that hides the inspector panel.
  ///
  /// In en, this message translates to:
  /// **'Hide inspector'**
  String get hideInspector;

  /// Tooltip for the button that shows the inspector panel.
  ///
  /// In en, this message translates to:
  /// **'Show inspector'**
  String get showInspector;

  /// Tooltip for the button that opens the native update checker.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// SnackBar message when checking for updates fails.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String updateCheckFailed(String error);

  /// Message shown when no newer release is available.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama {version} (build {build}) is up to date.'**
  String updateUpToDate(String version, String build);

  /// Message shown when the selected release channel is empty.
  ///
  /// In en, this message translates to:
  /// **'No release is published for this channel yet.'**
  String get updateNoPublishedRelease;

  /// Title for the new release dialog.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama {version} is available'**
  String updateAvailableTitle(String version);

  /// Body for the new release dialog.
  ///
  /// In en, this message translates to:
  /// **'You have {installedVersion} (build {installedBuild}). Build {availableBuild} is ready on the downloads page.'**
  String updateAvailableBody(
    String installedVersion,
    String installedBuild,
    String availableBuild,
  );

  /// Button that closes the new release dialog.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// Button that opens the ProcessLama downloads page.
  ///
  /// In en, this message translates to:
  /// **'Open downloads'**
  String get openDownloads;

  /// Message shown when opening the downloads page fails.
  ///
  /// In en, this message translates to:
  /// **'The downloads page could not be opened.'**
  String get updateDownloadOpenFailed;

  /// Label shown when the tree is focused on a subtree.
  ///
  /// In en, this message translates to:
  /// **'Focused on {name}'**
  String focusedOnSubtree(String name);

  /// Fallback name when the focused subtree process name is unknown.
  ///
  /// In en, this message translates to:
  /// **'subtree'**
  String get subtree;

  /// Tooltip for the button to leave subtree focus when no focus stack.
  ///
  /// In en, this message translates to:
  /// **'Leave subtree focus'**
  String get leaveSubtreeFocus;

  /// Tooltip for the button to go back one level in the subtree focus stack.
  ///
  /// In en, this message translates to:
  /// **'Back one subtree'**
  String get backOneSubtree;

  /// Tooltip for the button to clear subtree focus and show the full tree.
  ///
  /// In en, this message translates to:
  /// **'Show full tree'**
  String get showFullTree;

  /// Tooltip for the polling interval popup button.
  ///
  /// In en, this message translates to:
  /// **'Polling interval'**
  String get pollingInterval;

  /// Hint text for the process search field.
  ///
  /// In en, this message translates to:
  /// **'Search name, PID, path, or :port'**
  String get searchHint;

  /// Tooltip for clearing the process search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Tooltip for navigating to the previous process tree search match.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get previousSearchMatch;

  /// Tooltip for navigating to the next process tree search match.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get nextSearchMatch;

  /// Tooltip for toggling case-sensitive process search.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get matchCase;

  /// Tooltip for toggling whole-word process search.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get wholeWord;

  /// Tooltip for the bookmark/save filter button.
  ///
  /// In en, this message translates to:
  /// **'Save current filter'**
  String get saveCurrentFilter;

  /// Tooltip for the saved filters popup button.
  ///
  /// In en, this message translates to:
  /// **'Saved filters'**
  String get savedFilters;

  /// Tooltip when the process tree is frozen/locked.
  ///
  /// In en, this message translates to:
  /// **'Unlock process tree'**
  String get unlockProcessTree;

  /// Tooltip when the process tree is unfrozen/unlocked.
  ///
  /// In en, this message translates to:
  /// **'Lock process tree'**
  String get lockProcessTree;

  /// Tooltip for the refresh button.
  ///
  /// In en, this message translates to:
  /// **'Refresh process snapshot'**
  String get refreshProcessSnapshot;

  /// Tooltip for the take snapshot button.
  ///
  /// In en, this message translates to:
  /// **'Take snapshot'**
  String get takeSnapshot;

  /// Tooltip and dialog title for opening an exported snapshot document.
  ///
  /// In en, this message translates to:
  /// **'Open snapshot…'**
  String get openSnapshot;

  /// Tooltip for the settings/gear button and dialog title.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// Status bar showing the number of processes.
  ///
  /// In en, this message translates to:
  /// **'{count} processes'**
  String processCount(String count);

  /// Suffix showing the number of queued process mutations.
  ///
  /// In en, this message translates to:
  /// **' - queued {count}'**
  String queuedCount(String count);

  /// Column header for process ID.
  ///
  /// In en, this message translates to:
  /// **'PID'**
  String get columnPid;

  /// Column header for process name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get columnName;

  /// Column header for CPU usage.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get columnCpu;

  /// Column header for tree CPU usage.
  ///
  /// In en, this message translates to:
  /// **'Tree CPU'**
  String get columnTreeCpu;

  /// Column header for GPU usage.
  ///
  /// In en, this message translates to:
  /// **'GPU'**
  String get columnGpu;

  /// Column header for tree GPU usage.
  ///
  /// In en, this message translates to:
  /// **'Tree GPU'**
  String get columnTreeGpu;

  /// Column header for resident set size (memory).
  ///
  /// In en, this message translates to:
  /// **'RSS'**
  String get columnRss;

  /// Column header for tree resident set size.
  ///
  /// In en, this message translates to:
  /// **'Tree RSS'**
  String get columnTreeRss;

  /// Column header for network input.
  ///
  /// In en, this message translates to:
  /// **'Net In'**
  String get columnNetIn;

  /// Column header for network output.
  ///
  /// In en, this message translates to:
  /// **'Net Out'**
  String get columnNetOut;

  /// Column header for tree network input.
  ///
  /// In en, this message translates to:
  /// **'Tree Net In'**
  String get columnTreeNetIn;

  /// Column header for tree network output.
  ///
  /// In en, this message translates to:
  /// **'Tree Net Out'**
  String get columnTreeNetOut;

  /// Column header for process storage read throughput.
  ///
  /// In en, this message translates to:
  /// **'Storage Read'**
  String get columnStorageRead;

  /// Column header for process storage write throughput.
  ///
  /// In en, this message translates to:
  /// **'Storage Write'**
  String get columnStorageWrite;

  /// Column header for subtree storage read throughput.
  ///
  /// In en, this message translates to:
  /// **'Tree Storage Read'**
  String get columnTreeStorageRead;

  /// Column header for subtree storage write throughput.
  ///
  /// In en, this message translates to:
  /// **'Tree Storage Write'**
  String get columnTreeStorageWrite;

  /// Column header for process start time.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get columnStarted;

  /// Column header for process state.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get columnState;

  /// Column header for user ID.
  ///
  /// In en, this message translates to:
  /// **'UID'**
  String get columnUid;

  /// Context menu item to show all columns.
  ///
  /// In en, this message translates to:
  /// **'Show all columns'**
  String get showAllColumns;

  /// Context menu item to reset column order.
  ///
  /// In en, this message translates to:
  /// **'Reset column order'**
  String get resetColumnOrder;

  /// Empty-state message when no processes match the filter.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that filter.'**
  String get noProcessesMatchFilter;

  /// Tooltip for the order-locked hint.
  ///
  /// In en, this message translates to:
  /// **'Live ordering is paused while the pointer is over the tree'**
  String get liveOrderingPausedTooltip;

  /// Badge text shown when live ordering is paused.
  ///
  /// In en, this message translates to:
  /// **'Live ordering paused'**
  String get liveOrderingPaused;

  /// Tooltip for the collapse tree node button.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// Tooltip for the expand tree node button.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// Tooltip for the unpin process button.
  ///
  /// In en, this message translates to:
  /// **'Unpin process'**
  String get unpinProcess;

  /// Tooltip for the pin process button.
  ///
  /// In en, this message translates to:
  /// **'Pin process'**
  String get pinProcess;

  /// Tooltip for the spawned change marker icon.
  ///
  /// In en, this message translates to:
  /// **'Spawned'**
  String get spawned;

  /// Tooltip for the terminated change marker icon.
  ///
  /// In en, this message translates to:
  /// **'Terminated'**
  String get terminated;

  /// Context menu item to unpin a process.
  ///
  /// In en, this message translates to:
  /// **'Unpin process'**
  String get unpinProcessMenu;

  /// Context menu item to pin a process.
  ///
  /// In en, this message translates to:
  /// **'Pin process'**
  String get pinProcessMenu;

  /// Context menu item to focus on a subtree.
  ///
  /// In en, this message translates to:
  /// **'Focus subtree'**
  String get focusSubtree;

  /// Context menu item to expand a subtree.
  ///
  /// In en, this message translates to:
  /// **'Expand subtree'**
  String get expandSubtree;

  /// Context menu item to collapse a subtree.
  ///
  /// In en, this message translates to:
  /// **'Collapse subtree'**
  String get collapseSubtree;

  /// Context menu item to send SIGTERM to a process.
  ///
  /// In en, this message translates to:
  /// **'Terminate process'**
  String get terminateProcessMenu;

  /// Context menu item to send SIGKILL to a process.
  ///
  /// In en, this message translates to:
  /// **'Force kill process'**
  String get killProcessMenu;

  /// Context menu item to send SIGSTOP to a process.
  ///
  /// In en, this message translates to:
  /// **'Suspend process'**
  String get suspendProcessMenu;

  /// Context menu item to send SIGCONT to a process.
  ///
  /// In en, this message translates to:
  /// **'Resume process'**
  String get resumeProcessMenu;

  /// SnackBar message after sending a terminate signal.
  ///
  /// In en, this message translates to:
  /// **'Terminate signal sent.'**
  String get processTerminated;

  /// SnackBar message after sending a kill signal.
  ///
  /// In en, this message translates to:
  /// **'Kill signal sent.'**
  String get processKilled;

  /// SnackBar message after sending a suspend signal.
  ///
  /// In en, this message translates to:
  /// **'Suspend signal sent.'**
  String get processSuspended;

  /// SnackBar message after sending a resume signal.
  ///
  /// In en, this message translates to:
  /// **'Resume signal sent.'**
  String get processResumed;

  /// SnackBar message when a process action fails.
  ///
  /// In en, this message translates to:
  /// **'Process action failed: {error}'**
  String processActionFailed(String error);

  /// Cancel button on the process action confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get processActionConfirmCancel;

  /// Title of the confirmation dialog for terminating a process.
  ///
  /// In en, this message translates to:
  /// **'Terminate process?'**
  String get terminateConfirmTitle;

  /// Body of the confirmation dialog for terminating a process.
  ///
  /// In en, this message translates to:
  /// **'Send SIGTERM to \"{name}\" (pid {pid}). The process can clean up before exiting.'**
  String terminateConfirmBody(String name, String pid);

  /// Title of the confirmation dialog for force killing a process.
  ///
  /// In en, this message translates to:
  /// **'Force kill process?'**
  String get killConfirmTitle;

  /// Body of the confirmation dialog for force killing a process.
  ///
  /// In en, this message translates to:
  /// **'Send SIGKILL to \"{name}\" (pid {pid}). The process is killed immediately and may leave data in an inconsistent state.'**
  String killConfirmBody(String name, String pid);

  /// Title of the confirmation dialog for suspending a process.
  ///
  /// In en, this message translates to:
  /// **'Suspend process?'**
  String get suspendConfirmTitle;

  /// Body of the confirmation dialog for suspending a process.
  ///
  /// In en, this message translates to:
  /// **'Send SIGSTOP to \"{name}\" (pid {pid}). The process pauses until it is resumed.'**
  String suspendConfirmBody(String name, String pid);

  /// Context menu item to copy a process PID.
  ///
  /// In en, this message translates to:
  /// **'Copy PID {pid}'**
  String copyPid(String pid);

  /// Context menu item to copy a process name.
  ///
  /// In en, this message translates to:
  /// **'Copy {name}'**
  String copyName(String name);

  /// Context menu item to copy the executable path.
  ///
  /// In en, this message translates to:
  /// **'Copy executable path'**
  String get copyExecutablePath;

  /// Setting label for remembering tree expansion state.
  ///
  /// In en, this message translates to:
  /// **'Remember tree expansion'**
  String get rememberTreeExpansion;

  /// Setting label for subtle CPU-tinted process rows.
  ///
  /// In en, this message translates to:
  /// **'CPU row heatmap'**
  String get rowHeatmap;

  /// Setting label for how tall process tree and list rows are.
  ///
  /// In en, this message translates to:
  /// **'Row density'**
  String get rowDensity;

  /// Row density option: shortest rows, most processes on screen.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get rowDensityCompact;

  /// Row density option: medium row height.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get rowDensityRegular;

  /// Row density option: tallest rows.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get rowDensityComfortable;

  /// Setting label for choosing the app update release channel.
  ///
  /// In en, this message translates to:
  /// **'Release channel'**
  String get releaseChannel;

  /// Release channel option for stable updates only.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get releaseChannelStable;

  /// Release channel option for beta updates plus stable updates.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get releaseChannelBeta;

  /// Appearance mode option: system theme.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// Appearance mode option: light theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// Appearance mode option: dark theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// Button text to close a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Section header for column preferences.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columns;

  /// Tooltip for the move column up arrow.
  ///
  /// In en, this message translates to:
  /// **'Move column earlier'**
  String get moveColumnEarlier;

  /// Tooltip for the move column down arrow.
  ///
  /// In en, this message translates to:
  /// **'Move column later'**
  String get moveColumnLater;

  /// Label for the polling interval slider.
  ///
  /// In en, this message translates to:
  /// **'Polling interval: {value}ms'**
  String pollingIntervalLabel(String value);

  /// Fallback text for empty or unknown values.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// Inspector panel title when no process is selected.
  ///
  /// In en, this message translates to:
  /// **'Inspector'**
  String get inspector;

  /// Subtitle when no process is selected in the inspector.
  ///
  /// In en, this message translates to:
  /// **'No process selected'**
  String get noProcessSelected;

  /// Subtitle showing PID and platform.
  ///
  /// In en, this message translates to:
  /// **'pid {pid} · {platform}'**
  String pidPlatform(String pid, String platform);

  /// Tab label for the overview inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tabOverview;

  /// Tab label for the process details inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get tabDetails;

  /// Tab label for the files inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

  /// Tab label for the sockets inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Sockets'**
  String get tabSockets;

  /// Tab label for the combined files and sockets inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Files & Sockets'**
  String get tabFilesAndSockets;

  /// Tab label for the network inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get tabNetwork;

  /// Tab label for the threads inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get tabThreads;

  /// Tab label for the security inspector tab.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get tabSecurity;

  /// Detail label for network input rate.
  ///
  /// In en, this message translates to:
  /// **'Network In'**
  String get networkIn;

  /// Detail label for network output rate.
  ///
  /// In en, this message translates to:
  /// **'Network Out'**
  String get networkOut;

  /// Detail label for total network input.
  ///
  /// In en, this message translates to:
  /// **'Total In'**
  String get totalIn;

  /// Detail label for total network output.
  ///
  /// In en, this message translates to:
  /// **'Total Out'**
  String get totalOut;

  /// Graph row label for tree network input.
  ///
  /// In en, this message translates to:
  /// **'Tree Network In'**
  String get treeNetworkIn;

  /// Graph row label for tree network output.
  ///
  /// In en, this message translates to:
  /// **'Tree Network Out'**
  String get treeNetworkOut;

  /// Detail and graph label for storage read throughput.
  ///
  /// In en, this message translates to:
  /// **'Storage Read'**
  String get storageRead;

  /// Detail and graph label for storage write throughput.
  ///
  /// In en, this message translates to:
  /// **'Storage Write'**
  String get storageWrite;

  /// Detail label for cumulative process storage reads.
  ///
  /// In en, this message translates to:
  /// **'Total Storage Read'**
  String get totalStorageRead;

  /// Detail label for cumulative process storage writes.
  ///
  /// In en, this message translates to:
  /// **'Total Storage Write'**
  String get totalStorageWrite;

  /// Combined storage throughput history graph title.
  ///
  /// In en, this message translates to:
  /// **'Storage history'**
  String get storageHistory;

  /// Combined network throughput history graph title.
  ///
  /// In en, this message translates to:
  /// **'Network history'**
  String get networkHistory;

  /// Compact direction label for network output above input in the throughput graph.
  ///
  /// In en, this message translates to:
  /// **'Out / In'**
  String get networkOutIn;

  /// Compact direction label for paired storage throughput values.
  ///
  /// In en, this message translates to:
  /// **'Read / Write'**
  String get storageReadWrite;

  /// Memory summary label in the process inspector overview.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get overviewMemory;

  /// Storage throughput summary label in the process inspector overview.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get overviewStorage;

  /// Value shown when the operating system does not expose a metric.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get metricUnavailable;

  /// Scope label for tree metrics.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get tree;

  /// Scope label for process metrics.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get processScope;

  /// Metric card label for descendant count.
  ///
  /// In en, this message translates to:
  /// **'Descendants'**
  String get descendants;

  /// Detail label for parent PID.
  ///
  /// In en, this message translates to:
  /// **'Parent PID'**
  String get parentPid;

  /// Detail label for user ID.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get userId;

  /// Detail label for process status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// Detail label for thread count.
  ///
  /// In en, this message translates to:
  /// **'Threads'**
  String get threads;

  /// Detail label for open file count.
  ///
  /// In en, this message translates to:
  /// **'Open Files'**
  String get openFiles;

  /// Detail label for virtual memory size.
  ///
  /// In en, this message translates to:
  /// **'Virtual Memory'**
  String get virtualMemory;

  /// Detail label for process nice value.
  ///
  /// In en, this message translates to:
  /// **'Nice'**
  String get nice;

  /// Detail label for process priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// Detail label for a section summary row.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// Security detail label for code signing status.
  ///
  /// In en, this message translates to:
  /// **'Signing'**
  String get signing;

  /// Security detail label for signing authority.
  ///
  /// In en, this message translates to:
  /// **'Authority'**
  String get authority;

  /// Security detail label for Apple Developer Team ID.
  ///
  /// In en, this message translates to:
  /// **'Team ID'**
  String get teamId;

  /// Security detail label for bundle identifier.
  ///
  /// In en, this message translates to:
  /// **'Bundle ID'**
  String get bundleId;

  /// Security detail label for entitlements.
  ///
  /// In en, this message translates to:
  /// **'Entitlements'**
  String get entitlements;

  /// Security detail label for Gatekeeper origin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get origin;

  /// Security detail label for sandbox state.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get sandbox;

  /// Security detail label for hardened runtime state.
  ///
  /// In en, this message translates to:
  /// **'Hardened RT'**
  String get hardenedRuntime;

  /// Security detail label for executable architecture.
  ///
  /// In en, this message translates to:
  /// **'Architecture'**
  String get architecture;

  /// Security detail label for Rosetta translation state.
  ///
  /// In en, this message translates to:
  /// **'Rosetta'**
  String get rosetta;

  /// Generic affirmative value.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Generic negative value.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Fallback when an open file path is unavailable.
  ///
  /// In en, this message translates to:
  /// **'-'**
  String get noPathAvailable;

  /// Empty state for the inspector files tab.
  ///
  /// In en, this message translates to:
  /// **'No open files reported for this process.'**
  String get noOpenFilesReported;

  /// Notice when the open file list is capped.
  ///
  /// In en, this message translates to:
  /// **'Showing the first 500 open files.'**
  String get openFilesTruncated;

  /// Empty state for the inspector sockets tab.
  ///
  /// In en, this message translates to:
  /// **'No sockets reported for this process.'**
  String get noSocketsReported;

  /// Empty state for the inspector threads tab.
  ///
  /// In en, this message translates to:
  /// **'No threads reported for this process.'**
  String get noThreadsReported;

  /// Empty state for the inspector security tab.
  ///
  /// In en, this message translates to:
  /// **'No security metadata reported for this process.'**
  String get noSecurityMetadataReported;

  /// Restricted state shown when the operating system denies process detail access.
  ///
  /// In en, this message translates to:
  /// **'Restricted access: {reason}'**
  String restrictedByMacos(String reason);

  /// Detail label for GPU usage.
  ///
  /// In en, this message translates to:
  /// **'GPU'**
  String get gpu;

  /// Detail label for network input rate in overview.
  ///
  /// In en, this message translates to:
  /// **'Net in'**
  String get netIn;

  /// Detail label for network output rate in overview.
  ///
  /// In en, this message translates to:
  /// **'Net out'**
  String get netOut;

  /// Detail label for process identity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identity;

  /// Detail label for executable path.
  ///
  /// In en, this message translates to:
  /// **'Executable'**
  String get executable;

  /// Detail label for application bundle path.
  ///
  /// In en, this message translates to:
  /// **'Application bundle'**
  String get applicationBundle;

  /// Detail label for command line.
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get commandLine;

  /// Section header for pinned processes in the navigation rail.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// Empty text for the pinned section.
  ///
  /// In en, this message translates to:
  /// **'Pin rows for quick access.'**
  String get pinRowsForQuickAccess;

  /// Section header for snapshots in the navigation rail.
  ///
  /// In en, this message translates to:
  /// **'Snapshots'**
  String get snapshots;

  /// Label for the live snapshot entry.
  ///
  /// In en, this message translates to:
  /// **'Live · {platform}'**
  String livePlatform(String platform);

  /// Trailing badge for the live snapshot entry.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get now;

  /// Section header for filters in the navigation rail.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// Footer polling status text.
  ///
  /// In en, this message translates to:
  /// **'Polling every {interval} ms'**
  String pollingStatus(String interval);

  /// SnackBar message after successful export.
  ///
  /// In en, this message translates to:
  /// **'Exported {path}'**
  String exportedPath(String path);

  /// SnackBar message after export failure.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// Context menu item for exporting a saved snapshot.
  ///
  /// In en, this message translates to:
  /// **'Export snapshot…'**
  String get exportSnapshot;

  /// Context menu item for renaming a saved snapshot.
  ///
  /// In en, this message translates to:
  /// **'Rename snapshot…'**
  String get renameSnapshot;

  /// Dialog title for renaming a saved snapshot.
  ///
  /// In en, this message translates to:
  /// **'Rename snapshot'**
  String get renameSnapshotTitle;

  /// Text field label for a saved snapshot name.
  ///
  /// In en, this message translates to:
  /// **'Snapshot name'**
  String get snapshotName;

  /// Context menu item for deleting a saved snapshot.
  ///
  /// In en, this message translates to:
  /// **'Delete snapshot'**
  String get deleteSnapshot;

  /// Context menu item for deleting a saved filter.
  ///
  /// In en, this message translates to:
  /// **'Delete filter'**
  String get deleteFilter;

  /// SnackBar message after taking a snapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot taken'**
  String get snapshotTaken;

  /// SnackBar message after snapshot failure.
  ///
  /// In en, this message translates to:
  /// **'Snapshot failed: {error}'**
  String snapshotFailed(String error);

  /// SnackBar message after loading a snapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot loaded'**
  String get snapshotLoaded;

  /// SnackBar message after snapshot load failure.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String snapshotLoadFailed(String error);

  /// SnackBar message after deleting a snapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot deleted'**
  String get snapshotDeleted;

  /// SnackBar message after renaming a snapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot renamed'**
  String get snapshotRenamed;

  /// SnackBar message after snapshot rename failure.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String snapshotRenameFailed(String error);

  /// SnackBar message after snapshot delete failure.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String snapshotDeleteFailed(String error);

  /// Title shown when the app fails to bootstrap.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama could not finish starting.'**
  String get bootstrapErrorTitle;

  /// Description shown when the app fails to bootstrap.
  ///
  /// In en, this message translates to:
  /// **'The app window is alive, but one of the startup services failed.'**
  String get bootstrapErrorDescription;

  /// Platform feature name for process enumeration.
  ///
  /// In en, this message translates to:
  /// **'Process enumeration'**
  String get featureProcessEnumeration;

  /// Platform feature name for process tree synthesis.
  ///
  /// In en, this message translates to:
  /// **'Process tree synthesis'**
  String get featureProcessTreeSynthesis;

  /// Platform feature name for files and sockets.
  ///
  /// In en, this message translates to:
  /// **'Files and sockets'**
  String get featureFilesAndSockets;

  /// Platform feature name for network throughput.
  ///
  /// In en, this message translates to:
  /// **'Network throughput'**
  String get featureNetworkThroughput;

  /// Platform feature name for security metadata.
  ///
  /// In en, this message translates to:
  /// **'Security metadata'**
  String get featureSecurityMetadata;

  /// Platform feature name for permission restricted process hints.
  ///
  /// In en, this message translates to:
  /// **'Restricted process hints'**
  String get featureRestrictedProcessHints;

  /// Platform feature name for snapshot documents.
  ///
  /// In en, this message translates to:
  /// **'Snapshot documents'**
  String get featureSnapshotDocuments;

  /// Empty state text when no filters are saved.
  ///
  /// In en, this message translates to:
  /// **'No saved filters.'**
  String get noSavedFilters;

  /// No description provided for @statusTreeLocked.
  ///
  /// In en, this message translates to:
  /// **'Process tree locked'**
  String get statusTreeLocked;

  /// No description provided for @toolbarLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get toolbarLock;

  /// No description provided for @toolbarSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot'**
  String get toolbarSnapshot;

  /// No description provided for @toolbarUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get toolbarUpdates;

  /// No description provided for @snapshotOptions.
  ///
  /// In en, this message translates to:
  /// **'More snapshot options'**
  String get snapshotOptions;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @selectProcessToInspect.
  ///
  /// In en, this message translates to:
  /// **'Select a process to inspect it.'**
  String get selectProcessToInspect;

  /// No description provided for @selectProcessToInspectNetwork.
  ///
  /// In en, this message translates to:
  /// **'Select a process to inspect its network throughput.'**
  String get selectProcessToInspectNetwork;

  /// No description provided for @bootstrapModeMessage.
  ///
  /// In en, this message translates to:
  /// **'Bootstrap mode: {error}'**
  String bootstrapModeMessage(String error);

  /// No description provided for @sortedAscending.
  ///
  /// In en, this message translates to:
  /// **'sorted ascending'**
  String get sortedAscending;

  /// No description provided for @sortedDescending.
  ///
  /// In en, this message translates to:
  /// **'sorted descending'**
  String get sortedDescending;

  /// No description provided for @resizeInspector.
  ///
  /// In en, this message translates to:
  /// **'Resize inspector'**
  String get resizeInspector;

  /// No description provided for @morePreferencesOptions.
  ///
  /// In en, this message translates to:
  /// **'More preferences options'**
  String get morePreferencesOptions;

  /// No description provided for @minimizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Minimize window'**
  String get minimizeWindow;

  /// No description provided for @maximizeWindow.
  ///
  /// In en, this message translates to:
  /// **'Maximize or restore window'**
  String get maximizeWindow;

  /// No description provided for @closeWindow.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get closeWindow;

  /// No description provided for @installNetworkTelemetry.
  ///
  /// In en, this message translates to:
  /// **'Install network telemetry…'**
  String get installNetworkTelemetry;

  /// No description provided for @networkTelemetryInstallDescription.
  ///
  /// In en, this message translates to:
  /// **'Linux network activity needs a system service. Installing or repairing it requires administrator authorization and enables per-process network throughput for all users on this machine.'**
  String get networkTelemetryInstallDescription;

  /// No description provided for @networkTelemetryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Network telemetry unavailable'**
  String get networkTelemetryUnavailable;

  /// No description provided for @networkTelemetryUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'The Linux network service is missing or has stopped. Install or repair it to see live network activity.'**
  String get networkTelemetryUnavailableDescription;

  /// No description provided for @networkTelemetryInstalled.
  ///
  /// In en, this message translates to:
  /// **'Network service installed and started.'**
  String get networkTelemetryInstalled;

  /// No description provided for @networkTelemetryInstallerMissing.
  ///
  /// In en, this message translates to:
  /// **'This build does not include the network service. Install a current ProcessLama package or portable bundle.'**
  String get networkTelemetryInstallerMissing;

  /// No description provided for @networkTelemetryAuthorizationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System authorization is unavailable. Install the DEB or RPM package to enable network telemetry.'**
  String get networkTelemetryAuthorizationUnavailable;

  /// No description provided for @networkTelemetryAuthorizationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Network service installation was cancelled.'**
  String get networkTelemetryAuthorizationCancelled;

  /// No description provided for @networkTelemetryInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Network service installation failed. Check the system journal for processlama-network.service.'**
  String get networkTelemetryInstallFailed;

  /// No description provided for @searchMatchPosition.
  ///
  /// In en, this message translates to:
  /// **'{current} of {count} matches'**
  String searchMatchPosition(String current, String count);

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About ProcessLama'**
  String get aboutApp;

  /// No description provided for @makerLine.
  ///
  /// In en, this message translates to:
  /// **'by Devmil Solutions'**
  String get makerLine;

  /// No description provided for @brandTooltip.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama · by Devmil Solutions'**
  String get brandTooltip;

  /// No description provided for @aboutProductName.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama'**
  String get aboutProductName;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · build {build}'**
  String aboutVersion(String version, String build);

  /// No description provided for @lamaFamily.
  ///
  /// In en, this message translates to:
  /// **'The Lama family'**
  String get lamaFamily;

  /// No description provided for @closeAbout.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAbout;

  /// About dialog button that opens the bundled license notices.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get aboutLicenses;

  /// No description provided for @filterNoMatchesHelp.
  ///
  /// In en, this message translates to:
  /// **'Try a broader name or clear the CPU threshold.'**
  String get filterNoMatchesHelp;

  /// No description provided for @remoteTabLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get remoteTabLocal;

  /// No description provided for @remoteTabOpenMenu.
  ///
  /// In en, this message translates to:
  /// **'Open remote host'**
  String get remoteTabOpenMenu;

  /// No description provided for @remoteTabClose.
  ///
  /// In en, this message translates to:
  /// **'Close {tab}'**
  String remoteTabClose(String tab);

  /// No description provided for @remoteTabMoveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move tab left'**
  String get remoteTabMoveLeft;

  /// No description provided for @remoteTabMoveRight.
  ///
  /// In en, this message translates to:
  /// **'Move tab right'**
  String get remoteTabMoveRight;

  /// No description provided for @remoteTabMore.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get remoteTabMore;

  /// No description provided for @remoteTabTooltip.
  ///
  /// In en, this message translates to:
  /// **'{alias} · {platform} · helper {version}'**
  String remoteTabTooltip(String alias, String platform, String version);

  /// No description provided for @remoteTabSemantics.
  ///
  /// In en, this message translates to:
  /// **'{name}, {status}'**
  String remoteTabSemantics(String name, String status);

  /// No description provided for @remoteTabLimit.
  ///
  /// In en, this message translates to:
  /// **'You can open up to {count} remote tabs.'**
  String remoteTabLimit(String count);

  /// No description provided for @remoteHostAddMenu.
  ///
  /// In en, this message translates to:
  /// **'Add remote host…'**
  String get remoteHostAddMenu;

  /// No description provided for @remoteHostManageMenu.
  ///
  /// In en, this message translates to:
  /// **'Manage remote hosts…'**
  String get remoteHostManageMenu;

  /// No description provided for @remoteHostMenuEmpty.
  ///
  /// In en, this message translates to:
  /// **'No other saved hosts'**
  String get remoteHostMenuEmpty;

  /// No description provided for @remotePhaseIdle.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get remotePhaseIdle;

  /// No description provided for @remotePhaseConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get remotePhaseConnecting;

  /// No description provided for @remotePhaseInstalling.
  ///
  /// In en, this message translates to:
  /// **'Installing helper'**
  String get remotePhaseInstalling;

  /// No description provided for @remotePhaseLive.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get remotePhaseLive;

  /// No description provided for @remotePhaseReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get remotePhaseReconnecting;

  /// No description provided for @remotePhaseDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get remotePhaseDisconnected;

  /// No description provided for @remotePhaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get remotePhaseFailed;

  /// No description provided for @remoteFailureSshMissing.
  ///
  /// In en, this message translates to:
  /// **'OpenSSH is not installed on this computer.'**
  String get remoteFailureSshMissing;

  /// No description provided for @remoteFailureSshTooOld.
  ///
  /// In en, this message translates to:
  /// **'OpenSSH on this computer is older than 8.9.'**
  String get remoteFailureSshTooOld;

  /// No description provided for @remoteFailureSshConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'SSH could not connect. Check the host, the network and your ~/.ssh/config.'**
  String get remoteFailureSshConnectionFailed;

  /// No description provided for @remoteFailureHostKeyUntrusted.
  ///
  /// In en, this message translates to:
  /// **'The host key is not trusted yet. Connect once with ssh in a terminal.'**
  String get remoteFailureHostKeyUntrusted;

  /// No description provided for @remoteFailureAuthenticationInteractive.
  ///
  /// In en, this message translates to:
  /// **'SSH asks for a password or a confirmation. Set up key-based login or an agent.'**
  String get remoteFailureAuthenticationInteractive;

  /// No description provided for @remoteFailureUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'This host\'s system is not supported.'**
  String get remoteFailureUnsupportedPlatform;

  /// No description provided for @remoteFailureHelperNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'The ProcessLama helper is not installed on this host.'**
  String get remoteFailureHelperNotInstalled;

  /// No description provided for @remoteFailureHelperOutdated.
  ///
  /// In en, this message translates to:
  /// **'The helper on this host is outdated.'**
  String get remoteFailureHelperOutdated;

  /// No description provided for @remoteFailureHelperDamaged.
  ///
  /// In en, this message translates to:
  /// **'The helper on this host is damaged.'**
  String get remoteFailureHelperDamaged;

  /// No description provided for @remoteFailureHelperStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The helper did not start. A login script may print text or read input.'**
  String get remoteFailureHelperStartFailed;

  /// No description provided for @remoteFailureInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Installing the helper failed.'**
  String get remoteFailureInstallFailed;

  /// No description provided for @remoteFailureInstallNoSpace.
  ///
  /// In en, this message translates to:
  /// **'The host has no space left for the helper.'**
  String get remoteFailureInstallNoSpace;

  /// No description provided for @remoteFailureInstallNoexec.
  ///
  /// In en, this message translates to:
  /// **'The home directory on this host does not allow running programs (noexec).'**
  String get remoteFailureInstallNoexec;

  /// No description provided for @remoteFailureInstallRefused.
  ///
  /// In en, this message translates to:
  /// **'The install directory is unsafe: a symbolic link or a directory owned by someone else.'**
  String get remoteFailureInstallRefused;

  /// No description provided for @remoteFailureProtocolMismatch.
  ///
  /// In en, this message translates to:
  /// **'The helper speaks a different protocol version.'**
  String get remoteFailureProtocolMismatch;

  /// No description provided for @remoteFailureHeartbeatLost.
  ///
  /// In en, this message translates to:
  /// **'The host stopped responding.'**
  String get remoteFailureHeartbeatLost;

  /// No description provided for @remoteFailureFrameTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The host sent more data than allowed.'**
  String get remoteFailureFrameTooLarge;

  /// No description provided for @remoteFailureRemoteRestricted.
  ///
  /// In en, this message translates to:
  /// **'The host denied the request.'**
  String get remoteFailureRemoteRestricted;

  /// No description provided for @remoteFailureCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled.'**
  String get remoteFailureCanceled;

  /// No description provided for @remoteFailureInternal.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get remoteFailureInternal;

  /// No description provided for @remoteHostProbeSshUnreachable.
  ///
  /// In en, this message translates to:
  /// **'SSH unreachable'**
  String get remoteHostProbeSshUnreachable;

  /// No description provided for @remoteHostProbeHostKeyUntrusted.
  ///
  /// In en, this message translates to:
  /// **'Host key not trusted'**
  String get remoteHostProbeHostKeyUntrusted;

  /// No description provided for @remoteHostProbeAuthenticationInteractive.
  ///
  /// In en, this message translates to:
  /// **'Authentication needs interaction'**
  String get remoteHostProbeAuthenticationInteractive;

  /// No description provided for @remoteHostProbeUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Unsupported platform'**
  String get remoteHostProbeUnsupportedPlatform;

  /// No description provided for @remoteHostProbeHelperMissing.
  ///
  /// In en, this message translates to:
  /// **'Helper missing'**
  String get remoteHostProbeHelperMissing;

  /// No description provided for @remoteHostProbeHelperOutdated.
  ///
  /// In en, this message translates to:
  /// **'Helper outdated'**
  String get remoteHostProbeHelperOutdated;

  /// No description provided for @remoteHostProbeReady.
  ///
  /// In en, this message translates to:
  /// **'Ready: {platform}, helper {version}'**
  String remoteHostProbeReady(String platform, String version);

  /// No description provided for @remoteHostProbeRunning.
  ///
  /// In en, this message translates to:
  /// **'Testing the connection…'**
  String get remoteHostProbeRunning;

  /// No description provided for @remoteHostEditorAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add remote host'**
  String get remoteHostEditorAddTitle;

  /// No description provided for @remoteHostEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit remote host'**
  String get remoteHostEditorEditTitle;

  /// No description provided for @remoteHostDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get remoteHostDisplayName;

  /// No description provided for @remoteHostAlias.
  ///
  /// In en, this message translates to:
  /// **'SSH host alias'**
  String get remoteHostAlias;

  /// No description provided for @remoteHostAliasHelp.
  ///
  /// In en, this message translates to:
  /// **'A Host entry of your ~/.ssh/config. User names, ports, keys and jump hosts belong there; ProcessLama stores only the alias.'**
  String get remoteHostAliasHelp;

  /// No description provided for @remoteHostAliasInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use letters, digits, dots, dashes and underscores, starting with a letter or digit.'**
  String get remoteHostAliasInvalid;

  /// No description provided for @remoteHostDisplayNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use 1 to 64 characters.'**
  String get remoteHostDisplayNameInvalid;

  /// No description provided for @remoteHostAutoInstall.
  ///
  /// In en, this message translates to:
  /// **'Install helper automatically'**
  String get remoteHostAutoInstall;

  /// No description provided for @remoteHostAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect automatically'**
  String get remoteHostAutoReconnect;

  /// No description provided for @remoteHostOpenOnStartup.
  ///
  /// In en, this message translates to:
  /// **'Open on startup'**
  String get remoteHostOpenOnStartup;

  /// No description provided for @remoteHostOpenOnStartupRemember.
  ///
  /// In en, this message translates to:
  /// **'As at quit'**
  String get remoteHostOpenOnStartupRemember;

  /// No description provided for @remoteHostOpenOnStartupAlways.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get remoteHostOpenOnStartupAlways;

  /// No description provided for @remoteHostOpenOnStartupNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get remoteHostOpenOnStartupNever;

  /// No description provided for @remoteHostBackgroundRefresh.
  ///
  /// In en, this message translates to:
  /// **'Background refresh'**
  String get remoteHostBackgroundRefresh;

  /// No description provided for @remoteHostBackgroundRefreshDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get remoteHostBackgroundRefreshDefault;

  /// No description provided for @remoteRefreshSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow (5 s)'**
  String get remoteRefreshSlow;

  /// No description provided for @remoteRefreshLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get remoteRefreshLive;

  /// No description provided for @remoteRefreshPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get remoteRefreshPaused;

  /// No description provided for @remoteHostTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get remoteHostTestConnection;

  /// No description provided for @remoteHostSetupGuide.
  ///
  /// In en, this message translates to:
  /// **'Setup guide'**
  String get remoteHostSetupGuide;

  /// No description provided for @remoteHostSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get remoteHostSave;

  /// No description provided for @remoteHostCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get remoteHostCancel;

  /// No description provided for @remoteHostSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The remote host could not be saved.'**
  String get remoteHostSaveFailed;

  /// No description provided for @remoteHostTooMany.
  ///
  /// In en, this message translates to:
  /// **'You have reached the maximum number of remote hosts.'**
  String get remoteHostTooMany;

  /// No description provided for @remoteHelperInstallTitle.
  ///
  /// In en, this message translates to:
  /// **'Install helper on {host}?'**
  String remoteHelperInstallTitle(String host);

  /// No description provided for @remoteHelperUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update helper on {host}?'**
  String remoteHelperUpdateTitle(String host);

  /// No description provided for @remoteHelperInstallBody.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama copies a small helper program to this host and runs it as your SSH user. It never uses sudo.'**
  String get remoteHelperInstallBody;

  /// No description provided for @remoteHelperInstallPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get remoteHelperInstallPath;

  /// No description provided for @remoteHelperInstallVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get remoteHelperInstallVersion;

  /// No description provided for @remoteHelperInstallSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get remoteHelperInstallSize;

  /// No description provided for @remoteHelperInstallChecksum.
  ///
  /// In en, this message translates to:
  /// **'SHA-256'**
  String get remoteHelperInstallChecksum;

  /// No description provided for @remoteHelperInstallAction.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get remoteHelperInstallAction;

  /// No description provided for @remoteHelperInstallAlways.
  ///
  /// In en, this message translates to:
  /// **'Install and always install for this host'**
  String get remoteHelperInstallAlways;

  /// No description provided for @remoteHelperUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get remoteHelperUpdateAction;

  /// No description provided for @remoteHelperUpdateAlways.
  ///
  /// In en, this message translates to:
  /// **'Update and always install for this host'**
  String get remoteHelperUpdateAlways;

  /// No description provided for @remoteHelperInstalled.
  ///
  /// In en, this message translates to:
  /// **'Helper installed on {host}.'**
  String remoteHelperInstalled(String host);

  /// No description provided for @remoteHelperInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not install the helper on {host}. {reason}'**
  String remoteHelperInstallFailed(String host, String reason);

  /// No description provided for @remoteHelperInstallUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This build of ProcessLama has no helper for {host}.'**
  String remoteHelperInstallUnavailable(String host);

  /// No description provided for @remoteHelperRemoveMenu.
  ///
  /// In en, this message translates to:
  /// **'Remove helper from host…'**
  String get remoteHelperRemoveMenu;

  /// No description provided for @remoteHelperRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove helper from {host}?'**
  String remoteHelperRemoveTitle(String host);

  /// No description provided for @remoteHelperRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'ProcessLama disconnects and deletes its helper and caches under ~/.local/lib/processlama and ~/.cache/processlama on this host.'**
  String get remoteHelperRemoveBody;

  /// No description provided for @remoteHelperRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove helper'**
  String get remoteHelperRemoveAction;

  /// No description provided for @remoteHelperRemoved.
  ///
  /// In en, this message translates to:
  /// **'Helper removed from {host}.'**
  String remoteHelperRemoved(String host);

  /// No description provided for @remoteHelperRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the helper from {host}.'**
  String remoteHelperRemoveFailed(String host);

  /// No description provided for @remoteHostConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to {host}. {reason}'**
  String remoteHostConnectFailed(String host, String reason);

  /// No description provided for @remoteHostsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No remote hosts yet. Add one to watch its processes in a tab.'**
  String get remoteHostsEmpty;

  /// No description provided for @remoteHostAdd.
  ///
  /// In en, this message translates to:
  /// **'Add remote host'**
  String get remoteHostAdd;

  /// No description provided for @remoteHostEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get remoteHostEdit;

  /// No description provided for @remoteHostConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get remoteHostConnect;

  /// No description provided for @remoteHostDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get remoteHostDisconnect;

  /// No description provided for @remoteHostDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get remoteHostDuplicate;

  /// No description provided for @remoteHostRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remoteHostRemove;

  /// No description provided for @remoteHostRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {host}?'**
  String remoteHostRemoveTitle(String host);

  /// No description provided for @remoteHostRemoveBody.
  ///
  /// In en, this message translates to:
  /// **'The profile and its tab are removed. The helper stays on the host until you remove it.'**
  String get remoteHostRemoveBody;

  /// No description provided for @remoteHostActions.
  ///
  /// In en, this message translates to:
  /// **'Actions for {host}'**
  String remoteHostActions(String host);

  /// No description provided for @remoteHostLastSeen.
  ///
  /// In en, this message translates to:
  /// **'{platform} · helper {version}'**
  String remoteHostLastSeen(String platform, String version);

  /// No description provided for @remoteHostNeverConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected yet'**
  String get remoteHostNeverConnected;

  /// No description provided for @remoteHostAutoInstallOn.
  ///
  /// In en, this message translates to:
  /// **'Installs the helper automatically'**
  String get remoteHostAutoInstallOn;

  /// No description provided for @remoteHostsDefaultRefresh.
  ///
  /// In en, this message translates to:
  /// **'Default background refresh'**
  String get remoteHostsDefaultRefresh;

  /// No description provided for @remoteIconCache.
  ///
  /// In en, this message translates to:
  /// **'Remote icon cache'**
  String get remoteIconCache;

  /// No description provided for @remoteIconCacheUsage.
  ///
  /// In en, this message translates to:
  /// **'{used} used of {limit}'**
  String remoteIconCacheUsage(String used, String limit);

  /// No description provided for @remoteIconCacheClear.
  ///
  /// In en, this message translates to:
  /// **'Clear icon cache'**
  String get remoteIconCacheClear;

  /// No description provided for @remoteIconCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Icon cache cleared.'**
  String get remoteIconCacheCleared;

  /// No description provided for @remoteTabConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {host}…'**
  String remoteTabConnecting(String host);

  /// No description provided for @remoteTabStaleTitle.
  ///
  /// In en, this message translates to:
  /// **'{host} is not responding'**
  String remoteTabStaleTitle(String host);

  /// No description provided for @remoteTabReconnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to {host}…'**
  String remoteTabReconnectingTitle(String host);

  /// No description provided for @remoteTabStaleMessage.
  ///
  /// In en, this message translates to:
  /// **'Showing data from {time}. {reason}'**
  String remoteTabStaleMessage(String time, String reason);

  /// No description provided for @remoteTabFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to {host}'**
  String remoteTabFailedTitle(String host);

  /// No description provided for @remoteTabReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get remoteTabReconnect;

  /// No description provided for @remoteTabInstallHelper.
  ///
  /// In en, this message translates to:
  /// **'Install helper…'**
  String get remoteTabInstallHelper;

  /// No description provided for @remoteTabHidepid.
  ///
  /// In en, this message translates to:
  /// **'Showing only your processes: this host hides other users\' processes.'**
  String get remoteTabHidepid;

  /// No description provided for @remoteStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'{host} · connected {duration}'**
  String remoteStatusConnected(String host, String duration);

  /// No description provided for @remoteStatusLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'{host} · last updated {time}'**
  String remoteStatusLastUpdated(String host, String time);

  /// No description provided for @remoteStatusRefreshLive.
  ///
  /// In en, this message translates to:
  /// **'refresh: live · {interval}'**
  String remoteStatusRefreshLive(String interval);

  /// No description provided for @remoteStatusRefreshBackground.
  ///
  /// In en, this message translates to:
  /// **'background · {interval}'**
  String remoteStatusRefreshBackground(String interval);

  /// No description provided for @remoteStatusRefreshPaused.
  ///
  /// In en, this message translates to:
  /// **'refresh: paused'**
  String get remoteStatusRefreshPaused;

  /// No description provided for @remoteDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String remoteDurationSeconds(String count);

  /// No description provided for @remoteDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String remoteDurationMinutes(String count);

  /// No description provided for @remoteDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String remoteDurationHours(String hours, String minutes);

  /// No description provided for @remoteTerminateConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Send SIGTERM to \"{name}\" (pid {pid}) on {host}. The process can clean up before exiting.'**
  String remoteTerminateConfirmBody(String name, String pid, String host);

  /// No description provided for @remoteKillConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Send SIGKILL to \"{name}\" (pid {pid}) on {host}. The process stops immediately and cannot clean up.'**
  String remoteKillConfirmBody(String name, String pid, String host);

  /// No description provided for @remoteSuspendConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Send SIGSTOP to \"{name}\" (pid {pid}) on {host}. The process pauses until it is resumed.'**
  String remoteSuspendConfirmBody(String name, String pid, String host);

  /// No description provided for @processSignalDenied.
  ///
  /// In en, this message translates to:
  /// **'Not allowed: the process belongs to another user.'**
  String get processSignalDenied;

  /// No description provided for @processSignalNotFound.
  ///
  /// In en, this message translates to:
  /// **'The process has already exited.'**
  String get processSignalNotFound;

  /// No description provided for @processSignalUnknown.
  ///
  /// In en, this message translates to:
  /// **'The signal may not have arrived. It was not sent again.'**
  String get processSignalUnknown;

  /// No description provided for @remoteCapabilityNetworkMissing.
  ///
  /// In en, this message translates to:
  /// **'Per-process network rates need the ProcessLama network service on this host.'**
  String get remoteCapabilityNetworkMissing;

  /// No description provided for @remoteCapabilityNetworkUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This host cannot report per-process network rates.'**
  String get remoteCapabilityNetworkUnsupported;

  /// No description provided for @remoteCapabilityCopyInstallCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy install command'**
  String get remoteCapabilityCopyInstallCommand;

  /// No description provided for @remoteCapabilityInstallCommandCopied.
  ///
  /// In en, this message translates to:
  /// **'Install command copied. Run it on the host.'**
  String get remoteCapabilityInstallCommandCopied;

  /// No description provided for @remoteHostsProfiles.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get remoteHostsProfiles;

  /// No description provided for @remoteHostConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get remoteHostConnection;

  /// No description provided for @preferencesPageAppearanceDetail.
  ///
  /// In en, this message translates to:
  /// **'How ProcessLama looks and how tightly it packs the process rows.'**
  String get preferencesPageAppearanceDetail;

  /// No description provided for @preferencesPageProcessTree.
  ///
  /// In en, this message translates to:
  /// **'Process tree'**
  String get preferencesPageProcessTree;

  /// No description provided for @preferencesPageProcessTreeDetail.
  ///
  /// In en, this message translates to:
  /// **'How often processes refresh and what the tree remembers.'**
  String get preferencesPageProcessTreeDetail;

  /// No description provided for @preferencesPageColumnsDetail.
  ///
  /// In en, this message translates to:
  /// **'Which columns the process tree shows, and in which order.'**
  String get preferencesPageColumnsDetail;

  /// No description provided for @preferencesPageRemoteHosts.
  ///
  /// In en, this message translates to:
  /// **'Remote hosts'**
  String get preferencesPageRemoteHosts;

  /// No description provided for @preferencesPageRemoteHostsDetail.
  ///
  /// In en, this message translates to:
  /// **'Computers ProcessLama reaches through your SSH configuration, how often their background tabs refresh and how many of their icons it keeps.'**
  String get preferencesPageRemoteHostsDetail;

  /// No description provided for @preferencesPageUpdates.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get preferencesPageUpdates;

  /// No description provided for @preferencesPageUpdatesDetail.
  ///
  /// In en, this message translates to:
  /// **'Which ProcessLama builds the updater offers you.'**
  String get preferencesPageUpdatesDetail;

  /// No description provided for @preferencesTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get preferencesTheme;

  /// No description provided for @searchAspect.
  ///
  /// In en, this message translates to:
  /// **'Search aspect'**
  String get searchAspect;

  /// No description provided for @searchAll.
  ///
  /// In en, this message translates to:
  /// **'Process text'**
  String get searchAll;

  /// No description provided for @searchName.
  ///
  /// In en, this message translates to:
  /// **'Process name'**
  String get searchName;

  /// No description provided for @searchPid.
  ///
  /// In en, this message translates to:
  /// **'Process ID'**
  String get searchPid;

  /// No description provided for @searchUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get searchUser;

  /// No description provided for @searchCommand.
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get searchCommand;

  /// No description provided for @searchPath.
  ///
  /// In en, this message translates to:
  /// **'Executable path'**
  String get searchPath;

  /// No description provided for @searchPort.
  ///
  /// In en, this message translates to:
  /// **'Local port'**
  String get searchPort;

  /// No description provided for @searchPortHint.
  ///
  /// In en, this message translates to:
  /// **'Local port (e.g. 8080)'**
  String get searchPortHint;

  /// No description provided for @occupiedPorts.
  ///
  /// In en, this message translates to:
  /// **'Occupied ports'**
  String get occupiedPorts;

  /// No description provided for @localPorts.
  ///
  /// In en, this message translates to:
  /// **'Local TCP / UDP ports'**
  String get localPorts;

  /// No description provided for @portsNotReported.
  ///
  /// In en, this message translates to:
  /// **'No ports reported (none or access restricted)'**
  String get portsNotReported;

  /// No description provided for @noOccupiedPorts.
  ///
  /// In en, this message translates to:
  /// **'No occupied ports'**
  String get noOccupiedPorts;

  /// No description provided for @localPortsExplanation.
  ///
  /// In en, this message translates to:
  /// **'Listening ports accept connections: TCP listeners and UDP sockets on well-known ports (below 1024). Other local ports are mostly outgoing connections. Select a port to show every process using it. Permissions may hide ports owned by other users.'**
  String get localPortsExplanation;

  /// No description provided for @listeningPorts.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get listeningPorts;

  /// No description provided for @listeningPortsLabel.
  ///
  /// In en, this message translates to:
  /// **'Listening ports'**
  String get listeningPortsLabel;

  /// No description provided for @otherLocalPorts.
  ///
  /// In en, this message translates to:
  /// **'Other local ports'**
  String get otherLocalPorts;

  /// No description provided for @showPortProcesses.
  ///
  /// In en, this message translates to:
  /// **'Show processes using port {port}'**
  String showPortProcesses(int port);

  /// A process listening on the port a socket connects to.
  ///
  /// In en, this message translates to:
  /// **'{name} ({pid})'**
  String goToPortOwner(String name, int pid);

  /// No description provided for @goToPortOwnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Go to {name}, PID {pid}, listening on port {port}'**
  String goToPortOwnerLabel(String name, int pid, int port);

  /// No description provided for @columnPorts.
  ///
  /// In en, this message translates to:
  /// **'Ports'**
  String get columnPorts;

  /// No description provided for @socketPeers.
  ///
  /// In en, this message translates to:
  /// **'Local processes these sockets connect to'**
  String get socketPeers;

  /// User-controlled diagnostic capture and export: diagnosticsTitle
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// User-controlled diagnostic capture and export: diagnosticsDescription
  ///
  /// In en, this message translates to:
  /// **'Recent safe events stay in memory only (up to 1,000 events or 256 KiB). Detailed capture lasts up to 15 minutes or until the session ends. No credentials or private content are included. Preview before saving or sharing. Nothing is uploaded automatically. Clear history does not remove copies you saved or shared.'**
  String get diagnosticsDescription;

  /// User-controlled diagnostic capture and export: diagnosticsEnable
  ///
  /// In en, this message translates to:
  /// **'Enable detailed diagnostics for 15 minutes'**
  String get diagnosticsEnable;

  /// User-controlled diagnostic capture and export: diagnosticsDisable
  ///
  /// In en, this message translates to:
  /// **'Detailed diagnostics active — stop recording details'**
  String get diagnosticsDisable;

  /// User-controlled diagnostic capture and export: diagnosticsClear
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get diagnosticsClear;

  /// User-controlled diagnostic capture and export: diagnosticsPreview
  ///
  /// In en, this message translates to:
  /// **'Preview export'**
  String get diagnosticsPreview;

  /// User-controlled diagnostic capture and export: diagnosticsCancel
  ///
  /// In en, this message translates to:
  /// **'Close preview'**
  String get diagnosticsCancel;

  /// User-controlled diagnostic capture and export: diagnosticsSave
  ///
  /// In en, this message translates to:
  /// **'Save to file'**
  String get diagnosticsSave;

  /// User-controlled diagnostic capture and export: diagnosticsShare
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get diagnosticsShare;

  /// User-controlled diagnostic capture and export: diagnosticsFailed
  ///
  /// In en, this message translates to:
  /// **'Could not export diagnostics. Try another destination.'**
  String get diagnosticsFailed;

  /// User-controlled diagnostic capture and export: diagnosticsSaved
  ///
  /// In en, this message translates to:
  /// **'Diagnostics saved.'**
  String get diagnosticsSaved;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
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
