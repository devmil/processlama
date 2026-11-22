//! The explorer state of one tab over one process source.
//!
//! A port of the Flutter `ProcessSession`: tree caches and filter, selection,
//! freeze and its queued snapshot, the order lock, metric histories, pins and
//! the inspector. It runs on the GUI thread and never blocks: sampling and
//! detail fetches go through its [`SessionSource`], whose results come back as
//! calls. Time is passed in as monotonic milliseconds.

use crate::history::HistorySet;
use crate::order_lock::TreeOrderLock;
pub use crate::session_types::*;
use processlama_domain::{
    AppSettings, DetailSection, HostCapabilities, HostOperatingSystem, ProcessDetail,
    ProcessIdentity, ProcessPortOwner, ProcessPorts, ProcessRecord, ProcessSnapshot,
    ProcessTopology, SearchAspect, SearchOptions, SearchQuery, SortColumn, SortDirection,
    TextMatcher, is_loopback_address,
};
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

/// How often the inspector refreshes the selection's detail while visible.
pub const INSPECTOR_DETAIL_INTERVAL_MS: u64 = 2000;

#[derive(Clone, Copy, Debug, Default)]
struct TreeMetrics {
    cpu: f64,
    gpu: f64,
    rss: u64,
    network_in: f64,
    network_out: f64,
    storage_read: f64,
    storage_write: f64,
    storage_available: bool,
    descendant_count: u64,
}

impl TreeMetrics {
    fn own(record: &ProcessRecord) -> Self {
        Self {
            cpu: record.cpu_usage,
            gpu: record.gpu_usage,
            rss: record.rss_bytes,
            network_in: record.network_in_bytes_per_second,
            network_out: record.network_out_bytes_per_second,
            storage_read: record.storage_read_bytes_per_second,
            storage_write: record.storage_write_bytes_per_second,
            storage_available: record.storage_io_available,
            descendant_count: 0,
        }
    }

    fn native(record: &ProcessRecord) -> Self {
        Self {
            cpu: record.tree_cpu_usage,
            gpu: record.tree_gpu_usage,
            rss: record.tree_rss_bytes,
            network_in: record.tree_network_in_bytes_per_second,
            network_out: record.tree_network_out_bytes_per_second,
            storage_read: record.tree_storage_read_bytes_per_second,
            storage_write: record.tree_storage_write_bytes_per_second,
            storage_available: record.tree_storage_io_available,
            descendant_count: record.descendant_count,
        }
    }

    fn add_child(&mut self, other: &Self) {
        self.cpu += other.cpu;
        self.gpu += other.gpu;
        self.rss += other.rss;
        self.network_in += other.network_in;
        self.network_out += other.network_out;
        self.storage_read += other.storage_read;
        self.storage_write += other.storage_write;
        self.storage_available |= other.storage_available;
        self.descendant_count += other.descendant_count + 1;
    }
}

/// What changed since the owner last drained [`ProcessSession::take_changes`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[allow(clippy::struct_excessive_bools)]
pub struct SessionChanges {
    pub tree: bool,
    pub inspector: bool,
    pub filter: bool,
    pub loaded_snapshot: bool,
}

pub struct ProcessSession {
    source: Box<dyn SessionSource>,
    capabilities: HostCapabilities,
    source_state: SourceState,
    background_cadence: Cadence,
    active: bool,
    initialized: bool,
    disposed: bool,
    polling_interval_ms: u32,

    filter: String,
    search_options: SearchOptions,
    chosen_aspect: SearchAspect,
    loaded_snapshot_path: Option<String>,

    expanded: HashSet<ProcessIdentity>,
    pinned: Arc<HashSet<ProcessIdentity>>,
    parent_by_identity: HashMap<ProcessIdentity, Option<ProcessIdentity>>,
    records: HashMap<ProcessIdentity, Arc<ProcessRecord>>,
    children_by_parent: HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>>,
    sorted_children_by_parent: HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>>,
    tree_metrics: HashMap<ProcessIdentity, TreeMetrics>,
    sorted_children_dirty: bool,
    cached_topology: Option<Arc<ProcessTopology>>,

    active_snapshot: Arc<ProcessSnapshot>,
    display_records: Vec<Arc<ProcessRecord>>,
    change_markers: HashMap<ProcessIdentity, ChangeMarker>,
    queued_snapshot: Option<Arc<ProcessSnapshot>>,
    selected: Option<ProcessIdentity>,
    focused: Option<ProcessIdentity>,
    focus_stack: Vec<ProcessIdentity>,
    tree_search_query: String,
    tree_search_columns: u8,
    select_first_tree_search_match_on_publish: bool,
    sort_column: SortColumn,
    sort_direction: SortDirection,
    histories: HashMap<ProcessIdentity, HistorySet>,
    cpu_scale_max: f64,
    history_gap_pending: bool,

    frozen: bool,
    window_resizing: bool,
    has_applied_initial_expansion: bool,
    order_lock: TreeOrderLock,
    selected_detail: Option<Arc<ProcessDetail>>,
    detail_generation: u64,
    next_detail_refresh: Option<u64>,

    tree: TreeView,
    inspector: InspectorView,
    changes: SessionChanges,
}

impl ProcessSession {
    pub fn new(
        source: Box<dyn SessionSource>,
        capabilities: HostCapabilities,
        source_state: SourceState,
        background_cadence: Cadence,
    ) -> Self {
        Self {
            source,
            capabilities,
            source_state,
            background_cadence,
            active: true,
            initialized: false,
            disposed: false,
            polling_interval_ms: processlama_domain::DEFAULT_POLLING_INTERVAL_MS,
            filter: String::new(),
            search_options: SearchOptions::default(),
            chosen_aspect: SearchAspect::All,
            loaded_snapshot_path: None,
            expanded: HashSet::new(),
            pinned: Arc::new(HashSet::new()),
            parent_by_identity: HashMap::new(),
            records: HashMap::new(),
            children_by_parent: HashMap::new(),
            sorted_children_by_parent: HashMap::new(),
            tree_metrics: HashMap::new(),
            sorted_children_dirty: true,
            cached_topology: None,
            active_snapshot: Arc::new(ProcessSnapshot::empty(None)),
            display_records: Vec::new(),
            change_markers: HashMap::new(),
            queued_snapshot: None,
            selected: None,
            focused: None,
            focus_stack: Vec::new(),
            tree_search_query: String::new(),
            tree_search_columns: visible_search_columns(&processlama_domain::default_visible_columns()),
            select_first_tree_search_match_on_publish: false,
            sort_column: SortColumn::TreeCpu,
            sort_direction: SortDirection::Descending,
            histories: HashMap::new(),
            cpu_scale_max: 1.0,
            history_gap_pending: false,
            frozen: false,
            window_resizing: false,
            has_applied_initial_expansion: false,
            order_lock: TreeOrderLock::default(),
            selected_detail: None,
            detail_generation: 0,
            next_detail_refresh: None,
            tree: TreeView::default(),
            inspector: InspectorView::default(),
            changes: SessionChanges::default(),
        }
    }

    // State

    pub fn tree(&self) -> &TreeView {
        &self.tree
    }

    pub fn inspector(&self) -> &InspectorView {
        &self.inspector
    }

    pub fn filter(&self) -> &str {
        &self.filter
    }

    pub fn search_options(&self) -> SearchOptions {
        self.search_options
    }

    pub fn loaded_snapshot_path(&self) -> Option<&str> {
        self.loaded_snapshot_path.as_deref()
    }

    pub fn capabilities(&self) -> HostCapabilities {
        self.capabilities
    }

    pub fn source_state(&self) -> SourceState {
        self.source_state
    }

    pub fn is_active(&self) -> bool {
        self.active
    }

    pub fn is_frozen(&self) -> bool {
        self.frozen
    }

    pub fn snapshot(&self) -> &Arc<ProcessSnapshot> {
        &self.active_snapshot
    }

    pub fn take_changes(&mut self) -> SessionChanges {
        std::mem::take(&mut self.changes)
    }

    /// A record in the current display, including exited rows still shown.
    pub fn record(&self, identity: ProcessIdentity) -> Option<&Arc<ProcessRecord>> {
        self.records.get(&identity)
    }

    /// The name a confirmation shows for `identity`.
    pub fn process_name(&self, identity: ProcessIdentity) -> String {
        if let Some(row) = self.tree.rows.iter().find(|row| row.identity == identity) {
            return row.record.name.clone();
        }
        self.active_snapshot
            .processes
            .iter()
            .find(|record| record.identity() == identity)
            .map_or_else(|| identity.pid.to_string(), |record| record.name.clone())
    }

    // Lifecycle

    pub fn initialize(&mut self, settings: &AppSettings, now: u64) {
        if self.initialized || self.disposed {
            return;
        }
        self.initialized = true;
        self.apply_settings(settings, now);
        self.refresh();
    }

    pub fn dispose(&mut self) {
        self.disposed = true;
        self.next_detail_refresh = None;
    }

    /// Marks this session's tab visible or hidden.
    pub fn set_active(&mut self, active: bool, now: u64) {
        if self.active == active || self.disposed {
            return;
        }
        self.active = active;
        self.configure_cadence();
        self.configure_detail_timer(now);
    }

    pub fn set_background_cadence(&mut self, cadence: Cadence) {
        if self.background_cadence == cadence {
            return;
        }
        self.background_cadence = cadence;
        self.configure_cadence();
    }

    pub fn set_capabilities(&mut self, capabilities: HostCapabilities) {
        if self.capabilities != capabilities {
            self.capabilities = capabilities;
            self.changes.inspector = true;
        }
    }

    pub fn set_source_state(&mut self, state: SourceState) {
        if matches!(state.phase, SourcePhase::Stale | SourcePhase::Failed) {
            self.history_gap_pending = true;
        }
        self.source_state = state;
    }

    pub fn on_settings_changed(&mut self, settings: &AppSettings, now: u64) {
        let sort_changed = self.sort_column != settings.process_sort_column
            || self.sort_direction != settings.process_sort_direction;
        let search_columns_changed =
            self.tree_search_columns != visible_search_columns(&settings.visible_columns);
        self.apply_settings(settings, now);
        if sort_changed {
            self.rebuild_sorted_children();
        }
        if sort_changed || (search_columns_changed && !self.tree_search_query.is_empty()) {
            self.publish_tree(false, false, now);
        }
    }

    fn apply_settings(&mut self, settings: &AppSettings, now: u64) {
        self.sort_column = settings.process_sort_column;
        self.sort_direction = settings.process_sort_direction;
        self.tree_search_columns = visible_search_columns(&settings.visible_columns);
        self.polling_interval_ms = settings.polling_interval_ms;
        self.configure_cadence();
        self.configure_detail_timer(now);
    }

    /// Requests a sample now, unless a snapshot is shown or the window resizes.
    pub fn refresh(&mut self) {
        if self.disposed || self.loaded_snapshot_path.is_some() || self.window_resizing {
            return;
        }
        self.source.sample_now(self.polling_interval_ms);
    }

    /// Selects the source cadence: paused for a loaded snapshot or while the
    /// window resizes, live while visible, background while hidden.
    fn configure_cadence(&mut self) {
        if self.disposed || !self.initialized {
            return;
        }
        let cadence = if self.loaded_snapshot_path.is_some() || self.window_resizing {
            Cadence::Paused
        } else if self.active {
            Cadence::Live(self.polling_interval_ms)
        } else {
            self.background_cadence
        };
        self.source.set_cadence(cadence, self.polling_interval_ms);
    }

    fn configure_detail_timer(&mut self, now: u64) {
        self.next_detail_refresh = if self.disposed
            || !self.initialized
            || self.loaded_snapshot_path.is_some()
            || !self.active
        {
            None
        } else {
            Some(now + INSPECTOR_DETAIL_INTERVAL_MS)
        };
    }

    // Timers

    pub fn next_deadline(&self) -> Option<u64> {
        match (self.order_lock.next_deadline(), self.next_detail_refresh) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    pub fn on_time(&mut self, now: u64) {
        if self.order_lock.on_time(now) {
            self.publish_tree(true, false, now);
        }
        if self.next_detail_refresh.is_some_and(|at| at <= now) {
            self.next_detail_refresh = Some(now + INSPECTOR_DETAIL_INTERVAL_MS);
            self.refresh_inspector_detail();
        }
    }

    // Samples

    pub fn on_sample(&mut self, next: Arc<ProcessSnapshot>, now: u64) {
        if self.disposed || self.loaded_snapshot_path.is_some() || self.window_resizing {
            return;
        }
        if self.frozen && self.has_structural_change(&self.active_snapshot, &next) {
            self.queued_snapshot = Some(Arc::clone(&next));
            let merged = self.merge_metrics_keeping_structure(&next);
            self.active_snapshot = Arc::new(merged);
            self.display_records = self.active_snapshot.processes.clone();
            self.change_markers.clear();
            self.rebuild_tree_caches(true);
            self.publish_tree(true, true, now);
        } else {
            self.apply_snapshot(next, now);
        }
    }

    fn apply_snapshot(&mut self, next: Arc<ProcessSnapshot>, now: u64) {
        let first = self.active_snapshot.processes.is_empty();
        let mut markers = HashMap::new();
        let mut display: Vec<Arc<ProcessRecord>> = next.processes.clone();
        if !first {
            let previous: HashMap<ProcessIdentity, &Arc<ProcessRecord>> = self
                .active_snapshot
                .processes
                .iter()
                .map(|record| (record.identity(), record))
                .collect();
            let next_ids: HashSet<ProcessIdentity> =
                next.processes.iter().map(|record| record.identity()).collect();
            for identity in &next_ids {
                if !previous.contains_key(identity) {
                    markers.insert(*identity, ChangeMarker::Spawned);
                }
            }
            for record in &self.active_snapshot.processes {
                let identity = record.identity();
                if !next_ids.contains(&identity) {
                    markers.insert(identity, ChangeMarker::Terminated);
                    display.push(Arc::clone(record));
                }
            }
        }
        self.active_snapshot = next;
        self.display_records = display;
        self.change_markers = markers;
        self.rebuild_tree_caches(true);
        self.publish_tree(true, true, now);
        let detail_identity = self.selected_detail.as_ref().map(|detail| detail.identity);
        if detail_identity != self.selected {
            self.refresh_inspector_detail();
        }
    }

    // Snapshots

    /// Shows a loaded snapshot document instead of live data.
    pub fn load_snapshot(&mut self, path: String, snapshot: Arc<ProcessSnapshot>, now: u64) {
        self.next_detail_refresh = None;
        self.selected_detail = None;
        self.detail_generation += 1;
        self.loaded_snapshot_path = Some(path);
        self.queued_snapshot = None;
        self.frozen = false;
        self.order_lock.reset_interaction(now);
        self.source.set_cadence(Cadence::Paused, self.polling_interval_ms);
        self.changes.loaded_snapshot = true;
        // A loaded snapshot replaces the tree outright: nothing spawned or exited.
        self.active_snapshot = Arc::new(ProcessSnapshot::empty(None));
        self.apply_snapshot(snapshot, now);
    }

    pub fn show_live(&mut self, now: u64) {
        if self.loaded_snapshot_path.is_none() {
            return;
        }
        self.loaded_snapshot_path = None;
        self.queued_snapshot = None;
        self.frozen = false;
        self.order_lock.reset_interaction(now);
        self.changes.loaded_snapshot = true;
        // The first live sample replaces the snapshot outright, without
        // marking every difference as spawned or exited.
        self.active_snapshot = Arc::new(ProcessSnapshot::empty(None));
        self.configure_cadence();
        self.configure_detail_timer(now);
        self.refresh();
    }

    // Filter and search

    pub fn set_filter(&mut self, value: &str, now: u64) {
        let mut options = self.search_options;
        // A prefix-chosen aspect ends with its query: when the text is cleared,
        // or a port search no longer holds a port number.
        if options.aspect != self.chosen_aspect {
            let query = SearchQuery::new(value.trim(), options);
            let keep = if options.aspect == SearchAspect::Port {
                query.port().is_some()
            } else {
                !query.text.is_empty()
            };
            if !keep {
                options = options.with_aspect(self.chosen_aspect);
            }
        }
        let parsed = SearchQuery::parse(value, options);
        self.apply_filter(parsed.text, parsed.options, now);
    }

    pub fn set_search_aspect(&mut self, aspect: SearchAspect, now: u64) {
        self.chosen_aspect = aspect;
        let text = self.filter.clone();
        self.apply_filter(text, self.search_options.with_aspect(aspect), now);
    }

    /// Filters the tree to the processes using `port`.
    pub fn show_port(&mut self, port: u16, now: u64) {
        self.apply_filter(port.to_string(), self.search_options.with_aspect(SearchAspect::Port), now);
    }

    fn apply_filter(&mut self, text: String, options: SearchOptions, now: u64) {
        let aspect_changed = options.aspect != self.search_options.aspect;
        if self.filter == text && !aspect_changed {
            return;
        }
        if aspect_changed {
            self.search_options = options;
        }
        self.filter = text;
        self.changes.filter = true;
        self.publish_tree(false, false, now);
    }

    pub fn set_search_match_case(&mut self, value: bool, now: u64) {
        if self.search_options.match_case == value {
            return;
        }
        self.search_options.match_case = value;
        self.changes.filter = true;
        self.publish_tree(false, false, now);
    }

    pub fn set_search_whole_word(&mut self, value: bool, now: u64) {
        if self.search_options.whole_word == value {
            return;
        }
        self.search_options.whole_word = value;
        self.changes.filter = true;
        self.publish_tree(false, false, now);
    }

    pub fn set_tree_search(&mut self, value: &str, now: u64) {
        let next = value.trim();
        if self.tree_search_query == next {
            return;
        }
        self.tree_search_query = next.to_owned();
        self.select_first_tree_search_match_on_publish = !next.is_empty();
        self.publish_tree(false, false, now);
    }

    pub fn select_next_tree_search_match(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        self.select_tree_search_offset(1, now);
    }

    pub fn select_previous_tree_search_match(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        self.select_tree_search_offset(-1, now);
    }

    // Selection and expansion

    pub fn toggle_expansion(&mut self, identity: ProcessIdentity, now: u64) {
        self.mark_tree_interaction(now);
        if !self.expanded.remove(&identity) {
            self.expanded.insert(identity);
        }
        self.publish_tree(true, false, now);
    }

    pub fn select_process(&mut self, identity: ProcessIdentity, now: u64) {
        self.mark_tree_interaction(now);
        self.select_identity(identity, now);
    }

    pub fn select_next_visible(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        self.select_visible_offset(1, now);
    }

    pub fn select_previous_visible(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        self.select_visible_offset(-1, now);
    }

    pub fn mark_tree_interaction(&mut self, now: u64) {
        if self.loaded_snapshot_path.is_some() {
            return;
        }
        if self.order_lock.mark_interaction(now) {
            self.publish_tree(true, false, now);
        }
    }

    pub fn expand_selected(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        let Some(row) = self.selected_visible_row() else {
            return;
        };
        if !row.has_children {
            return;
        }
        self.expanded.insert(row.identity);
        self.publish_tree(true, false, now);
    }

    pub fn collapse_selected(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        let Some(row) = self.selected_visible_row() else {
            return;
        };
        if row.is_expanded {
            self.expanded.remove(&row.identity);
            self.publish_tree(true, false, now);
            return;
        }
        if let Some(Some(parent)) = self.parent_by_identity.get(&row.identity).copied() {
            self.select_identity(parent, now);
        }
    }

    pub fn expand_selected_subtree(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        let Some(row) = self.selected_visible_row() else {
            return;
        };
        let subtree = self.subtree_identities(row.identity);
        self.expanded.extend(subtree);
        self.publish_tree(true, false, now);
    }

    pub fn collapse_selected_subtree(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        let Some(row) = self.selected_visible_row() else {
            return;
        };
        for identity in self.subtree_identities(row.identity) {
            self.expanded.remove(&identity);
        }
        self.publish_tree(true, false, now);
    }

    pub fn focus_selected_subtree(&mut self, now: u64) {
        self.mark_tree_interaction(now);
        if let Some(identity) = self.selected {
            self.focus_subtree(identity, now);
        }
    }

    pub fn focus_subtree(&mut self, identity: ProcessIdentity, now: u64) {
        if !self.records.contains_key(&identity) || Some(identity) == self.focused {
            return;
        }
        match self.focused {
            Some(current) if self.subtree_identities(current).contains(&identity) => {
                self.focus_stack.push(current);
            }
            _ => self.focus_stack.clear(),
        }
        self.focused = Some(identity);
        self.selected = Some(identity);
        self.expanded.insert(identity);
        self.publish_tree(false, false, now);
    }

    pub fn clear_subtree_focus(&mut self, now: u64) {
        let Some(former) = self.focused.take() else {
            return;
        };
        self.focus_stack.clear();
        self.selected = Some(former);
        self.publish_tree(false, false, now);
    }

    pub fn pop_subtree_focus(&mut self, now: u64) {
        let Some(former) = self.focused else {
            return;
        };
        let next = self.focus_stack.pop();
        self.focused = next;
        self.selected = Some(next.unwrap_or(former));
        if let Some(next) = next {
            self.expanded.insert(next);
        }
        self.publish_tree(false, false, now);
    }

    /// Sorts by `column`, flipping the direction when it already sorts.
    /// Returns the new sort for persistence.
    pub fn sort_by(&mut self, column: SortColumn, now: u64) -> (SortColumn, SortDirection) {
        if self.sort_column == column {
            self.sort_direction = self.sort_direction.flipped();
        } else {
            self.sort_column = column;
            self.sort_direction = column.default_direction();
        }
        self.rebuild_sorted_children();
        self.publish_tree(false, false, now);
        (self.sort_column, self.sort_direction)
    }

    pub fn toggle_pin(&mut self, identity: ProcessIdentity, now: u64) {
        self.mark_tree_interaction(now);
        let pinned = Arc::make_mut(&mut self.pinned);
        if !pinned.remove(&identity) {
            pinned.insert(identity);
        }
        self.publish_tree(true, false, now);
    }

    pub fn set_tree_hovering(&mut self, hovering: bool, now: u64) {
        if self.order_lock.set_hovering(hovering, now) {
            self.publish_tree(true, false, now);
        }
    }

    pub fn set_tree_context_menu_open(&mut self, open: bool, now: u64) {
        if self.order_lock.set_context_menu_open(open, now) {
            self.publish_tree(true, false, now);
        }
    }

    pub fn set_modal_overlay_open(&mut self, open: bool, now: u64) {
        if self.order_lock.set_modal_overlay_open(open, now) {
            self.publish_tree(true, false, now);
        }
    }

    pub fn set_window_resizing(&mut self, resizing: bool) {
        if self.window_resizing == resizing {
            return;
        }
        self.window_resizing = resizing;
        self.configure_cadence();
    }

    pub fn set_frozen(&mut self, frozen: bool, now: u64) {
        if self.frozen == frozen {
            return;
        }
        self.frozen = frozen;
        if !frozen && let Some(queued) = self.queued_snapshot.take() {
            self.apply_snapshot(queued, now);
            return;
        }
        self.publish_tree(true, false, now);
    }

    pub fn toggle_frozen(&mut self, now: u64) {
        self.set_frozen(!self.frozen, now);
    }

    // Inspector detail

    pub fn on_detail(&mut self, identity: ProcessIdentity, generation: u64, detail: Option<ProcessDetail>) {
        let Some(detail) = detail else {
            return;
        };
        if self.selected == Some(identity) && self.detail_generation == generation {
            self.selected_detail = Some(Arc::new(detail));
            self.publish_inspector();
        }
    }

    fn refresh_inspector_detail(&mut self) {
        if self.loaded_snapshot_path.is_some() {
            return;
        }
        let Some(identity) = self.selected else {
            return;
        };
        if !self.records.contains_key(&identity) {
            return;
        }
        self.source.fetch_detail(identity, self.detail_generation);
    }

    fn select_identity(&mut self, identity: ProcessIdentity, now: u64) {
        if self.selected == Some(identity) {
            return;
        }
        self.selected = Some(identity);
        self.selected_detail = None;
        self.detail_generation += 1;
        self.publish_tree(true, false, now);
        self.refresh_inspector_detail();
    }

    fn select_visible_offset(&mut self, offset: i64, now: u64) {
        let rows: Vec<ProcessIdentity> = self
            .tree
            .rows
            .iter()
            .filter(|row| !row.is_terminated())
            .map(|row| row.identity)
            .collect();
        if rows.is_empty() {
            return;
        }
        let current = self
            .selected
            .and_then(|selected| rows.iter().position(|identity| *identity == selected))
            .map_or(-1, |index| index as i64);
        let next = (current + offset).clamp(0, rows.len() as i64 - 1) as usize;
        self.select_identity(rows[next], now);
    }

    fn select_tree_search_offset(&mut self, offset: i64, now: u64) {
        if self.tree_search_query.is_empty() {
            return;
        }
        let rows: Vec<ProcessIdentity> = self
            .tree
            .rows
            .iter()
            .filter(|row| row.matches_tree_search() && !row.is_terminated())
            .map(|row| row.identity)
            .collect();
        if rows.is_empty() {
            return;
        }
        let count = rows.len() as i64;
        let current = self
            .selected
            .and_then(|selected| rows.iter().position(|identity| *identity == selected));
        let next = match current {
            None => {
                if offset < 0 {
                    count - 1
                } else {
                    0
                }
            }
            Some(index) => (index as i64 + offset).rem_euclid(count),
        };
        self.select_identity(rows[next as usize], now);
    }

    fn selected_visible_row(&self) -> Option<TreeRow> {
        let selected = self.selected?;
        self.tree.rows.iter().find(|row| row.identity == selected).cloned()
    }

    fn subtree_identities(&self, root: ProcessIdentity) -> HashSet<ProcessIdentity> {
        let mut identities = HashSet::new();
        let mut pending = vec![root];
        while let Some(identity) = pending.pop() {
            if !identities.insert(identity) {
                continue;
            }
            if let Some(children) = self.children_by_parent.get(&Some(identity)) {
                pending.extend(children.iter().copied());
            }
        }
        identities
    }

    // Caches

    fn rebuild_tree_caches(&mut self, record_metrics: bool) {
        let records: HashMap<ProcessIdentity, Arc<ProcessRecord>> = self
            .display_records
            .iter()
            .map(|record| (record.identity(), Arc::clone(record)))
            .collect();
        let native = self.active_snapshot.topology.clone();
        let use_native = native.as_ref().is_some_and(|topology| {
            !self.change_markers.values().any(|marker| *marker == ChangeMarker::Terminated)
                && topology.parent_by_identity.len() == records.len()
        });
        let topology_changed;
        if use_native {
            let topology = native.expect("checked above");
            topology_changed = !self
                .cached_topology
                .as_ref()
                .is_some_and(|cached| Arc::ptr_eq(cached, &topology));
            if topology_changed {
                self.children_by_parent = topology.children_by_parent.clone();
                self.parent_by_identity = topology.parent_by_identity.clone();
            }
            self.cached_topology = Some(topology);
        } else {
            topology_changed = self.cached_topology.is_some()
                || !self.change_markers.is_empty()
                || records.len() != self.records.len()
                || records.iter().any(|(identity, record)| {
                    self.records.get(identity).map(|cached| cached.ppid) != Some(record.ppid)
                });
            if topology_changed {
                let parents = self.parent_links(&self.display_records);
                let mut children: HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>> =
                    HashMap::new();
                for record in &self.display_records {
                    let identity = record.identity();
                    if let Some(parent) = parents.get(&identity) {
                        children.entry(*parent).or_default().push(identity);
                    }
                }
                self.children_by_parent = children;
                self.parent_by_identity = parents;
            }
            self.cached_topology = None;
        }
        self.sorted_children_dirty |= topology_changed || !self.sort_column.is_stable();
        self.records = records;
        self.rebuild_tree_metrics(record_metrics);
    }

    fn rebuild_tree_metrics(&mut self, record_metrics: bool) {
        self.tree_metrics = self.compute_tree_metrics();
        if record_metrics {
            self.record_histories();
        }
    }

    fn compute_tree_metrics(&self) -> HashMap<ProcessIdentity, TreeMetrics> {
        let mut memo: HashMap<ProcessIdentity, TreeMetrics> = HashMap::with_capacity(self.records.len());
        // Post-order over every identity without recursion.
        for root in self.records.keys() {
            if memo.contains_key(root) {
                continue;
            }
            let mut stack: Vec<(ProcessIdentity, bool)> = vec![(*root, false)];
            while let Some((identity, children_done)) = stack.pop() {
                if memo.contains_key(&identity) {
                    continue;
                }
                let record = self.records.get(&identity);
                if let Some(record) = record
                    && record.has_native_tree_metrics()
                {
                    memo.insert(identity, TreeMetrics::native(record));
                    continue;
                }
                let children = self
                    .children_by_parent
                    .get(&Some(identity))
                    .map_or(&[][..], Vec::as_slice);
                if !children_done {
                    stack.push((identity, true));
                    for child in children {
                        if !memo.contains_key(child) {
                            stack.push((*child, false));
                        }
                    }
                    continue;
                }
                let mut total = record.map_or_else(TreeMetrics::default, |record| TreeMetrics::own(record));
                for child in children {
                    if let Some(metrics) = memo.get(child) {
                        total.add_child(metrics);
                    }
                }
                memo.insert(identity, total);
            }
        }
        memo
    }

    fn record_histories(&mut self) {
        let gap = std::mem::take(&mut self.history_gap_pending);
        let mut cpu_scale_max: f32 = 1.0;
        for (identity, record) in &self.records {
            let Some(metrics) = self.tree_metrics.get(identity) else {
                continue;
            };
            let set = self.histories.entry(*identity).or_default();
            if gap && !set.tree_cpu.is_empty() {
                set.add_gap();
            }
            set.tree_cpu.add(metrics.cpu as f32);
            cpu_scale_max = cpu_scale_max.max(set.tree_cpu.max());
            set.cpu.add(record.cpu_usage as f32);
            set.gpu.add(record.gpu_usage as f32);
            set.rss.add(record.rss_bytes as f32);
            set.network_in.add(record.network_in_bytes_per_second as f32);
            set.network_out.add(record.network_out_bytes_per_second as f32);
            set.storage_read.add(record.storage_read_bytes_per_second as f32);
            set.storage_write.add(record.storage_write_bytes_per_second as f32);
            set.tree_gpu.add(metrics.gpu as f32);
            set.tree_rss.add(metrics.rss as f32);
            set.tree_network_in.add(metrics.network_in as f32);
            set.tree_network_out.add(metrics.network_out as f32);
            set.tree_storage_read.add(metrics.storage_read as f32);
            set.tree_storage_write.add(metrics.storage_write as f32);
        }
        let records = &self.records;
        self.histories.retain(|identity, _| records.contains_key(identity));
        self.cpu_scale_max = f64::from(cpu_scale_max);
    }

    fn rebuild_sorted_children(&mut self) {
        self.sorted_children_dirty = false;
        let mut sorted = self.children_by_parent.clone();
        for children in sorted.values_mut() {
            children.sort_by(|left, right| self.compare_identities(*left, *right));
        }
        self.sorted_children_by_parent = sorted;
    }

    fn ordered_children_for_visible_order(
        &self,
        previous: &HashMap<ProcessIdentity, usize>,
    ) -> HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>> {
        let mut ordered = self.children_by_parent.clone();
        for children in ordered.values_mut() {
            children.sort_by(|left, right| match (previous.get(left), previous.get(right)) {
                (None, None) => self.compare_identities(*left, *right),
                (None, Some(_)) => Ordering::Greater,
                (Some(_), None) => Ordering::Less,
                (Some(a), Some(b)) => a.cmp(b),
            });
        }
        ordered
    }

    fn compare_identities(&self, left: ProcessIdentity, right: ProcessIdentity) -> Ordering {
        let (Some(l), Some(r)) = (self.records.get(&left), self.records.get(&right)) else {
            return compare_by_pid(left, right);
        };
        let lm = self.tree_metrics.get(&left);
        let rm = self.tree_metrics.get(&right);
        let f = |a: f64, b: f64| a.partial_cmp(&b).unwrap_or(Ordering::Equal);
        let base = match self.sort_column {
            SortColumn::Tree => compare_by_pid(left, right),
            SortColumn::Pid => l.pid.cmp(&r.pid),
            SortColumn::Name => l.display_name().to_lowercase().cmp(&r.display_name().to_lowercase()),
            SortColumn::Cpu => f(l.cpu_usage, r.cpu_usage),
            SortColumn::TreeCpu => f(lm.map_or(l.cpu_usage, |m| m.cpu), rm.map_or(r.cpu_usage, |m| m.cpu)),
            SortColumn::Gpu => f(l.gpu_usage, r.gpu_usage),
            SortColumn::TreeGpu => f(lm.map_or(l.gpu_usage, |m| m.gpu), rm.map_or(r.gpu_usage, |m| m.gpu)),
            SortColumn::Memory => l.rss_bytes.cmp(&r.rss_bytes),
            SortColumn::TreeMemory => lm.map_or(l.rss_bytes, |m| m.rss).cmp(&rm.map_or(r.rss_bytes, |m| m.rss)),
            SortColumn::NetworkIn => f(l.network_in_bytes_per_second, r.network_in_bytes_per_second),
            SortColumn::NetworkOut => f(l.network_out_bytes_per_second, r.network_out_bytes_per_second),
            SortColumn::TreeNetworkIn => f(
                lm.map_or(l.network_in_bytes_per_second, |m| m.network_in),
                rm.map_or(r.network_in_bytes_per_second, |m| m.network_in),
            ),
            SortColumn::TreeNetworkOut => f(
                lm.map_or(l.network_out_bytes_per_second, |m| m.network_out),
                rm.map_or(r.network_out_bytes_per_second, |m| m.network_out),
            ),
            SortColumn::StorageRead => f(l.storage_read_bytes_per_second, r.storage_read_bytes_per_second),
            SortColumn::StorageWrite => f(l.storage_write_bytes_per_second, r.storage_write_bytes_per_second),
            SortColumn::TreeStorageRead => f(
                lm.map_or(l.storage_read_bytes_per_second, |m| m.storage_read),
                rm.map_or(r.storage_read_bytes_per_second, |m| m.storage_read),
            ),
            SortColumn::TreeStorageWrite => f(
                lm.map_or(l.storage_write_bytes_per_second, |m| m.storage_write),
                rm.map_or(r.storage_write_bytes_per_second, |m| m.storage_write),
            ),
            SortColumn::StartTime => l.start_time_unix_ms.cmp(&r.start_time_unix_ms),
            SortColumn::Status => l.status.name().cmp(r.status.name()),
            SortColumn::Uid => l.uid.cmp(&r.uid),
            SortColumn::Ports => compare_ports(l, r),
        };
        let ordered = match self.sort_direction {
            SortDirection::Ascending => base,
            SortDirection::Descending => base.reverse(),
        };
        if ordered == Ordering::Equal {
            compare_by_pid(left, right)
        } else {
            ordered
        }
    }

    fn parent_links(&self, records: &[Arc<ProcessRecord>]) -> HashMap<ProcessIdentity, Option<ProcessIdentity>> {
        let mut by_pid: HashMap<i32, ProcessIdentity> = HashMap::with_capacity(records.len());
        for record in records {
            let identity = record.identity();
            let terminated = self.change_markers.get(&identity) == Some(&ChangeMarker::Terminated);
            match by_pid.get(&identity.pid) {
                None => {
                    by_pid.insert(identity.pid, identity);
                }
                Some(existing) => {
                    let existing_terminated =
                        self.change_markers.get(existing) == Some(&ChangeMarker::Terminated);
                    if existing_terminated && !terminated {
                        by_pid.insert(identity.pid, identity);
                    }
                }
            }
        }
        records
            .iter()
            .map(|record| {
                let parent = if record.ppid == record.pid {
                    None
                } else {
                    by_pid.get(&record.ppid).copied()
                };
                (record.identity(), parent)
            })
            .collect()
    }

    fn has_structural_change(&self, current: &ProcessSnapshot, next: &ProcessSnapshot) -> bool {
        if current.processes.is_empty() {
            return false;
        }
        if let (Some(a), Some(b)) = (&current.topology, &next.topology)
            && Arc::ptr_eq(a, b)
        {
            return false;
        }
        let current_parents = current
            .topology
            .as_ref()
            .map_or_else(|| self.parent_links(&current.processes), |t| t.parent_by_identity.clone());
        let next_parents = next
            .topology
            .as_ref()
            .map_or_else(|| self.parent_links(&next.processes), |t| t.parent_by_identity.clone());
        if current_parents.len() != next_parents.len() {
            return true;
        }
        current_parents
            .iter()
            .any(|(identity, parent)| next_parents.get(identity) != Some(parent))
    }

    fn merge_metrics_keeping_structure(&self, metrics: &ProcessSnapshot) -> ProcessSnapshot {
        let by_identity: HashMap<ProcessIdentity, &Arc<ProcessRecord>> = metrics
            .processes
            .iter()
            .map(|record| (record.identity(), record))
            .collect();
        let current = &self.active_snapshot;
        let processes: Vec<Arc<ProcessRecord>> = current
            .processes
            .iter()
            .map(|record| match by_identity.get(&record.identity()) {
                None => Arc::clone(record),
                Some(updated) if updated.ppid == record.ppid => Arc::clone(updated),
                Some(updated) => {
                    let mut copy = (***updated).clone();
                    copy.ppid = record.ppid;
                    Arc::new(copy)
                }
            })
            .collect();
        let topology = current.topology.clone().unwrap_or_else(|| {
            let parents = self.parent_links(&current.processes);
            let order: Vec<ProcessIdentity> = current.processes.iter().map(|r| r.identity()).collect();
            Arc::new(ProcessTopology::new(None, parents, &order))
        });
        ProcessSnapshot {
            generated_at_unix_ms: metrics.generated_at_unix_ms,
            platform: metrics.platform.clone(),
            processes,
            error: metrics.error.clone(),
            topology: Some(topology),
        }
    }

    // Publication

    fn previous_visible_order(&self) -> HashMap<ProcessIdentity, usize> {
        self.tree
            .rows
            .iter()
            .enumerate()
            .map(|(index, row)| (row.identity, index))
            .collect()
    }

    fn publish_tree(&mut self, allow_interaction_order_lock: bool, record_metrics: bool, _now: u64) {
        let previous_order = self.previous_visible_order();
        let order_locked_by_interaction =
            allow_interaction_order_lock && self.order_lock.locked() && !previous_order.is_empty();
        let order_frozen = allow_interaction_order_lock && self.frozen && !previous_order.is_empty();
        if self.records.len() != self.display_records.len() {
            self.rebuild_tree_caches(record_metrics);
        }
        let preserve = order_locked_by_interaction || order_frozen;
        let rows = self.build_tree_rows(preserve, &previous_order);

        let mut matches = rows
            .iter()
            .filter(|row| row.matches_tree_search() && !row.is_terminated())
            .map(|row| row.identity);
        if self.select_first_tree_search_match_on_publish {
            if let Some(first) = matches.clone().next() {
                self.selected = Some(first);
            }
            self.select_first_tree_search_match_on_publish = false;
        }
        let match_count = matches.clone().count();
        if self.selected.is_none_or(|selected| !rows.iter().any(|row| row.identity == selected)) {
            self.selected = rows.iter().find(|row| !row.is_terminated()).map(|row| row.identity);
        }
        let selected_match_index = self
            .selected
            .and_then(|selected| matches.position(|identity| identity == selected))
            .map_or(-1, |index| index as i64);

        self.tree = TreeView {
            snapshot: Arc::clone(&self.active_snapshot),
            rows: Arc::new(rows),
            selected: self.selected,
            filter: self.filter.clone(),
            tree_search_query: self.tree_search_query.clone(),
            tree_search_match_count: match_count,
            tree_search_selected_match_index: selected_match_index,
            search_options: self.search_options,
            lock: TreeLockState {
                is_frozen: self.frozen,
                has_queued_structural_mutations: self.queued_snapshot.is_some(),
                queued_process_count: self.queued_snapshot.as_ref().map_or(0, |s| s.processes.len()),
                is_order_locked_by_interaction: order_locked_by_interaction,
            },
            sort_column: self.sort_column,
            sort_direction: self.sort_direction,
            pinned: Arc::clone(&self.pinned),
            focused: self.focused,
            focus_stack_depth: self.focus_stack.len(),
            focused_name: self
                .focused
                .and_then(|identity| self.records.get(&identity).map(|record| record.name.clone())),
            cpu_scale_max: self.cpu_scale_max,
        };
        self.changes.tree = true;
        self.publish_inspector();
    }

    fn build_tree_rows(
        &mut self,
        preserve_previous_order: bool,
        previous_order: &HashMap<ProcessIdentity, usize>,
    ) -> Vec<TreeRow> {
        if !preserve_previous_order && self.sorted_children_dirty {
            self.rebuild_sorted_children();
        }
        let ordered;
        let children_by_parent = if preserve_previous_order {
            ordered = self.ordered_children_for_visible_order(previous_order);
            &ordered
        } else {
            &self.sorted_children_by_parent
        };
        let roots: Vec<ProcessIdentity> = children_by_parent.get(&None).cloned().unwrap_or_default();
        if let Some(focused) = self.focused
            && !self.records.contains_key(&focused)
        {
            self.focused = None;
            self.focus_stack.clear();
        }
        let visible_roots = match self.focused {
            Some(focused) => vec![focused],
            None => roots.clone(),
        };
        if !self.has_applied_initial_expansion && !roots.is_empty() {
            self.expanded.extend(roots.iter().copied());
            if self.capabilities.operating_system == HostOperatingSystem::Linux {
                for root in &roots {
                    if self.records.get(root).is_some_and(|record| record.name == "systemd") {
                        for child in children_by_parent.get(&Some(*root)).map_or(&[][..], Vec::as_slice) {
                            if self.records.get(child).is_some_and(|record| record.name == "systemd") {
                                self.expanded.insert(*child);
                            }
                        }
                    }
                }
            }
            self.has_applied_initial_expansion = true;
        }

        let filter = SearchQuery::new(self.filter.clone(), self.search_options);
        let has_filter = !filter.text.is_empty();
        let search = TextMatcher::new(
            &self.tree_search_query,
            self.search_options.match_case,
            self.search_options.whole_word,
        );
        let has_search = !search.is_empty();
        let records = &self.records;

        let mut filter_memo: HashMap<ProcessIdentity, bool> = HashMap::new();
        let mut search_memo: HashMap<ProcessIdentity, bool> = HashMap::new();
        let record_matches = |record: &ProcessRecord| !has_filter || filter.matches(record);
        let record_matches_search = |record: &ProcessRecord| {
            has_search
                && search.matches_any([
                    record.display_name(),
                    record.pid.to_string().as_str(),
                    record.executable_path.as_str(),
                    record.command_line.as_str(),
                    record.app_bundle_path.as_str(),
                ])
        };

        fn descendant_matches(
            identity: ProcessIdentity,
            children: &HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>>,
            records: &HashMap<ProcessIdentity, Arc<ProcessRecord>>,
            memo: &mut HashMap<ProcessIdentity, bool>,
            matches: &dyn Fn(&ProcessRecord) -> bool,
        ) -> bool {
            if let Some(cached) = memo.get(&identity) {
                return *cached;
            }
            let mut result = false;
            for child in children.get(&Some(identity)).map_or(&[][..], Vec::as_slice) {
                if records.get(child).is_some_and(|record| matches(record))
                    || descendant_matches(*child, children, records, memo, matches)
                {
                    result = true;
                    break;
                }
            }
            memo.insert(identity, result);
            result
        }

        let search_columns = self.tree_search_columns;
        let mut rows = Vec::with_capacity(records.len().min(4096));
        // Preorder with an explicit stack: (identity, depth, ancestor matched).
        let mut stack: Vec<(ProcessIdentity, u32, bool)> =
            visible_roots.iter().rev().map(|root| (*root, 0, false)).collect();
        while let Some((identity, depth, ancestor_matched)) = stack.pop() {
            let Some(record) = records.get(&identity) else {
                continue;
            };
            let children = children_by_parent.get(&Some(identity)).map_or(&[][..], Vec::as_slice);
            let has_children = !children.is_empty();
            let expanded = self.expanded.contains(&identity);
            let matches = record_matches(record);
            let matched_columns = if has_search {
                search_column_bits(record, &search, search_columns)
            } else {
                0
            };
            let descendant = has_filter
                && descendant_matches(identity, children_by_parent, records, &mut filter_memo, &record_matches);
            let force_for_filter = has_filter && has_children;
            let force_for_search = has_search
                && has_children
                && descendant_matches(identity, children_by_parent, records, &mut search_memo, &record_matches_search);
            let force_expanded = force_for_filter || force_for_search;
            if !(!has_filter || matches || descendant || ancestor_matched) {
                continue;
            }
            let metrics = self.tree_metrics.get(&identity).copied();
            let cpu_history = self
                .histories
                .get_mut(&identity)
                .map_or_else(|| Arc::from(Vec::<f32>::new()), |set| set.tree_cpu.as_list());
            rows.push(TreeRow {
                identity,
                record: Arc::clone(record),
                depth,
                has_children,
                is_expanded: expanded || force_expanded,
                tree_cpu: metrics.map_or(record.cpu_usage, |m| m.cpu),
                tree_gpu: metrics.map_or(record.gpu_usage, |m| m.gpu),
                tree_rss: metrics.map_or(record.rss_bytes, |m| m.rss),
                tree_network_in: metrics.map_or(record.network_in_bytes_per_second, |m| m.network_in),
                tree_network_out: metrics.map_or(record.network_out_bytes_per_second, |m| m.network_out),
                tree_storage_read: metrics.map_or(record.storage_read_bytes_per_second, |m| m.storage_read),
                tree_storage_write: metrics.map_or(record.storage_write_bytes_per_second, |m| m.storage_write),
                tree_storage_available: metrics.map_or(record.storage_io_available, |m| m.storage_available),
                descendant_count: metrics.map_or(0, |m| m.descendant_count),
                matches_filter: !has_filter || matches,
                preserves_filter_branch: has_filter && !matches,
                search_columns: matched_columns,
                change_marker: self.change_markers.get(&identity).copied().unwrap_or_default(),
                cpu_history,
            });
            if force_expanded || expanded {
                for child in children.iter().rev() {
                    stack.push((*child, depth + 1, ancestor_matched || matches));
                }
            }
        }
        rows
    }

    fn publish_inspector(&mut self) {
        let Some(selected) = self.selected else {
            self.inspector = InspectorView::default();
            self.changes.inspector = true;
            return;
        };
        let Some(row) = self.tree.rows.iter().find(|row| row.identity == selected).cloned() else {
            self.inspector = InspectorView::default();
            self.changes.inspector = true;
            return;
        };
        let detail = self
            .selected_detail
            .as_ref()
            .filter(|detail| detail.identity == selected)
            .cloned();
        let histories = self.histories.get_mut(&selected).map(|set| SelectedHistories {
            tree_cpu: set.tree_cpu.as_list(),
            tree_gpu: set.tree_gpu.as_list(),
            tree_rss: set.tree_rss.as_list(),
            tree_network_in: set.tree_network_in.as_list(),
            tree_network_out: set.tree_network_out.as_list(),
            tree_storage_read: set.tree_storage_read.as_list(),
            tree_storage_write: set.tree_storage_write.as_list(),
            cpu: set.cpu.as_list(),
            gpu: set.gpu.as_list(),
            rss: set.rss.as_list(),
            network_in: set.network_in.as_list(),
            network_out: set.network_out.as_list(),
            storage_read: set.storage_read.as_list(),
            storage_write: set.storage_write.as_list(),
        });
        self.inspector = InspectorView {
            process: Some(Arc::clone(&row.record)),
            identity: Some(selected),
            change_marker: row.change_marker,
            ports: ProcessPorts::of_record(&row.record),
            tree_ports: self.subtree_ports(selected),
            listener_owners_by_port: self.listener_owners_of_peers(selected, detail.as_deref()),
            platform: self.active_snapshot.platform.clone(),
            detail,
            row: Some(row),
            histories,
        };
        self.changes.inspector = true;
    }

    fn subtree_ports(&self, root: ProcessIdentity) -> Option<ProcessPorts> {
        let mut pending = vec![root];
        let mut visited = HashSet::new();
        let mut sources: Vec<(Arc<[u16]>, Option<Arc<[u16]>>)> = Vec::new();
        while let Some(identity) = pending.pop() {
            if !visited.insert(identity) {
                continue;
            }
            if let Some(children) = self.children_by_parent.get(&Some(identity)) {
                pending.extend(children.iter().copied());
            }
            if self.change_markers.get(&identity) == Some(&ChangeMarker::Terminated) {
                continue;
            }
            if let Some(record) = self.records.get(&identity)
                && let Some(local) = &record.local_ports
            {
                sources.push((Arc::clone(local), record.listening_ports.clone()));
            }
        }
        if sources.is_empty() {
            return None;
        }
        Some(ProcessPorts::merge(
            sources.iter().map(|(local, listening)| (local.as_ref(), listening.as_deref())),
        ))
    }

    fn listener_owners_of_peers(
        &self,
        selected: ProcessIdentity,
        detail: Option<&ProcessDetail>,
    ) -> BTreeMap<u16, Vec<ProcessPortOwner>> {
        let Some(DetailSection::Available(sockets)) = detail.map(|detail| &detail.sockets) else {
            return BTreeMap::new();
        };
        let peer_ports: HashSet<u16> = sockets
            .iter()
            .filter(|endpoint| endpoint.remote_port != 0 && is_loopback_address(&endpoint.remote_address))
            .map(|endpoint| endpoint.remote_port)
            .collect();
        if peer_ports.is_empty() {
            return BTreeMap::new();
        }
        let mut owners: BTreeMap<u16, Vec<ProcessPortOwner>> = BTreeMap::new();
        for (identity, record) in &self.records {
            if *identity == selected || self.change_markers.get(identity) == Some(&ChangeMarker::Terminated) {
                continue;
            }
            for port in record.listening_ports.as_deref().unwrap_or(&[]) {
                if peer_ports.contains(port) {
                    owners.entry(*port).or_default().push(ProcessPortOwner {
                        identity: *identity,
                        pid: record.pid,
                        name: record.display_name().to_owned(),
                    });
                }
            }
        }
        for list in owners.values_mut() {
            list.sort_by_key(|owner| owner.identity);
        }
        owners
    }
}

fn compare_by_pid(left: ProcessIdentity, right: ProcessIdentity) -> Ordering {
    left.pid
        .cmp(&right.pid)
        .then(left.start_time_unix_ms.cmp(&right.start_time_unix_ms))
}

/// Ascending puts listeners first by their lowest listening port, then
/// processes with only other local ports, then processes without ports.
fn compare_ports(left: &ProcessRecord, right: &ProcessRecord) -> Ordering {
    fn key(record: &ProcessRecord) -> (u8, i64) {
        if let Some(first) = record.listening_ports.as_deref().and_then(|ports| ports.first()) {
            return (0, i64::from(*first));
        }
        match record.local_ports.as_deref() {
            Some(local) if !local.is_empty() => (1, -(local.len() as i64)),
            _ => (2, 0),
        }
    }
    key(left).cmp(&key(right))
}

/// The tree search columns that are visible, as `SEARCH_COLUMNS` bits.
pub fn visible_search_columns(visible_columns: &[String]) -> u8 {
    let mut bits = 1; // name is always visible
    for (bit, id) in SEARCH_COLUMNS.iter().enumerate() {
        if visible_columns.iter().any(|column| column == id) {
            bits |= 1 << bit;
        }
    }
    bits
}

fn search_column_bits(record: &ProcessRecord, matcher: &TextMatcher, allowed: u8) -> u8 {
    let mut bits = 0;
    let check = |bit: usize, value: &str| -> u8 {
        if allowed & (1 << bit) != 0 && matcher.matches(value) {
            1 << bit
        } else {
            0
        }
    };
    bits |= check(0, record.display_name());
    bits |= check(1, &record.pid.to_string());
    if allowed & (1 << 2) != 0 {
        bits |= check(2, &crate::time::format_clock(record.start_time_unix_ms));
    }
    bits |= check(3, record.status.name());
    bits |= check(4, &record.uid.to_string());
    bits
}

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
