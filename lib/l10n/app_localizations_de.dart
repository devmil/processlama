// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'ProcessLama';

  @override
  String get processExplorer => 'Prozess-Explorer';

  @override
  String get hideInspector => 'Inspektor ausblenden';

  @override
  String get showInspector => 'Inspektor anzeigen';

  @override
  String get checkForUpdates => 'Nach Updates suchen';

  @override
  String updateCheckFailed(String error) {
    return 'Update-Suche fehlgeschlagen: $error';
  }

  @override
  String updateUpToDate(String version, String build) {
    return 'ProcessLama $version (Build $build) ist aktuell.';
  }

  @override
  String get updateNoPublishedRelease =>
      'Für diesen Kanal ist noch keine Version veröffentlicht.';

  @override
  String updateAvailableTitle(String version) {
    return 'ProcessLama $version ist verfügbar';
  }

  @override
  String updateAvailableBody(
    String installedVersion,
    String installedBuild,
    String availableBuild,
  ) {
    return 'Installiert ist $installedVersion (Build $installedBuild). Build $availableBuild steht auf der Download-Seite bereit.';
  }

  @override
  String get later => 'Später';

  @override
  String get openDownloads => 'Downloads öffnen';

  @override
  String get updateDownloadOpenFailed =>
      'Die Download-Seite konnte nicht geöffnet werden.';

  @override
  String focusedOnSubtree(String name) {
    return 'Fokussiert auf $name';
  }

  @override
  String get subtree => 'Teilbaum';

  @override
  String get leaveSubtreeFocus => 'Teilbaum-Fokus verlassen';

  @override
  String get backOneSubtree => 'Einen Teilbaum zurück';

  @override
  String get showFullTree => 'Gesamten Baum anzeigen';

  @override
  String get pollingInterval => 'Abfrageintervall';

  @override
  String get searchHint => 'Name, PID, Pfad oder :Port suchen';

  @override
  String get clearSearch => 'Suche löschen';

  @override
  String get previousSearchMatch => 'Vorheriger Treffer';

  @override
  String get nextSearchMatch => 'Nächster Treffer';

  @override
  String get matchCase => 'Groß-/Kleinschreibung beachten';

  @override
  String get wholeWord => 'Ganzes Wort';

  @override
  String get saveCurrentFilter => 'Aktuellen Filter speichern';

  @override
  String get savedFilters => 'Gespeicherte Filter';

  @override
  String get unlockProcessTree => 'Prozessbaum entsperren';

  @override
  String get lockProcessTree => 'Prozessbaum sperren';

  @override
  String get refreshProcessSnapshot => 'Prozess-Schnappschuss aktualisieren';

  @override
  String get takeSnapshot => 'Schnappschuss aufnehmen';

  @override
  String get openSnapshot => 'Schnappschuss öffnen…';

  @override
  String get preferences => 'Einstellungen';

  @override
  String processCount(String count) {
    return '$count Prozesse';
  }

  @override
  String queuedCount(String count) {
    return ' - $count in Warteschlange';
  }

  @override
  String get columnPid => 'PID';

  @override
  String get columnName => 'Name';

  @override
  String get columnCpu => 'CPU';

  @override
  String get columnTreeCpu => 'Baum-CPU';

  @override
  String get columnGpu => 'GPU';

  @override
  String get columnTreeGpu => 'Baum-GPU';

  @override
  String get columnRss => 'RSS';

  @override
  String get columnTreeRss => 'Baum-RSS';

  @override
  String get columnNetIn => 'Netzeingang';

  @override
  String get columnNetOut => 'Netzausgang';

  @override
  String get columnTreeNetIn => 'Baum-Netzeingang';

  @override
  String get columnTreeNetOut => 'Baum-Netzausgang';

  @override
  String get columnStorageRead => 'Lesedurchsatz';

  @override
  String get columnStorageWrite => 'Schreibdurchsatz';

  @override
  String get columnTreeStorageRead => 'Baum-Lesedurchsatz';

  @override
  String get columnTreeStorageWrite => 'Baum-Schreibdurchsatz';

  @override
  String get columnStarted => 'Gestartet';

  @override
  String get columnState => 'Status';

  @override
  String get columnUid => 'UID';

  @override
  String get showAllColumns => 'Alle Spalten anzeigen';

  @override
  String get resetColumnOrder => 'Spaltenreihenfolge zurücksetzen';

  @override
  String get noProcessesMatchFilter => 'Nichts entspricht diesem Filter.';

  @override
  String get liveOrderingPausedTooltip =>
      'Live-Sortierung ist pausiert, solange der Zeiger über dem Baum ist';

  @override
  String get liveOrderingPaused => 'Live-Sortierung pausiert';

  @override
  String get collapse => 'Einklappen';

  @override
  String get expand => 'Ausklappen';

  @override
  String get unpinProcess => 'Prozess lösen';

  @override
  String get pinProcess => 'Prozess anheften';

  @override
  String get spawned => 'Gestartet';

  @override
  String get terminated => 'Beendet';

  @override
  String get unpinProcessMenu => 'Prozess lösen';

  @override
  String get pinProcessMenu => 'Prozess anheften';

  @override
  String get focusSubtree => 'Teilbaum fokussieren';

  @override
  String get expandSubtree => 'Teilbaum ausklappen';

  @override
  String get collapseSubtree => 'Teilbaum einklappen';

  @override
  String get terminateProcessMenu => 'Prozess beenden';

  @override
  String get killProcessMenu => 'Prozess sofort beenden';

  @override
  String get suspendProcessMenu => 'Prozess anhalten';

  @override
  String get resumeProcessMenu => 'Prozess fortsetzen';

  @override
  String get processTerminated => 'Signal zum Beenden gesendet.';

  @override
  String get processKilled => 'Signal zum sofortigen Beenden gesendet.';

  @override
  String get processSuspended => 'Signal zum Anhalten gesendet.';

  @override
  String get processResumed => 'Signal zum Fortsetzen gesendet.';

  @override
  String processActionFailed(String error) {
    return 'Prozessaktion fehlgeschlagen: $error';
  }

  @override
  String get processActionConfirmCancel => 'Abbrechen';

  @override
  String get terminateConfirmTitle => 'Prozess beenden?';

  @override
  String terminateConfirmBody(String name, String pid) {
    return 'SIGTERM an „$name“ (PID $pid) senden. Der Prozess kann vor dem Beenden noch aufräumen.';
  }

  @override
  String get killConfirmTitle => 'Prozess sofort beenden?';

  @override
  String killConfirmBody(String name, String pid) {
    return 'SIGKILL an „$name“ (PID $pid) senden. Der Prozess wird sofort beendet; dabei können Daten in einem inkonsistenten Zustand zurückbleiben.';
  }

  @override
  String get suspendConfirmTitle => 'Prozess anhalten?';

  @override
  String suspendConfirmBody(String name, String pid) {
    return 'SIGSTOP an „$name“ (PID $pid) senden. Der Prozess pausiert, bis er fortgesetzt wird.';
  }

  @override
  String copyPid(String pid) {
    return 'PID $pid kopieren';
  }

  @override
  String copyName(String name) {
    return '$name kopieren';
  }

  @override
  String get copyExecutablePath => 'Pfad der ausführbaren Datei kopieren';

  @override
  String get rememberTreeExpansion => 'Ausgeklappte Zweige merken';

  @override
  String get rowHeatmap => 'CPU-Zeilen-Heatmap';

  @override
  String get rowDensity => 'Zeilendichte';

  @override
  String get rowDensityCompact => 'Kompakt';

  @override
  String get rowDensityRegular => 'Normal';

  @override
  String get rowDensityComfortable => 'Großzügig';

  @override
  String get releaseChannel => 'Release-Kanal';

  @override
  String get releaseChannelStable => 'Stabil';

  @override
  String get releaseChannelBeta => 'Beta';

  @override
  String get system => 'System';

  @override
  String get light => 'Hell';

  @override
  String get dark => 'Dunkel';

  @override
  String get close => 'Schließen';

  @override
  String get columns => 'Spalten';

  @override
  String get moveColumnEarlier => 'Spalte nach oben verschieben';

  @override
  String get moveColumnLater => 'Spalte nach unten verschieben';

  @override
  String pollingIntervalLabel(String value) {
    return 'Abfrageintervall: $value ms';
  }

  @override
  String get unknown => 'Unbekannt';

  @override
  String get inspector => 'Inspektor';

  @override
  String get noProcessSelected => 'Kein Prozess ausgewählt';

  @override
  String pidPlatform(String pid, String platform) {
    return 'PID $pid · $platform';
  }

  @override
  String get tabOverview => 'Übersicht';

  @override
  String get tabDetails => 'Details';

  @override
  String get tabFiles => 'Dateien';

  @override
  String get tabSockets => 'Sockets';

  @override
  String get tabFilesAndSockets => 'Dateien & Sockets';

  @override
  String get tabNetwork => 'Netzwerk';

  @override
  String get tabThreads => 'Threads';

  @override
  String get tabSecurity => 'Sicherheit';

  @override
  String get networkIn => 'Netzwerkeingang';

  @override
  String get networkOut => 'Netzwerkausgang';

  @override
  String get totalIn => 'Eingang gesamt';

  @override
  String get totalOut => 'Ausgang gesamt';

  @override
  String get treeNetworkIn => 'Baum-Netzwerkeingang';

  @override
  String get treeNetworkOut => 'Baum-Netzwerkausgang';

  @override
  String get storageRead => 'Lesedurchsatz';

  @override
  String get storageWrite => 'Schreibdurchsatz';

  @override
  String get totalStorageRead => 'Insgesamt gelesen';

  @override
  String get totalStorageWrite => 'Insgesamt geschrieben';

  @override
  String get storageHistory => 'Speicherverlauf';

  @override
  String get networkHistory => 'Netzwerkverlauf';

  @override
  String get networkOutIn => 'Ausgang / Eingang';

  @override
  String get storageReadWrite => 'Lesen / Schreiben';

  @override
  String get overviewMemory => 'Arbeitsspeicher';

  @override
  String get overviewStorage => 'Speicher';

  @override
  String get metricUnavailable => 'Nicht verfügbar';

  @override
  String get tree => 'Baum';

  @override
  String get processScope => 'Prozess';

  @override
  String get descendants => 'Nachkommen';

  @override
  String get parentPid => 'Eltern-PID';

  @override
  String get userId => 'Benutzer-ID';

  @override
  String get status => 'Status';

  @override
  String get threads => 'Threads';

  @override
  String get openFiles => 'Offene Dateien';

  @override
  String get virtualMemory => 'Virtueller Speicher';

  @override
  String get nice => 'Nice';

  @override
  String get priority => 'Priorität';

  @override
  String get summary => 'Zusammenfassung';

  @override
  String get signing => 'Signatur';

  @override
  String get authority => 'Zertifizierungsstelle';

  @override
  String get teamId => 'Team-ID';

  @override
  String get bundleId => 'Bundle-ID';

  @override
  String get entitlements => 'Berechtigungen';

  @override
  String get origin => 'Herkunft';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get hardenedRuntime => 'Hardened RT';

  @override
  String get architecture => 'Architektur';

  @override
  String get rosetta => 'Rosetta';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get noPathAvailable => '-';

  @override
  String get noOpenFilesReported =>
      'Für diesen Prozess wurden keine offenen Dateien gemeldet.';

  @override
  String get openFilesTruncated =>
      'Es werden die ersten 500 offenen Dateien angezeigt.';

  @override
  String get noSocketsReported =>
      'Für diesen Prozess wurden keine Sockets gemeldet.';

  @override
  String get noThreadsReported =>
      'Für diesen Prozess wurden keine Threads gemeldet.';

  @override
  String get noSecurityMetadataReported =>
      'Für diesen Prozess wurden keine Sicherheits-Metadaten gemeldet.';

  @override
  String restrictedByMacos(String reason) {
    return 'Eingeschränkter Zugriff: $reason';
  }

  @override
  String get gpu => 'GPU';

  @override
  String get netIn => 'Netzeingang';

  @override
  String get netOut => 'Netzausgang';

  @override
  String get identity => 'Identität';

  @override
  String get executable => 'Ausführbare Datei';

  @override
  String get applicationBundle => 'Anwendungspaket';

  @override
  String get commandLine => 'Befehlszeile';

  @override
  String get pinned => 'Angeheftet';

  @override
  String get pinRowsForQuickAccess => 'Zeilen für schnellen Zugriff anheften.';

  @override
  String get snapshots => 'Schnappschüsse';

  @override
  String livePlatform(String platform) {
    return 'Live · $platform';
  }

  @override
  String get now => 'jetzt';

  @override
  String get filters => 'Filter';

  @override
  String pollingStatus(String interval) {
    return 'Abfrage alle $interval ms';
  }

  @override
  String exportedPath(String path) {
    return 'Exportiert nach $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get exportSnapshot => 'Schnappschuss exportieren…';

  @override
  String get renameSnapshot => 'Schnappschuss umbenennen…';

  @override
  String get renameSnapshotTitle => 'Schnappschuss umbenennen';

  @override
  String get snapshotName => 'Schnappschussname';

  @override
  String get deleteSnapshot => 'Schnappschuss löschen';

  @override
  String get deleteFilter => 'Filter löschen';

  @override
  String get snapshotTaken => 'Schnappschuss aufgenommen';

  @override
  String snapshotFailed(String error) {
    return 'Schnappschuss fehlgeschlagen: $error';
  }

  @override
  String get snapshotLoaded => 'Schnappschuss geladen';

  @override
  String snapshotLoadFailed(String error) {
    return 'Laden fehlgeschlagen: $error';
  }

  @override
  String get snapshotDeleted => 'Schnappschuss gelöscht';

  @override
  String get snapshotRenamed => 'Schnappschuss umbenannt';

  @override
  String snapshotRenameFailed(String error) {
    return 'Umbenennen fehlgeschlagen: $error';
  }

  @override
  String snapshotDeleteFailed(String error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get bootstrapErrorTitle =>
      'ProcessLama konnte den Start nicht abschließen.';

  @override
  String get bootstrapErrorDescription =>
      'Das App-Fenster läuft, aber einer der Startdienste ist fehlgeschlagen.';

  @override
  String get featureProcessEnumeration => 'Prozessaufzählung';

  @override
  String get featureProcessTreeSynthesis => 'Aufbau des Prozessbaums';

  @override
  String get featureFilesAndSockets => 'Dateien und Sockets';

  @override
  String get featureNetworkThroughput => 'Netzwerkdurchsatz';

  @override
  String get featureSecurityMetadata => 'Sicherheits-Metadaten';

  @override
  String get featureRestrictedProcessHints =>
      'Hinweise zu eingeschränkten Prozessen';

  @override
  String get featureSnapshotDocuments => 'Schnappschuss-Dokumente';

  @override
  String get noSavedFilters => 'Keine gespeicherten Filter.';

  @override
  String get statusTreeLocked => 'Prozessbaum gesperrt';

  @override
  String get toolbarLock => 'Sperren';

  @override
  String get toolbarSnapshot => 'Schnappschuss';

  @override
  String get toolbarUpdates => 'Updates';

  @override
  String get snapshotOptions => 'Weitere Schnappschuss-Optionen';

  @override
  String get appearance => 'Darstellung';

  @override
  String get selectProcessToInspect =>
      'Wähle einen Prozess aus, um ihn zu untersuchen.';

  @override
  String get selectProcessToInspectNetwork =>
      'Wähle einen Prozess aus, um seinen Netzwerkdurchsatz zu untersuchen.';

  @override
  String bootstrapModeMessage(String error) {
    return 'Startmodus: $error';
  }

  @override
  String get sortedAscending => 'aufsteigend sortiert';

  @override
  String get sortedDescending => 'absteigend sortiert';

  @override
  String get resizeInspector => 'Inspektorbreite ändern';

  @override
  String get morePreferencesOptions => 'Weitere Einstellungen';

  @override
  String get minimizeWindow => 'Fenster minimieren';

  @override
  String get maximizeWindow => 'Fenster maximieren oder wiederherstellen';

  @override
  String get closeWindow => 'Fenster schließen';

  @override
  String get installNetworkTelemetry => 'Netzwerk-Telemetrie installieren…';

  @override
  String get networkTelemetryInstallDescription =>
      'Für die Netzwerkaktivität unter Linux ist ein Systemdienst erforderlich. Die Installation oder Reparatur benötigt Administratorrechte und aktiviert den Netzwerkdurchsatz pro Prozess für alle Benutzer dieses Rechners.';

  @override
  String get networkTelemetryUnavailable =>
      'Netzwerk-Telemetrie nicht verfügbar';

  @override
  String get networkTelemetryUnavailableDescription =>
      'Der Linux-Netzwerkdienst fehlt oder wurde beendet. Installiere oder repariere ihn, um die Netzwerkaktivität live zu sehen.';

  @override
  String get networkTelemetryInstalled =>
      'Netzwerkdienst installiert und gestartet.';

  @override
  String get networkTelemetryInstallerMissing =>
      'Dieser Build enthält keinen Netzwerkdienst. Installiere ein aktuelles ProcessLama-Paket oder ein portables Bundle.';

  @override
  String get networkTelemetryAuthorizationUnavailable =>
      'Systemautorisierung ist nicht verfügbar. Installiere das DEB- oder RPM-Paket, um die Netzwerk-Telemetrie zu aktivieren.';

  @override
  String get networkTelemetryAuthorizationCancelled =>
      'Die Installation des Netzwerkdienstes wurde abgebrochen.';

  @override
  String get networkTelemetryInstallFailed =>
      'Die Installation des Netzwerkdienstes ist fehlgeschlagen. Prüfe das Systemjournal für processlama-network.service.';

  @override
  String searchMatchPosition(String current, String count) {
    return 'Treffer $current von $count';
  }

  @override
  String get aboutApp => 'Über ProcessLama';

  @override
  String get makerLine => 'by Devmil Solutions';

  @override
  String get brandTooltip => 'ProcessLama · by Devmil Solutions';

  @override
  String get aboutProductName => 'ProcessLama';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version · Build $build';
  }

  @override
  String get lamaFamily => 'Die Lama-Familie';

  @override
  String get closeAbout => 'Schließen';

  @override
  String get aboutLicenses => 'Lizenzen';

  @override
  String get filterNoMatchesHelp =>
      'Versuch es mit einem allgemeineren Namen oder entferne den CPU-Schwellenwert.';

  @override
  String get remoteTabLocal => 'Lokal';

  @override
  String get remoteTabOpenMenu => 'Entfernten Host öffnen';

  @override
  String remoteTabClose(String tab) {
    return '$tab schließen';
  }

  @override
  String get remoteTabMoveLeft => 'Tab nach links verschieben';

  @override
  String get remoteTabMoveRight => 'Tab nach rechts verschieben';

  @override
  String get remoteTabMore => 'Alle Tabs';

  @override
  String remoteTabTooltip(String alias, String platform, String version) {
    return '$alias · $platform · Helfer $version';
  }

  @override
  String remoteTabSemantics(String name, String status) {
    return '$name, $status';
  }

  @override
  String remoteTabLimit(String count) {
    return 'Du kannst bis zu $count entfernte Tabs öffnen.';
  }

  @override
  String get remoteHostAddMenu => 'Entfernten Host hinzufügen …';

  @override
  String get remoteHostManageMenu => 'Entfernte Hosts verwalten …';

  @override
  String get remoteHostMenuEmpty => 'Keine weiteren gespeicherten Hosts';

  @override
  String get remotePhaseIdle => 'Nicht verbunden';

  @override
  String get remotePhaseConnecting => 'Verbindet';

  @override
  String get remotePhaseInstalling => 'Installiert Helfer';

  @override
  String get remotePhaseLive => 'Verbunden';

  @override
  String get remotePhaseReconnecting => 'Verbindet erneut';

  @override
  String get remotePhaseDisconnected => 'Getrennt';

  @override
  String get remotePhaseFailed => 'Fehlgeschlagen';

  @override
  String get remoteFailureSshMissing =>
      'OpenSSH ist auf diesem Computer nicht installiert.';

  @override
  String get remoteFailureSshTooOld =>
      'OpenSSH auf diesem Computer ist älter als 8.9.';

  @override
  String get remoteFailureSshConnectionFailed =>
      'SSH konnte keine Verbindung aufbauen. Prüfe den Host, das Netzwerk und deine ~/.ssh/config.';

  @override
  String get remoteFailureHostKeyUntrusted =>
      'Dem Host-Schlüssel wird noch nicht vertraut. Verbinde dich einmal mit ssh in einem Terminal.';

  @override
  String get remoteFailureAuthenticationInteractive =>
      'SSH fragt nach einem Passwort oder einer Bestätigung. Richte eine Anmeldung per Schlüssel oder einen Agent ein.';

  @override
  String get remoteFailureUnsupportedPlatform =>
      'Das System dieses Hosts wird nicht unterstützt.';

  @override
  String get remoteFailureHelperNotInstalled =>
      'Der ProcessLama-Helfer ist auf diesem Host nicht installiert.';

  @override
  String get remoteFailureHelperOutdated =>
      'Der Helfer auf diesem Host ist veraltet.';

  @override
  String get remoteFailureHelperDamaged =>
      'Der Helfer auf diesem Host ist beschädigt.';

  @override
  String get remoteFailureHelperStartFailed =>
      'Der Helfer ist nicht gestartet. Möglicherweise gibt ein Login-Skript Text aus oder liest Eingaben.';

  @override
  String get remoteFailureInstallFailed =>
      'Die Installation des Helfers ist fehlgeschlagen.';

  @override
  String get remoteFailureInstallNoSpace =>
      'Auf dem Host ist kein Platz mehr für den Helfer.';

  @override
  String get remoteFailureInstallNoexec =>
      'Das Home-Verzeichnis auf diesem Host erlaubt keine Programme (noexec).';

  @override
  String get remoteFailureInstallRefused =>
      'Das Installationsverzeichnis ist unsicher: ein symbolischer Link oder ein Verzeichnis eines anderen Benutzers.';

  @override
  String get remoteFailureProtocolMismatch =>
      'Der Helfer spricht eine andere Protokollversion.';

  @override
  String get remoteFailureHeartbeatLost => 'Der Host antwortet nicht mehr.';

  @override
  String get remoteFailureFrameTooLarge =>
      'Der Host hat mehr Daten gesendet als erlaubt.';

  @override
  String get remoteFailureRemoteRestricted =>
      'Der Host hat die Anfrage abgelehnt.';

  @override
  String get remoteFailureCanceled => 'Abgebrochen.';

  @override
  String get remoteFailureInternal =>
      'Ein unerwarteter Fehler ist aufgetreten.';

  @override
  String get remoteHostProbeSshUnreachable => 'SSH nicht erreichbar';

  @override
  String get remoteHostProbeHostKeyUntrusted =>
      'Host-Schlüssel nicht vertrauenswürdig';

  @override
  String get remoteHostProbeAuthenticationInteractive =>
      'Anmeldung erfordert eine Eingabe';

  @override
  String get remoteHostProbeUnsupportedPlatform =>
      'Nicht unterstützte Plattform';

  @override
  String get remoteHostProbeHelperMissing => 'Helfer fehlt';

  @override
  String get remoteHostProbeHelperOutdated => 'Helfer veraltet';

  @override
  String remoteHostProbeReady(String platform, String version) {
    return 'Bereit: $platform, Helfer $version';
  }

  @override
  String get remoteHostProbeRunning => 'Teste die Verbindung …';

  @override
  String get remoteHostEditorAddTitle => 'Entfernten Host hinzufügen';

  @override
  String get remoteHostEditorEditTitle => 'Entfernten Host bearbeiten';

  @override
  String get remoteHostDisplayName => 'Anzeigename';

  @override
  String get remoteHostAlias => 'SSH-Host-Alias';

  @override
  String get remoteHostAliasHelp =>
      'Ein Host-Eintrag deiner ~/.ssh/config. Benutzernamen, Ports, Schlüssel und Jump-Hosts gehören dorthin; ProcessLama speichert nur den Alias.';

  @override
  String get remoteHostAliasInvalid =>
      'Verwende Buchstaben, Ziffern, Punkte, Binde- und Unterstriche; beginne mit einem Buchstaben oder einer Ziffer.';

  @override
  String get remoteHostDisplayNameInvalid => 'Verwende 1 bis 64 Zeichen.';

  @override
  String get remoteHostAutoInstall => 'Helfer automatisch installieren';

  @override
  String get remoteHostAutoReconnect => 'Automatisch neu verbinden';

  @override
  String get remoteHostOpenOnStartup => 'Beim Start öffnen';

  @override
  String get remoteHostOpenOnStartupRemember => 'Wie beim Beenden';

  @override
  String get remoteHostOpenOnStartupAlways => 'Immer';

  @override
  String get remoteHostOpenOnStartupNever => 'Nie';

  @override
  String get remoteHostBackgroundRefresh => 'Aktualisierung im Hintergrund';

  @override
  String get remoteHostBackgroundRefreshDefault => 'Standard';

  @override
  String get remoteRefreshSlow => 'Langsam (5 s)';

  @override
  String get remoteRefreshLive => 'Live';

  @override
  String get remoteRefreshPaused => 'Pausiert';

  @override
  String get remoteHostTestConnection => 'Verbindung testen';

  @override
  String get remoteHostSetupGuide => 'Einrichtungsanleitung';

  @override
  String get remoteHostSave => 'Speichern';

  @override
  String get remoteHostCancel => 'Abbrechen';

  @override
  String get remoteHostSaveFailed =>
      'Der entfernte Host konnte nicht gespeichert werden.';

  @override
  String get remoteHostTooMany =>
      'Du hast die maximale Anzahl entfernter Hosts erreicht.';

  @override
  String remoteHelperInstallTitle(String host) {
    return 'Helfer auf $host installieren?';
  }

  @override
  String remoteHelperUpdateTitle(String host) {
    return 'Helfer auf $host aktualisieren?';
  }

  @override
  String get remoteHelperInstallBody =>
      'ProcessLama kopiert ein kleines Hilfsprogramm auf diesen Host und führt es als dein SSH-Benutzer aus. Es verwendet nie sudo.';

  @override
  String get remoteHelperInstallPath => 'Pfad';

  @override
  String get remoteHelperInstallVersion => 'Version';

  @override
  String get remoteHelperInstallSize => 'Größe';

  @override
  String get remoteHelperInstallChecksum => 'SHA-256';

  @override
  String get remoteHelperInstallAction => 'Installieren';

  @override
  String get remoteHelperInstallAlways =>
      'Installieren und für diesen Host immer installieren';

  @override
  String get remoteHelperUpdateAction => 'Aktualisieren';

  @override
  String get remoteHelperUpdateAlways =>
      'Aktualisieren und für diesen Host immer installieren';

  @override
  String remoteHelperInstalled(String host) {
    return 'Helfer auf $host installiert.';
  }

  @override
  String remoteHelperInstallFailed(String host, String reason) {
    return 'Der Helfer konnte nicht auf $host installiert werden. $reason';
  }

  @override
  String remoteHelperInstallUnavailable(String host) {
    return 'Dieser Build von ProcessLama enthält keinen Helfer für $host.';
  }

  @override
  String get remoteHelperRemoveMenu => 'Helfer vom Host entfernen …';

  @override
  String remoteHelperRemoveTitle(String host) {
    return 'Helfer von $host entfernen?';
  }

  @override
  String get remoteHelperRemoveBody =>
      'ProcessLama trennt die Verbindung und löscht seinen Helfer und seine Caches unter ~/.local/lib/processlama und ~/.cache/processlama auf diesem Host.';

  @override
  String get remoteHelperRemoveAction => 'Helfer entfernen';

  @override
  String remoteHelperRemoved(String host) {
    return 'Helfer von $host entfernt.';
  }

  @override
  String remoteHelperRemoveFailed(String host) {
    return 'Der Helfer konnte nicht von $host entfernt werden.';
  }

  @override
  String remoteHostConnectFailed(String host, String reason) {
    return 'Keine Verbindung zu $host. $reason';
  }

  @override
  String get remoteHostsEmpty =>
      'Noch keine entfernten Hosts. Füge einen hinzu, um seine Prozesse in einem Tab zu sehen.';

  @override
  String get remoteHostAdd => 'Entfernten Host hinzufügen';

  @override
  String get remoteHostEdit => 'Bearbeiten';

  @override
  String get remoteHostConnect => 'Verbinden';

  @override
  String get remoteHostDisconnect => 'Trennen';

  @override
  String get remoteHostDuplicate => 'Duplizieren';

  @override
  String get remoteHostRemove => 'Entfernen';

  @override
  String remoteHostRemoveTitle(String host) {
    return '$host entfernen?';
  }

  @override
  String get remoteHostRemoveBody =>
      'Das Profil und sein Tab werden entfernt. Der Helfer bleibt auf dem Host, bis du ihn entfernst.';

  @override
  String remoteHostActions(String host) {
    return 'Aktionen für $host';
  }

  @override
  String remoteHostLastSeen(String platform, String version) {
    return '$platform · Helfer $version';
  }

  @override
  String get remoteHostNeverConnected => 'Noch nicht verbunden';

  @override
  String get remoteHostAutoInstallOn => 'Installiert den Helfer automatisch';

  @override
  String get remoteHostsDefaultRefresh =>
      'Standard-Aktualisierung im Hintergrund';

  @override
  String get remoteIconCache => 'Cache für entfernte Icons';

  @override
  String remoteIconCacheUsage(String used, String limit) {
    return '$used von $limit belegt';
  }

  @override
  String get remoteIconCacheClear => 'Icon-Cache leeren';

  @override
  String get remoteIconCacheCleared => 'Icon-Cache geleert.';

  @override
  String remoteTabConnecting(String host) {
    return 'Verbinde mit $host …';
  }

  @override
  String remoteTabStaleTitle(String host) {
    return '$host antwortet nicht';
  }

  @override
  String remoteTabReconnectingTitle(String host) {
    return 'Verbinde erneut mit $host …';
  }

  @override
  String remoteTabStaleMessage(String time, String reason) {
    return 'Zeige Daten von $time. $reason';
  }

  @override
  String remoteTabFailedTitle(String host) {
    return 'Keine Verbindung zu $host';
  }

  @override
  String get remoteTabReconnect => 'Neu verbinden';

  @override
  String get remoteTabInstallHelper => 'Helfer installieren …';

  @override
  String get remoteTabHidepid =>
      'Nur deine Prozesse werden angezeigt: Dieser Host verbirgt die Prozesse anderer Benutzer.';

  @override
  String remoteStatusConnected(String host, String duration) {
    return '$host · verbunden seit $duration';
  }

  @override
  String remoteStatusLastUpdated(String host, String time) {
    return '$host · zuletzt aktualisiert $time';
  }

  @override
  String remoteStatusRefreshLive(String interval) {
    return 'Aktualisierung: live · $interval';
  }

  @override
  String remoteStatusRefreshBackground(String interval) {
    return 'Hintergrund · $interval';
  }

  @override
  String get remoteStatusRefreshPaused => 'Aktualisierung: pausiert';

  @override
  String remoteDurationSeconds(String count) {
    return '$count s';
  }

  @override
  String remoteDurationMinutes(String count) {
    return '$count min';
  }

  @override
  String remoteDurationHours(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String remoteTerminateConfirmBody(String name, String pid, String host) {
    return 'SIGTERM an „$name“ (PID $pid) auf $host senden. Der Prozess kann vor dem Beenden noch aufräumen.';
  }

  @override
  String remoteKillConfirmBody(String name, String pid, String host) {
    return 'SIGKILL an „$name“ (PID $pid) auf $host senden. Der Prozess stoppt sofort und kann nicht aufräumen.';
  }

  @override
  String remoteSuspendConfirmBody(String name, String pid, String host) {
    return 'SIGSTOP an „$name“ (PID $pid) auf $host senden. Der Prozess pausiert, bis er fortgesetzt wird.';
  }

  @override
  String get processSignalDenied =>
      'Nicht erlaubt: Der Prozess gehört einem anderen Benutzer.';

  @override
  String get processSignalNotFound => 'Der Prozess wurde bereits beendet.';

  @override
  String get processSignalUnknown =>
      'Das Signal ist möglicherweise nicht angekommen. Es wurde nicht erneut gesendet.';

  @override
  String get remoteCapabilityNetworkMissing =>
      'Netzwerkwerte pro Prozess brauchen den ProcessLama-Netzwerkdienst auf diesem Host.';

  @override
  String get remoteCapabilityNetworkUnsupported =>
      'Dieser Host kann keine Netzwerkwerte pro Prozess liefern.';

  @override
  String get remoteCapabilityCopyInstallCommand =>
      'Installationsbefehl kopieren';

  @override
  String get remoteCapabilityInstallCommandCopied =>
      'Installationsbefehl kopiert. Führe ihn auf dem Host aus.';

  @override
  String get remoteHostsProfiles => 'Hosts';

  @override
  String get remoteHostConnection => 'Verbindung';

  @override
  String get preferencesPageAppearanceDetail =>
      'Wie ProcessLama aussieht und wie dicht es die Prozesszeilen setzt.';

  @override
  String get preferencesPageProcessTree => 'Prozessbaum';

  @override
  String get preferencesPageProcessTreeDetail =>
      'Wie oft Prozesse aktualisiert werden und was sich der Baum merkt.';

  @override
  String get preferencesPageColumnsDetail =>
      'Welche Spalten der Prozessbaum zeigt, und in welcher Reihenfolge.';

  @override
  String get preferencesPageRemoteHosts => 'Entfernte Hosts';

  @override
  String get preferencesPageRemoteHostsDetail =>
      'Rechner, die ProcessLama über deine SSH-Konfiguration erreicht, wie oft ihre Tabs im Hintergrund aktualisiert werden und wie viele ihrer Icons es behält.';

  @override
  String get preferencesPageUpdates => 'Updates';

  @override
  String get preferencesPageUpdatesDetail =>
      'Welche ProcessLama-Versionen dir die Aktualisierung anbietet.';

  @override
  String get preferencesTheme => 'Farbschema';

  @override
  String get searchAspect => 'Suchkriterium';

  @override
  String get searchAll => 'Prozesstext';

  @override
  String get searchName => 'Prozessname';

  @override
  String get searchPid => 'Prozess-ID';

  @override
  String get searchUser => 'Benutzer';

  @override
  String get searchCommand => 'Befehlszeile';

  @override
  String get searchPath => 'Programmpfad';

  @override
  String get searchPort => 'Lokaler Port';

  @override
  String get searchPortHint => 'Lokaler Port (z. B. 8080)';

  @override
  String get occupiedPorts => 'Belegte Ports';

  @override
  String get localPorts => 'Lokale TCP- / UDP-Ports';

  @override
  String get portsNotReported =>
      'Keine Ports gemeldet (keine oder Zugriff eingeschränkt)';

  @override
  String get noOccupiedPorts => 'Keine belegten Ports';

  @override
  String get localPortsExplanation =>
      'Lauschende Ports nehmen Verbindungen an: TCP-Listener und UDP-Sockets auf Well-Known-Ports (unter 1024). Weitere lokale Ports sind meist ausgehende Verbindungen. Wähle einen Port, um alle Prozesse anzuzeigen, die ihn nutzen. Berechtigungen können Ports anderer Benutzer verbergen.';

  @override
  String get listeningPorts => 'Lauschend';

  @override
  String get listeningPortsLabel => 'Lauschende Ports';

  @override
  String get otherLocalPorts => 'Weitere lokale Ports';

  @override
  String showPortProcesses(int port) {
    return 'Prozesse mit Port $port anzeigen';
  }

  @override
  String goToPortOwner(String name, int pid) {
    return '$name ($pid)';
  }

  @override
  String goToPortOwnerLabel(String name, int pid, int port) {
    return 'Zu $name wechseln, PID $pid, lauscht auf Port $port';
  }

  @override
  String get columnPorts => 'Ports';

  @override
  String get socketPeers =>
      'Lokale Prozesse, mit denen diese Sockets verbunden sind';

  @override
  String get diagnosticsTitle => 'Diagnose';

  @override
  String get diagnosticsDescription =>
      'Letzte sichere Ereignisse bleiben nur im Arbeitsspeicher (bis zu 1.000 Ereignisse oder 256 KiB). Die detaillierte Aufzeichnung endet nach spätestens 15 Minuten oder mit der Sitzung. Zugangsdaten und private Inhalte sind ausgeschlossen. Prüfe die Vorschau vor dem Speichern oder Teilen. Es wird nichts automatisch hochgeladen. Verlauf löschen entfernt keine gespeicherten oder geteilten Kopien.';

  @override
  String get diagnosticsEnable =>
      'Detaillierte Diagnose für 15 Minuten aktivieren';

  @override
  String get diagnosticsDisable =>
      'Detaillierte Diagnose aktiv — Details beenden';

  @override
  String get diagnosticsClear => 'Verlauf löschen';

  @override
  String get diagnosticsPreview => 'Exportvorschau';

  @override
  String get diagnosticsCancel => 'Vorschau schließen';

  @override
  String get diagnosticsSave => 'In Datei speichern';

  @override
  String get diagnosticsShare => 'Teilen…';

  @override
  String get diagnosticsFailed =>
      'Diagnose konnte nicht exportiert werden. Versuche ein anderes Ziel.';

  @override
  String get diagnosticsSaved => 'Diagnose gespeichert.';
}
