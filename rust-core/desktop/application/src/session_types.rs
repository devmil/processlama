//! Values a process session publishes and consumes.

use processlama_domain::{
    ProcessDetail, ProcessIdentity, ProcessPortOwner, ProcessPorts, ProcessRecord, ProcessSnapshot,
    RemoteFailureCode, SearchOptions, SortColumn, SortDirection,
};
use std::collections::{BTreeMap, HashSet};
use std::sync::Arc;

/// How often a process source samples.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Cadence {
    Live(u32),
    Background(u32),
    Paused,
}

impl Cadence {
    pub const fn interval_ms(self) -> Option<u32> {
        match self {
            Self::Live(ms) | Self::Background(ms) => Some(ms),
            Self::Paused => None,
        }
    }
}

/// Background tabs refresh this often unless a profile overrides it.
pub const DEFAULT_BACKGROUND_REFRESH_MS: u32 = 5000;

/// Whether a source delivers current data.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum SourcePhase {
    #[default]
    Connecting,
    Live,
    Stale,
    Failed,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct SourceState {
    pub phase: SourcePhase,
    /// Wall-clock ms of the newest sample.
    pub last_sample_at_ms: Option<u64>,
    pub failure: Option<RemoteFailureCode>,
}

impl SourceState {
    pub const LIVE: Self = Self {
        phase: SourcePhase::Live,
        last_sample_at_ms: None,
        failure: None,
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum ChangeMarker {
    #[default]
    None,
    Spawned,
    Terminated,
}

/// What a session asks of its source. Results come back as session calls.
pub trait SessionSource {
    fn set_cadence(&self, cadence: Cadence, polling_interval_ms: u32);
    /// Requests a sample now; ignored while one is in flight.
    fn sample_now(&self, polling_interval_ms: u32);
    /// Fetches inspector detail; the result arrives through
    /// `ProcessSession::on_detail` with the same generation.
    fn fetch_detail(&self, identity: ProcessIdentity, generation: u64);
}

/// Tree search columns: bit positions in `TreeRow::search_columns`.
pub const SEARCH_COLUMNS: [&str; 5] = ["name", "pid", "startTime", "status", "uid"];

/// One visible row of the tree, in preorder.
#[derive(Clone, Debug)]
pub struct TreeRow {
    pub identity: ProcessIdentity,
    pub record: Arc<ProcessRecord>,
    pub depth: u32,
    pub has_children: bool,
    pub is_expanded: bool,
    pub tree_cpu: f64,
    pub tree_gpu: f64,
    pub tree_rss: u64,
    pub tree_network_in: f64,
    pub tree_network_out: f64,
    pub tree_storage_read: f64,
    pub tree_storage_write: f64,
    pub tree_storage_available: bool,
    pub descendant_count: u64,
    pub matches_filter: bool,
    pub preserves_filter_branch: bool,
    /// Bits over `SEARCH_COLUMNS` the tree search matched.
    pub search_columns: u8,
    pub change_marker: ChangeMarker,
    /// The subtree CPU history for the row's sparkline.
    pub cpu_history: Arc<[f32]>,
}

impl TreeRow {
    pub fn matches_tree_search(&self) -> bool {
        self.search_columns != 0
    }

    pub fn is_terminated(&self) -> bool {
        self.change_marker == ChangeMarker::Terminated
    }

    pub fn search_matches_column(&self, column: &str) -> bool {
        SEARCH_COLUMNS
            .iter()
            .position(|id| *id == column)
            .is_some_and(|bit| self.search_columns & (1 << bit) != 0)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
#[allow(clippy::struct_excessive_bools)]
pub struct TreeLockState {
    pub is_frozen: bool,
    pub has_queued_structural_mutations: bool,
    pub queued_process_count: usize,
    pub is_order_locked_by_interaction: bool,
}

/// The tree as a session last published it.
#[derive(Clone, Debug)]
pub struct TreeView {
    pub snapshot: Arc<ProcessSnapshot>,
    pub rows: Arc<Vec<TreeRow>>,
    pub selected: Option<ProcessIdentity>,
    pub filter: String,
    pub tree_search_query: String,
    pub tree_search_match_count: usize,
    /// -1 when the selection is not a match.
    pub tree_search_selected_match_index: i64,
    pub search_options: SearchOptions,
    pub lock: TreeLockState,
    pub sort_column: SortColumn,
    pub sort_direction: SortDirection,
    pub pinned: Arc<HashSet<ProcessIdentity>>,
    pub focused: Option<ProcessIdentity>,
    pub focus_stack_depth: usize,
    pub focused_name: Option<String>,
    pub cpu_scale_max: f64,
}

impl Default for TreeView {
    fn default() -> Self {
        Self {
            snapshot: Arc::new(ProcessSnapshot::empty(None)),
            rows: Arc::new(Vec::new()),
            selected: None,
            filter: String::new(),
            tree_search_query: String::new(),
            tree_search_match_count: 0,
            tree_search_selected_match_index: -1,
            search_options: SearchOptions::default(),
            lock: TreeLockState::default(),
            sort_column: SortColumn::TreeCpu,
            sort_direction: SortDirection::Descending,
            pinned: Arc::new(HashSet::new()),
            focused: None,
            focus_stack_depth: 0,
            focused_name: None,
            cpu_scale_max: 1.0,
        }
    }
}

/// Inspector section availability.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InspectorAvailability {
    Available,
    RequiresPermission,
    UnsupportedPlatform,
    NotImplementedYet,
    Unavailable,
}

/// Histories of the selected process for the inspector charts.
#[derive(Clone, Debug, Default)]
pub struct SelectedHistories {
    pub tree_cpu: Arc<[f32]>,
    pub tree_gpu: Arc<[f32]>,
    pub tree_rss: Arc<[f32]>,
    pub tree_network_in: Arc<[f32]>,
    pub tree_network_out: Arc<[f32]>,
    pub tree_storage_read: Arc<[f32]>,
    pub tree_storage_write: Arc<[f32]>,
    pub cpu: Arc<[f32]>,
    pub gpu: Arc<[f32]>,
    pub rss: Arc<[f32]>,
    pub network_in: Arc<[f32]>,
    pub network_out: Arc<[f32]>,
    pub storage_read: Arc<[f32]>,
    pub storage_write: Arc<[f32]>,
}

/// What the inspector shows for the selection.
#[derive(Clone, Debug, Default)]
pub struct InspectorView {
    pub process: Option<Arc<ProcessRecord>>,
    pub identity: Option<ProcessIdentity>,
    pub change_marker: ChangeMarker,
    pub ports: Option<ProcessPorts>,
    pub tree_ports: Option<ProcessPorts>,
    pub listener_owners_by_port: BTreeMap<u16, Vec<ProcessPortOwner>>,
    pub platform: String,
    /// Inspector detail for the selection, once fetched.
    pub detail: Option<Arc<ProcessDetail>>,
    /// The selection's tree row, when it is visible.
    pub row: Option<TreeRow>,
    pub histories: Option<SelectedHistories>,
}
