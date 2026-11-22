//! The application core: tabs with one process session each, settings,
//! snapshots, remote hosts, icons, updates and the network service. It runs on
//! the GUI thread; [`AppCore::handle`] applies one event, and the shell reads
//! the published state and drains [`UiEvent`]s afterwards.

use crate::events::{Command, CoreEvent, TabKey};
use crate::icons::IconService;
use crate::ports::{
    Clock, EventSink, Executor, LocalTelemetry, NetworkServiceSetup, SettingsStore, SnapshotStore,
    SourceId, UpdateCheck, UpdateChecker,
};
use crate::remote::RemoteHosts;
use crate::remote_ports::{IconCache, RemoteConnector};
use crate::session::{Cadence, DEFAULT_BACKGROUND_REFRESH_MS, ProcessSession, SourceState};
use processlama_domain::{
    AppSettings, CURRENT_SCHEMA_VERSION, HostCapabilities, HostOperatingSystem,
    MAX_INSPECTOR_WIDTH, MAX_POLLING_INTERVAL_MS, MIN_INSPECTOR_WIDTH, MIN_POLLING_INTERVAL_MS,
    ProcessSignal, RemoteHostsState, SearchQuery, SignalOutcome, SnapshotDocument, SnapshotEntry,
    normalize_saved_filters, normalized_visible_columns,
};
use std::sync::Arc;

/// How long drag-driven settings wait before they are written.
pub const SETTINGS_PERSIST_DEBOUNCE_MS: u64 = 400;
/// How often the Linux network service availability is checked.
pub const NETWORK_AVAILABILITY_INTERVAL_MS: u64 = 3000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToastTone {
    Neutral,
    Success,
    Error,
}

/// What the window shows or asks in response to the core.
#[derive(Clone, Debug, PartialEq)]
pub enum UiEvent {
    /// `key` names a localized message; `args` fill its placeholders in order.
    Toast {
        key: &'static str,
        args: Vec<String>,
        tone: ToastTone,
    },
    UpdateAvailable {
        installed_version: String,
        installed_build: u64,
        version: String,
        build: u64,
        installable: bool,
    },
    /// Bytes of an in-place update received so far.
    UpdateProgress {
        received: u64,
        total: u64,
    },
    /// An in-place update finished: installed, or failed (with a toast).
    UpdateInstalled {
        ok: bool,
    },
    /// The updated app started; the window quits.
    QuitForUpdate,
    ConfirmHelperInstall(crate::remote::InstallPrompt),
    ProfileSaved {
        request: u64,
        profile_id: Option<String>,
        /// A localized message key when saving failed.
        error: Option<&'static str>,
    },
    ProbeFinished {
        request: u64,
        outcome: crate::remote::ProbeOutcome,
        /// `Linux/x86_64`-style label, or `–`.
        platform: String,
        compatibility: String,
    },
    CopyToClipboard {
        text: String,
        toast_key: &'static str,
    },
}

/// What changed since the shell last drained [`AppCore::take_changes`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[allow(clippy::struct_excessive_bools)]
pub struct CoreChanges {
    pub settings: bool,
    pub remote_hosts: bool,
    pub connections: bool,
    pub tabs: bool,
    pub tree: bool,
    pub inspector: bool,
    pub session_meta: bool,
    pub snapshots: bool,
    pub icons: bool,
    pub network: bool,
    pub update: bool,
}

impl CoreChanges {
    fn merge(&mut self, other: Self) {
        self.settings |= other.settings;
        self.remote_hosts |= other.remote_hosts;
        self.connections |= other.connections;
        self.tabs |= other.tabs;
        self.tree |= other.tree;
        self.inspector |= other.inspector;
        self.session_meta |= other.session_meta;
        self.snapshots |= other.snapshots;
        self.icons |= other.icons;
        self.network |= other.network;
        self.update |= other.update;
    }
}

/// One tab of the main window.
pub struct Tab {
    pub key: TabKey,
    /// The profile of a remote tab.
    pub profile_id: Option<String>,
    pub source: SourceId,
    pub session: ProcessSession,
}

impl Tab {
    pub fn is_local(&self) -> bool {
        self.profile_id.is_none()
    }
}

pub const LOCAL_TAB: &str = "local";

pub fn remote_tab_key(profile_id: &str) -> TabKey {
    format!("remote:{profile_id}")
}

/// The ports the core uses, supplied by the composition root.
pub struct CorePorts {
    pub sink: Arc<dyn EventSink>,
    pub executor: Arc<dyn Executor>,
    pub clock: Arc<dyn Clock>,
    pub local: Box<dyn LocalTelemetry>,
    pub local_os: HostOperatingSystem,
    pub snapshots: Arc<dyn SnapshotStore>,
    pub settings: Arc<dyn SettingsStore>,
    pub updates: Arc<dyn UpdateChecker>,
    pub network: Arc<dyn NetworkServiceSetup>,
    pub remote: Arc<dyn RemoteConnector>,
    pub icon_cache: Arc<dyn IconCache>,
}

pub struct AppCore {
    pub(crate) ports: CorePorts,
    pub(crate) settings: AppSettings,
    pub(crate) remote_state: RemoteHostsState,
    pub(crate) tabs: Vec<Tab>,
    pub(crate) active: usize,
    pub(crate) next_source: u64,
    pub(crate) snapshots: Vec<SnapshotEntry>,
    pub(crate) remote: RemoteHosts,
    pub(crate) icons: IconService,
    pub(crate) network_available: bool,
    pub(crate) next_network_check: Option<u64>,
    persist_at: Option<u64>,
    remote_writes_pending: usize,
    installing_update: bool,
    ui_events: Vec<UiEvent>,
    changes: CoreChanges,
    disposed: bool,
}

impl AppCore {
    pub fn new(ports: CorePorts) -> Self {
        let settings = ports.settings.load_settings();
        let remote_state = ports.settings.load_remote_hosts();
        let network_supported = ports.network.is_supported();
        let mut core = Self {
            settings,
            remote_state,
            tabs: Vec::new(),
            active: 0,
            next_source: 1,
            snapshots: Vec::new(),
            installing_update: false,
            remote: RemoteHosts::default(),
            icons: IconService::default(),
            network_available: true,
            next_network_check: None,
            persist_at: None,
            remote_writes_pending: 0,
            ui_events: Vec::new(),
            changes: CoreChanges::default(),
            disposed: false,
            ports,
        };
        let now = core.now();
        let source = core.allocate_source();
        let session = ProcessSession::new(
            core.ports.local.create_source(source),
            HostCapabilities::local(core.ports.local_os),
            SourceState::LIVE,
            Cadence::Background(DEFAULT_BACKGROUND_REFRESH_MS),
        );
        core.tabs.push(Tab {
            key: LOCAL_TAB.into(),
            profile_id: None,
            source,
            session,
        });
        let settings = core.settings.clone();
        core.tabs[0].session.initialize(&settings, now);
        core.ports.updates.configure(core.settings.release_channel);
        core.refresh_snapshot_list();
        if network_supported {
            core.check_network_availability();
            core.next_network_check = Some(now + NETWORK_AVAILABILITY_INTERVAL_MS);
        }
        core.restore_remote_tabs();
        core.changes = CoreChanges {
            settings: true,
            remote_hosts: true,
            connections: true,
            tabs: true,
            tree: true,
            inspector: true,
            session_meta: true,
            snapshots: true,
            icons: true,
            network: true,
            update: true,
        };
        core
    }

    // Reading

    pub fn settings(&self) -> &AppSettings {
        &self.settings
    }

    pub fn remote_hosts(&self) -> &RemoteHostsState {
        &self.remote_state
    }

    pub fn tabs(&self) -> &[Tab] {
        &self.tabs
    }

    pub fn active_index(&self) -> usize {
        self.active
    }

    pub fn active_tab(&self) -> &Tab {
        &self.tabs[self.active]
    }

    pub fn active_session(&self) -> &ProcessSession {
        &self.tabs[self.active].session
    }

    pub fn snapshots(&self) -> &[SnapshotEntry] {
        &self.snapshots
    }

    pub fn network_available(&self) -> bool {
        self.network_available
    }

    pub fn network_supported(&self) -> bool {
        self.ports.network.is_supported()
    }

    pub fn update_supported(&self) -> bool {
        self.ports.updates.is_supported()
    }

    pub fn installed_version(&self) -> crate::ports::InstalledVersion {
        self.ports.updates.installed()
    }

    pub fn remote(&self) -> &RemoteHosts {
        &self.remote
    }

    pub fn icon_cache(&self) -> &Arc<dyn IconCache> {
        &self.ports.icon_cache
    }

    /// How many processes of the active snapshot match a saved filter.
    pub fn saved_filter_count(&self, saved: &str) -> usize {
        let query = SearchQuery::parse(saved, processlama_domain::SearchOptions::default());
        self.active_session()
            .snapshot()
            .processes
            .iter()
            .filter(|record| query.matches(record))
            .count()
    }

    pub fn take_changes(&mut self) -> CoreChanges {
        // Fold session changes into the core's view of the active tab.
        let active = self.active;
        for (index, tab) in self.tabs.iter_mut().enumerate() {
            let session = tab.session.take_changes();
            if index == active {
                self.changes.tree |= session.tree;
                self.changes.inspector |= session.inspector;
                self.changes.session_meta |=
                    session.tree || session.filter || session.loaded_snapshot;
            }
        }
        std::mem::take(&mut self.changes)
    }

    pub fn take_ui_events(&mut self) -> Vec<UiEvent> {
        std::mem::take(&mut self.ui_events)
    }

    pub(crate) fn emit(&mut self, event: UiEvent) {
        self.ui_events.push(event);
    }

    pub(crate) fn toast(&mut self, key: &'static str, args: Vec<String>, tone: ToastTone) {
        self.emit(UiEvent::Toast { key, args, tone });
    }

    pub(crate) fn mark(&mut self, changes: CoreChanges) {
        self.changes.merge(changes);
    }

    pub(crate) fn now(&self) -> u64 {
        self.ports.clock.monotonic_ms()
    }

    pub(crate) fn wall(&self) -> u64 {
        self.ports.clock.wall_ms()
    }

    pub(crate) fn allocate_source(&mut self) -> SourceId {
        let id = SourceId(self.next_source);
        self.next_source += 1;
        id
    }

    pub(crate) fn tab_index_for_source(&self, source: SourceId) -> Option<usize> {
        self.tabs.iter().position(|tab| tab.source == source)
    }

    pub(crate) fn spawn(&self, job: impl FnOnce() + Send + 'static) {
        self.ports.executor.spawn(Box::new(job));
    }

    pub(crate) fn sink(&self) -> Arc<dyn EventSink> {
        Arc::clone(&self.ports.sink)
    }

    // Timers

    /// The earliest monotonic time at which the core wants a Tick.
    pub fn next_deadline(&self) -> Option<u64> {
        let mut deadline: Option<u64> = None;
        let mut consider = |value: Option<u64>| {
            if let Some(value) = value {
                deadline = Some(deadline.map_or(value, |current| current.min(value)));
            }
        };
        for tab in &self.tabs {
            consider(tab.session.next_deadline());
        }
        consider(self.persist_at);
        consider(self.next_network_check);
        consider(self.remote.next_deadline());
        consider(self.icons.next_deadline());
        deadline
    }

    fn on_tick(&mut self) {
        let now = self.now();
        for tab in &mut self.tabs {
            if tab.session.next_deadline().is_some_and(|at| at <= now) {
                tab.session.on_time(now);
            }
        }
        if self.persist_at.is_some_and(|at| at <= now) {
            self.persist_at = None;
            self.save_settings_now();
        }
        if self.next_network_check.is_some_and(|at| at <= now) {
            self.next_network_check = Some(now + NETWORK_AVAILABILITY_INTERVAL_MS);
            self.check_network_availability();
        }
        self.remote_on_time(now);
        self.icons_on_time(now);
    }

    // Events

    pub fn handle(&mut self, event: CoreEvent) {
        if self.disposed {
            return;
        }
        match event {
            CoreEvent::Tick => self.on_tick(),
            CoreEvent::Command(command) => self.handle_command(command),
            CoreEvent::Sample { source, snapshot } => {
                let now = self.now();
                if let Some(index) = self.tab_index_for_source(source) {
                    self.remote_before_sample(index, &snapshot);
                    self.tabs[index].session.on_sample(snapshot, now);
                    self.remote_after_sample(index);
                }
            }
            CoreEvent::SampleFailed { source, error } => {
                let now = self.now();
                if let Some(index) = self.tab_index_for_source(source) {
                    self.tabs[index].session.on_sample(
                        Arc::new(processlama_domain::ProcessSnapshot::empty(Some(error))),
                        now,
                    );
                }
            }
            CoreEvent::Detail {
                source,
                identity,
                generation,
                detail,
            } => {
                if let Some(index) = self.tab_index_for_source(source) {
                    self.tabs[index]
                        .session
                        .on_detail(identity, generation, detail);
                }
            }
            CoreEvent::SignalSent {
                source,
                identity: _,
                signal,
                outcome,
            } => self.on_signal_sent(source, signal, outcome),
            CoreEvent::SnapshotsListed(entries) => {
                self.snapshots = entries;
                self.mark(CoreChanges {
                    snapshots: true,
                    session_meta: true,
                    ..CoreChanges::default()
                });
            }
            CoreEvent::SnapshotSaved(result) => {
                match result {
                    Ok(()) => self.toast("snapshotTaken", vec![], ToastTone::Success),
                    Err(error) => self.toast("snapshotFailed", vec![error], ToastTone::Error),
                }
                self.refresh_snapshot_list();
            }
            CoreEvent::SnapshotOpened {
                tab,
                path: _,
                result,
            } => self.on_snapshot_opened(&tab, result),
            CoreEvent::SnapshotExported { target, result } => match result {
                Ok(()) => self.toast("exportedPath", vec![target], ToastTone::Success),
                Err(error) => self.toast("exportFailed", vec![error], ToastTone::Error),
            },
            CoreEvent::SnapshotRenamed(result) => {
                match result {
                    Ok(()) => self.toast("snapshotRenamed", vec![], ToastTone::Success),
                    Err(error) => self.toast("snapshotRenameFailed", vec![error], ToastTone::Error),
                }
                self.refresh_snapshot_list();
            }
            CoreEvent::SnapshotDeleted { path, result } => {
                match result {
                    Ok(()) => {
                        self.toast("snapshotDeleted", vec![], ToastTone::Neutral);
                        let now = self.now();
                        for tab in &mut self.tabs {
                            if tab.session.loaded_snapshot_path() == Some(path.as_str()) {
                                tab.session.show_live(now);
                            }
                        }
                    }
                    Err(error) => self.toast("snapshotDeleteFailed", vec![error], ToastTone::Error),
                }
                self.refresh_snapshot_list();
            }
            CoreEvent::SettingsSaved(_) => {}
            CoreEvent::RemoteHostsSaved { section, result } => {
                self.on_remote_hosts_saved(section, result)
            }
            CoreEvent::UpdateChecked(result) => self.on_update_checked(result),
            CoreEvent::UpdateProgress { received, total } => {
                self.emit(UiEvent::UpdateProgress { received, total })
            }
            CoreEvent::UpdateInstalled(result) => self.on_update_installed(result),
            CoreEvent::NetworkAvailability(available) => {
                if self.network_available != available {
                    self.network_available = available;
                    self.mark(CoreChanges {
                        network: true,
                        inspector: true,
                        ..CoreChanges::default()
                    });
                }
            }
            CoreEvent::NetworkInstalled(result) => match result {
                Ok(()) => {
                    self.toast("networkTelemetryInstalled", vec![], ToastTone::Success);
                    self.check_network_availability();
                }
                Err(failure) => {
                    use crate::ports::NetworkSetupFailure::{
                        AuthorizationCancelled, AuthorizationUnavailable, InstallFailed,
                        InstallerMissing,
                    };
                    let key = match failure {
                        InstallerMissing => "networkTelemetryInstallerMissing",
                        AuthorizationUnavailable => "networkTelemetryAuthorizationUnavailable",
                        AuthorizationCancelled => "networkTelemetryAuthorizationCancelled",
                        InstallFailed => "networkTelemetryInstallFailed",
                    };
                    self.toast(key, vec![], ToastTone::Error);
                }
            },
            CoreEvent::Remote(event) => self.handle_remote_event(event),
        }
    }

    fn handle_command(&mut self, command: Command) {
        let now = self.now();
        let session = &mut self.tabs[self.active].session;
        match command {
            Command::SetFilter(value) => session.set_filter(&value, now),
            Command::SetSearchAspect(aspect) => session.set_search_aspect(aspect, now),
            Command::SetSearchMatchCase(value) => session.set_search_match_case(value, now),
            Command::SetSearchWholeWord(value) => session.set_search_whole_word(value, now),
            Command::SetTreeSearch(value) => session.set_tree_search(&value, now),
            Command::SelectNextTreeSearchMatch => session.select_next_tree_search_match(now),
            Command::SelectPreviousTreeSearchMatch => {
                session.select_previous_tree_search_match(now)
            }
            Command::ToggleExpansion(identity) => session.toggle_expansion(identity, now),
            Command::SelectProcess(identity) => session.select_process(identity, now),
            Command::SelectNextVisible => session.select_next_visible(now),
            Command::SelectPreviousVisible => session.select_previous_visible(now),
            Command::ExpandSelected => session.expand_selected(now),
            Command::CollapseSelected => session.collapse_selected(now),
            Command::ExpandSelectedSubtree => session.expand_selected_subtree(now),
            Command::CollapseSelectedSubtree => session.collapse_selected_subtree(now),
            Command::FocusSelectedSubtree => session.focus_selected_subtree(now),
            Command::FocusSubtree(identity) => session.focus_subtree(identity, now),
            Command::PopSubtreeFocus => session.pop_subtree_focus(now),
            Command::ClearSubtreeFocus => session.clear_subtree_focus(now),
            Command::SortBy(column) => {
                let (column, direction) = session.sort_by(column, now);
                self.change_settings(true, |settings| {
                    settings.process_sort_column = column;
                    settings.process_sort_direction = direction;
                });
            }
            Command::TogglePin(identity) => session.toggle_pin(identity, now),
            Command::SetTreeHovering(value) => session.set_tree_hovering(value, now),
            Command::SetTreeContextMenuOpen(value) => {
                session.set_tree_context_menu_open(value, now)
            }
            Command::SetModalOverlayOpen(value) => session.set_modal_overlay_open(value, now),
            Command::MarkTreeInteraction => session.mark_tree_interaction(now),
            Command::SetWindowResizing(value) => {
                session.set_window_resizing(value);
                if !value {
                    session.refresh();
                }
            }
            Command::ToggleFrozen => session.toggle_frozen(now),
            Command::ShowPort(port) => session.show_port(port, now),
            Command::Refresh => session.refresh(),
            Command::SendSignal(identity, signal) => self.send_signal(identity, signal),
            Command::TakeSnapshot => self.take_snapshot(),
            Command::OpenSnapshot(path) => self.open_snapshot(path),
            Command::ShowLive => session.show_live(now),
            Command::ExportSnapshot { path, target } => self.export_snapshot(path, target),
            Command::RenameSnapshot { path, name } => self.rename_snapshot(path, name),
            Command::DeleteSnapshot(path) => self.delete_snapshot(path),
            Command::SetPollingInterval(value) => {
                let value = value.clamp(MIN_POLLING_INTERVAL_MS, MAX_POLLING_INTERVAL_MS);
                self.change_settings(true, |settings| settings.polling_interval_ms = value);
            }
            Command::SetRememberTreeExpansion(value) => {
                self.change_settings(true, |settings| settings.remember_tree_expansion = value);
            }
            Command::SaveCurrentFilter => {
                let session = &self.tabs[self.active].session;
                let filter = session.filter().to_owned();
                if filter.is_empty() {
                    return;
                }
                let saved = session.search_options().saved_query(&filter);
                self.add_saved_filter(&saved);
            }
            Command::ApplySavedFilter(saved) => {
                let query =
                    SearchQuery::parse(&saved, processlama_domain::SearchOptions::default());
                let value = query.options.saved_query(&query.text);
                self.tabs[self.active].session.set_filter(&value, now);
            }
            Command::RemoveSavedFilter(saved) => {
                let filters: Vec<String> = self
                    .settings
                    .saved_filters
                    .iter()
                    .filter(|filter| **filter != saved)
                    .cloned()
                    .collect();
                self.change_settings(true, |settings| {
                    settings.saved_filters = normalize_saved_filters(&filters)
                });
            }
            Command::SetVisibleColumns(columns) => {
                let normalized = normalized_visible_columns(&columns);
                self.change_settings(true, |settings| settings.visible_columns = normalized);
            }
            Command::SetColumnWidth { column, width } => {
                if processlama_domain::is_available_column(&column) {
                    let width = clamp_column_width(&column, width);
                    self.change_settings(false, |settings| {
                        settings.column_widths.insert(column, width);
                    });
                }
            }
            Command::ResetColumnWidth(column) => {
                self.change_settings(false, |settings| {
                    settings.column_widths.remove(&column);
                });
            }
            Command::SetInspectorWidth(width) => {
                let width = width.clamp(MIN_INSPECTOR_WIDTH, MAX_INSPECTOR_WIDTH);
                self.change_settings(false, |settings| settings.inspector_width = width);
            }
            Command::ResetInspectorWidth => {
                self.change_settings(false, |settings| {
                    settings.inspector_width = processlama_domain::DEFAULT_INSPECTOR_WIDTH;
                });
            }
            Command::SetAppearance(mode) => {
                self.change_settings(true, |settings| settings.appearance_mode = mode)
            }
            Command::SetRowHeatmap(value) => {
                self.change_settings(true, |settings| settings.row_heatmap = value)
            }
            Command::SetRowDensity(value) => {
                self.change_settings(true, |settings| settings.row_density = value)
            }
            Command::SetReleaseChannel(channel) => {
                self.change_settings(true, |settings| settings.release_channel = channel);
                self.ports.updates.configure(channel);
            }
            Command::FlushSettings => {
                if self.persist_at.take().is_some() {
                    let _ = self.ports.settings.save_settings(&self.settings);
                }
            }
            Command::ActivateTab(key) => {
                if let Some(index) = self.tabs.iter().position(|tab| tab.key == key) {
                    self.activate(index, true);
                }
            }
            Command::ActivateTabIndex(index) => {
                if index < self.tabs.len() {
                    self.activate(index, true);
                }
            }
            Command::CycleTabs { backwards } => {
                let count = self.tabs.len();
                if count >= 2 {
                    let next = if backwards {
                        (self.active + count - 1) % count
                    } else {
                        (self.active + 1) % count
                    };
                    self.activate(next, true);
                }
            }
            Command::CloseTab(key) => self.close_tab(&key),
            Command::MoveTab { from, to } => self.move_tab(from, to),
            Command::Remote(command) => self.handle_remote_command(command),
            Command::SetDefaultBackgroundRefresh(mode) => self.set_default_background_refresh(mode),
            Command::SetRemoteIconCacheBytes(bytes) => self.set_icon_cache_bytes(bytes),
            Command::ClearRemoteIconCache => self.clear_icon_cache(),
            Command::CheckForUpdates => self.check_for_updates(),
            Command::InstallUpdate => self.install_update(),
            Command::RelaunchAfterUpdate => match self.ports.updates.relaunch() {
                Ok(()) => self.emit(UiEvent::QuitForUpdate),
                Err(error) => self.toast("updateRelaunchFailed", vec![error], ToastTone::Error),
            },
            Command::RefreshNetworkAvailability => self.check_network_availability(),
            Command::InstallNetworkTelemetry => {
                let network = Arc::clone(&self.ports.network);
                let sink = self.sink();
                self.spawn(move || {
                    sink.post(CoreEvent::NetworkInstalled(network.install_or_repair()))
                });
            }
        }
    }

    // Settings

    /// Applies a settings change. `save_now` writes at once; otherwise the
    /// write is debounced (drags change values many times per second).
    pub(crate) fn change_settings(
        &mut self,
        save_now: bool,
        change: impl FnOnce(&mut AppSettings),
    ) {
        let mut next = self.settings.clone();
        change(&mut next);
        if next == self.settings {
            return;
        }
        let now = self.now();
        self.settings = next;
        let settings = self.settings.clone();
        for tab in &mut self.tabs {
            tab.session.on_settings_changed(&settings, now);
        }
        self.remote_on_settings_changed();
        self.mark(CoreChanges {
            settings: true,
            ..CoreChanges::default()
        });
        if save_now {
            self.persist_at = None;
            self.save_settings_now();
        } else {
            self.persist_at = Some(now + SETTINGS_PERSIST_DEBOUNCE_MS);
        }
    }

    fn save_settings_now(&self) {
        let store = Arc::clone(&self.ports.settings);
        let settings = self.settings.clone();
        let sink = self.sink();
        self.spawn(move || sink.post(CoreEvent::SettingsSaved(store.save_settings(&settings))));
    }

    fn add_saved_filter(&mut self, value: &str) {
        let normalized = value.trim().to_owned();
        if normalized.is_empty() {
            return;
        }
        let mut filters = vec![normalized.clone()];
        filters.extend(
            self.settings
                .saved_filters
                .iter()
                .filter(|filter| filter.to_lowercase() != normalized.to_lowercase())
                .cloned(),
        );
        self.change_settings(true, |settings| {
            settings.saved_filters = normalize_saved_filters(&filters)
        });
    }

    /// Writes the remote hosts value; on failure `restore` is applied.
    pub(crate) fn save_remote_hosts(&mut self, section: &'static str) {
        self.remote_writes_pending += 1;
        let store = Arc::clone(&self.ports.settings);
        let state = self.remote_state.clone();
        let sink = self.sink();
        self.spawn(move || {
            sink.post(CoreEvent::RemoteHostsSaved {
                section,
                result: store.save_remote_hosts(&state),
            });
        });
        self.mark(CoreChanges {
            remote_hosts: true,
            ..CoreChanges::default()
        });
    }

    fn on_remote_hosts_saved(&mut self, section: &'static str, result: Result<(), String>) {
        self.remote_writes_pending = self.remote_writes_pending.saturating_sub(1);
        if result.is_err() && section == "profile" {
            self.toast("remoteHostSaveFailed", vec![], ToastTone::Error);
        }
    }

    /// Writes pending settings synchronously (application exit).
    pub fn flush(&mut self) {
        if self.persist_at.take().is_some() {
            let _ = self.ports.settings.save_settings(&self.settings);
        }
    }

    // Tabs

    pub(crate) fn activate(&mut self, index: usize, persist: bool) {
        if index == self.active || index >= self.tabs.len() {
            return;
        }
        let now = self.now();
        let previous = self.active;
        self.active = index;
        self.tabs[previous].session.set_active(false, now);
        self.tabs[index].session.set_active(true, now);
        self.mark(CoreChanges {
            tabs: true,
            tree: true,
            inspector: true,
            session_meta: true,
            ..CoreChanges::default()
        });
        if persist {
            self.persist_tabs();
        }
    }

    pub(crate) fn persist_tabs(&mut self) {
        let open: Vec<String> = self
            .tabs
            .iter()
            .filter_map(|tab| tab.profile_id.clone())
            .collect();
        let active = Some(self.tabs[self.active].key.clone());
        let known: std::collections::HashSet<&str> = self
            .remote_state
            .profiles
            .iter()
            .map(|profile| profile.id.as_str())
            .collect();
        let open: Vec<String> = open
            .into_iter()
            .filter(|id| known.contains(id.as_str()))
            .collect();
        if open == self.remote_state.open_tabs && active == self.remote_state.active_tab {
            return;
        }
        self.remote_state.open_tabs = open;
        self.remote_state.active_tab = active;
        self.save_remote_hosts("tabs");
    }

    fn close_tab(&mut self, key: &str) {
        let Some(index) = self.tabs.iter().position(|tab| tab.key == key) else {
            return;
        };
        if self.tabs[index].is_local() {
            return;
        }
        let was_active = index == self.active;
        let mut tab = self.tabs.remove(index);
        tab.session.dispose();
        if was_active {
            self.active = index.saturating_sub(1).min(self.tabs.len() - 1);
            let now = self.now();
            self.tabs[self.active].session.set_active(true, now);
        } else if index < self.active {
            self.active -= 1;
        }
        self.remote_release_tab(&tab);
        self.mark(CoreChanges {
            tabs: true,
            tree: true,
            inspector: true,
            session_meta: true,
            ..CoreChanges::default()
        });
        self.persist_tabs();
    }

    fn move_tab(&mut self, from: usize, to: usize) {
        if from == 0 || from >= self.tabs.len() {
            return;
        }
        let target = to.clamp(1, self.tabs.len() - 1);
        if target == from {
            return;
        }
        let active_key = self.tabs[self.active].key.clone();
        let tab = self.tabs.remove(from);
        self.tabs.insert(target, tab);
        self.active = self
            .tabs
            .iter()
            .position(|tab| tab.key == active_key)
            .unwrap_or(0);
        self.mark(CoreChanges {
            tabs: true,
            ..CoreChanges::default()
        });
        self.persist_tabs();
    }

    // Snapshots

    pub(crate) fn refresh_snapshot_list(&self) {
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        self.spawn(move || sink.post(CoreEvent::SnapshotsListed(store.list().unwrap_or_default())));
    }

    fn take_snapshot(&mut self) {
        let tab = &self.tabs[self.active];
        let snapshot = Arc::clone(tab.session.snapshot());
        let context = tab
            .profile_id
            .as_deref()
            .map(|profile| self.remote_snapshot_context(profile, &snapshot));
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        let wall = self.wall();
        self.spawn(move || {
            let (host, icons) = match context {
                Some(context) => {
                    let icons = context.icons_base64();
                    (Some(context.host), icons)
                }
                None => (None, Default::default()),
            };
            let document = SnapshotDocument {
                schema_version: if host.is_some() {
                    CURRENT_SCHEMA_VERSION
                } else {
                    1
                },
                exported_at_unix_ms: wall,
                source: "ProcessLama".into(),
                display_name: None,
                host,
                icons,
                snapshot: (*snapshot).clone(),
            };
            sink.post(CoreEvent::SnapshotSaved(store.save(&document).map(|_| ())));
        });
    }

    fn open_snapshot(&mut self, path: String) {
        let tab = self.tabs[self.active].key.clone();
        let saved = self.snapshots.iter().any(|entry| entry.path == path);
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        self.spawn(move || {
            let result = (|| {
                let stored = if saved {
                    path.clone()
                } else {
                    store.import(&path)?
                };
                let document = store.read(&stored)?;
                Ok((stored, document))
            })();
            sink.post(CoreEvent::SnapshotOpened { tab, path, result });
        });
    }

    fn on_snapshot_opened(
        &mut self,
        tab: &str,
        result: Result<(String, SnapshotDocument), String>,
    ) {
        match result {
            Ok((stored, document)) => {
                self.import_snapshot_icons(&document);
                let now = self.now();
                if let Some(tab) = self.tabs.iter_mut().find(|candidate| candidate.key == tab) {
                    tab.session
                        .load_snapshot(stored, Arc::new(document.snapshot), now);
                }
                self.toast("snapshotLoaded", vec![], ToastTone::Neutral);
                self.refresh_snapshot_list();
            }
            Err(error) => self.toast("snapshotLoadFailed", vec![error], ToastTone::Error),
        }
    }

    fn export_snapshot(&mut self, path: String, target: String) {
        let Some(entry) = self
            .snapshots
            .iter()
            .find(|entry| entry.path == path)
            .cloned()
        else {
            return;
        };
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        self.spawn(move || {
            let result = store.export(&entry, &target);
            sink.post(CoreEvent::SnapshotExported { target, result });
        });
    }

    fn rename_snapshot(&mut self, path: String, name: String) {
        let Some(entry) = self
            .snapshots
            .iter()
            .find(|entry| entry.path == path)
            .cloned()
        else {
            return;
        };
        let name = name.trim().to_owned();
        if name.is_empty() {
            return;
        }
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        self.spawn(move || sink.post(CoreEvent::SnapshotRenamed(store.rename(&entry, &name))));
    }

    fn delete_snapshot(&mut self, path: String) {
        let Some(entry) = self
            .snapshots
            .iter()
            .find(|entry| entry.path == path)
            .cloned()
        else {
            return;
        };
        let store = Arc::clone(&self.ports.snapshots);
        let sink = self.sink();
        self.spawn(move || {
            let result = store.delete(&entry);
            sink.post(CoreEvent::SnapshotDeleted { path, result });
        });
    }

    // Signals

    fn send_signal(
        &mut self,
        identity: processlama_domain::ProcessIdentity,
        signal: ProcessSignal,
    ) {
        let tab = &self.tabs[self.active];
        let source = tab.source;
        if let Some(profile) = tab.profile_id.clone() {
            self.remote_send_signal(&profile, source, identity, signal);
            return;
        }
        let local = self.ports.local.signal_handle();
        let sink = self.sink();
        self.spawn(move || {
            let outcome = local.send_signal(identity, signal);
            sink.post(CoreEvent::SignalSent {
                source,
                identity,
                signal,
                outcome: Ok(outcome),
            });
        });
    }

    fn on_signal_sent(
        &mut self,
        source: SourceId,
        signal: ProcessSignal,
        outcome: Result<SignalOutcome, String>,
    ) {
        match outcome {
            Ok(SignalOutcome::Sent) => {
                let key = match signal {
                    ProcessSignal::Terminate => "processTerminated",
                    ProcessSignal::Kill => "processKilled",
                    ProcessSignal::Suspend => "processSuspended",
                    ProcessSignal::Resume => "processResumed",
                };
                self.toast(key, vec![], ToastTone::Success);
            }
            Ok(SignalOutcome::Denied) => {
                self.toast("processSignalDenied", vec![], ToastTone::Error)
            }
            Ok(SignalOutcome::NotFound) => {
                self.toast("processSignalNotFound", vec![], ToastTone::Error)
            }
            Ok(SignalOutcome::Unknown) => {
                self.toast("processSignalUnknown", vec![], ToastTone::Error)
            }
            Err(error) => self.toast("processActionFailed", vec![error], ToastTone::Error),
        }
        if let Some(index) = self.tab_index_for_source(source) {
            self.tabs[index].session.refresh();
        }
    }

    // Updates and network

    fn check_for_updates(&mut self) {
        if !self.ports.updates.is_supported() {
            return;
        }
        let updates = Arc::clone(&self.ports.updates);
        let channel = self.settings.release_channel;
        let sink = self.sink();
        self.spawn(move || sink.post(CoreEvent::UpdateChecked(updates.check(channel))));
    }

    fn on_update_checked(&mut self, result: Result<UpdateCheck, String>) {
        let installed = self.ports.updates.installed();
        match result {
            Ok(UpdateCheck::NativeCheckerOpened) => {}
            Ok(UpdateCheck::UpToDate) => self.toast(
                "updateUpToDate",
                vec![installed.version, installed.build.to_string()],
                ToastTone::Success,
            ),
            Ok(UpdateCheck::NoPublishedRelease) => {
                self.toast("updateNoPublishedRelease", vec![], ToastTone::Neutral)
            }
            Ok(UpdateCheck::UpdateAvailable {
                version,
                build,
                installable,
            }) => self.emit(UiEvent::UpdateAvailable {
                installed_version: installed.version,
                installed_build: installed.build,
                version,
                build,
                installable,
            }),
            Err(error) => self.toast("updateCheckFailed", vec![error], ToastTone::Error),
        }
    }

    fn install_update(&mut self) {
        if self.installing_update {
            return;
        }
        self.installing_update = true;
        let updates = Arc::clone(&self.ports.updates);
        let sink = self.sink();
        self.spawn(move || {
            // About a hundred progress events per download.
            let mut reported = 0u64;
            let result = updates.install(&mut |received, total| {
                if received == total || received - reported >= (total / 100).max(1) {
                    reported = received;
                    sink.post(CoreEvent::UpdateProgress { received, total });
                }
            });
            sink.post(CoreEvent::UpdateInstalled(result));
        });
    }

    fn on_update_installed(&mut self, result: Result<(), String>) {
        self.installing_update = false;
        let ok = result.is_ok();
        if let Err(error) = result {
            self.toast("updateInstallFailed", vec![error], ToastTone::Error);
        }
        self.emit(UiEvent::UpdateInstalled { ok });
    }

    fn check_network_availability(&self) {
        if !self.ports.network.is_supported() {
            return;
        }
        let network = Arc::clone(&self.ports.network);
        let sink = self.sink();
        self.spawn(move || sink.post(CoreEvent::NetworkAvailability(network.is_available())));
    }

    /// Stops sampling and closes every remote connection.
    pub fn dispose(&mut self) {
        self.flush();
        for tab in &mut self.tabs {
            tab.session.dispose();
        }
        self.remote_dispose();
        self.disposed = true;
    }
}

/// The name column is 180..960 wide; others 52..360.
pub fn clamp_column_width(column: &str, width: f64) -> f64 {
    if column == "name" {
        width.clamp(180.0, 960.0)
    } else {
        width.clamp(52.0, 360.0)
    }
}

impl AppCore {
    /// Bumped when remote icons arrive or the cache clears.
    pub fn icons_revision(&self) -> u64 {
        self.icons.revision()
    }
}
