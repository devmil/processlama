//! Events the core handles on the GUI thread: worker results, timer ticks and
//! commands from the window.

use crate::ports::{SourceId, UpdateCheck, NetworkSetupFailure};
use crate::remote::RemoteEvent;
use processlama_domain::{
    AppearanceMode, BackgroundRefreshMode, ProcessDetail, ProcessIdentity, ProcessSignal,
    ProcessSnapshot, ReleaseChannel, RowDensity, SearchAspect, SignalOutcome, SnapshotDocument,
    SnapshotEntry, SortColumn,
};
use std::sync::Arc;

/// A tab key: `local` or `remote:<profile id>`.
pub type TabKey = String;

#[derive(Debug)]
pub enum CoreEvent {
    /// A source delivered a sample.
    Sample { source: SourceId, snapshot: Arc<ProcessSnapshot> },
    /// A source failed to sample; the session shows the error.
    SampleFailed { source: SourceId, error: String },
    Detail {
        source: SourceId,
        identity: ProcessIdentity,
        generation: u64,
        detail: Option<ProcessDetail>,
    },
    SignalSent {
        source: SourceId,
        identity: ProcessIdentity,
        signal: ProcessSignal,
        outcome: Result<SignalOutcome, String>,
    },
    SnapshotsListed(Vec<SnapshotEntry>),
    SnapshotSaved(Result<(), String>),
    SnapshotOpened {
        tab: TabKey,
        path: String,
        result: Result<(String, SnapshotDocument), String>,
    },
    SnapshotExported { target: String, result: Result<(), String> },
    SnapshotRenamed(Result<(), String>),
    SnapshotDeleted { path: String, result: Result<(), String> },
    SettingsSaved(Result<(), String>),
    RemoteHostsSaved { section: &'static str, result: Result<(), String> },
    UpdateChecked(Result<UpdateCheck, String>),
    NetworkAvailability(bool),
    NetworkInstalled(Result<(), NetworkSetupFailure>),
    Remote(RemoteEvent),
    /// The timer thread reached the core's next deadline.
    Tick,
    Command(Command),
}

/// What the window asks the core to do.
#[derive(Clone, Debug)]
pub enum Command {
    // The active tab's explorer
    SetFilter(String),
    SetSearchAspect(SearchAspect),
    SetSearchMatchCase(bool),
    SetSearchWholeWord(bool),
    SetTreeSearch(String),
    SelectNextTreeSearchMatch,
    SelectPreviousTreeSearchMatch,
    ToggleExpansion(ProcessIdentity),
    SelectProcess(ProcessIdentity),
    SelectNextVisible,
    SelectPreviousVisible,
    ExpandSelected,
    CollapseSelected,
    ExpandSelectedSubtree,
    CollapseSelectedSubtree,
    FocusSelectedSubtree,
    FocusSubtree(ProcessIdentity),
    PopSubtreeFocus,
    ClearSubtreeFocus,
    SortBy(SortColumn),
    TogglePin(ProcessIdentity),
    SetTreeHovering(bool),
    SetTreeContextMenuOpen(bool),
    SetModalOverlayOpen(bool),
    MarkTreeInteraction,
    SetWindowResizing(bool),
    ToggleFrozen,
    ShowPort(u16),
    SendSignal(ProcessIdentity, ProcessSignal),
    Refresh,
    // Snapshots
    TakeSnapshot,
    OpenSnapshot(String),
    ShowLive,
    ExportSnapshot { path: String, target: String },
    RenameSnapshot { path: String, name: String },
    DeleteSnapshot(String),
    // Settings
    SetPollingInterval(u32),
    SetRememberTreeExpansion(bool),
    SaveCurrentFilter,
    ApplySavedFilter(String),
    RemoveSavedFilter(String),
    SetVisibleColumns(Vec<String>),
    SetColumnWidth { column: String, width: f64 },
    ResetColumnWidth(String),
    SetInspectorWidth(f64),
    ResetInspectorWidth,
    SetAppearance(AppearanceMode),
    SetRowHeatmap(bool),
    SetRowDensity(RowDensity),
    SetReleaseChannel(ReleaseChannel),
    FlushSettings,
    // Tabs
    ActivateTab(TabKey),
    ActivateTabIndex(usize),
    CycleTabs { backwards: bool },
    CloseTab(TabKey),
    MoveTab { from: usize, to: usize },
    // Remote hosts
    Remote(crate::remote::RemoteCommand),
    SetDefaultBackgroundRefresh(BackgroundRefreshMode),
    SetRemoteIconCacheBytes(u64),
    ClearRemoteIconCache,
    // Platform
    CheckForUpdates,
    RefreshNetworkAvailability,
    InstallNetworkTelemetry,
}
