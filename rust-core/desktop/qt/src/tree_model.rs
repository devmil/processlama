//! The active tab's visible tree rows as a flat table model.
//!
//! Rows are the session's preorder projection; columns are the visible
//! columns in display order. Publications are reconciled against the previous
//! rows: structure changes remove and insert only the changed middle range
//! (by identity), and value changes emit `dataChanged` for the changed cells
//! of each row only. Routine live updates never reset the model.

use processlama_application::{ChangeMarker, IconCache, TreeRow, TreeView};
use processlama_domain::{ProcessIconRef, ProcessIdentity, SearchOptions, TextMatcher};
use processlama_presentation::{COLUMNS, ColumnDefinition, cell_text, column_definition};
use qtbridge::qobject;
use std::collections::HashSet;
use std::sync::Arc;

pub(crate) fn icon_url(
    record_icon: Option<&ProcessIconRef>,
    cache: Option<&Arc<dyn IconCache>>,
) -> String {
    match record_icon {
        Some(ProcessIconRef::File(uri)) => {
            if uri.starts_with("file:") {
                uri.clone()
            } else if uri.starts_with('/') {
                format!("file://{uri}")
            } else {
                format!("file:///{}", uri.replace('\\', "/"))
            }
        }
        Some(ProcessIconRef::Remote(hash)) => cache
            .and_then(|cache| cache.path_for(hash))
            .map(|path| {
                if path.starts_with('/') {
                    format!("file://{path}")
                } else {
                    format!("file:///{}", path.replace('\\', "/"))
                }
            })
            .unwrap_or_default(),
        None => String::new(),
    }
}

#[qobject(Base = QAbstractItemModel, ConvertToCamelCase)]
mod process_tree_model {
    use super::*;
    use qtbridge::qtbridge_type_lib::{QByteArray, QHash, QModelIndex, QVariant};
    use qtbridge::{QAbstractItemModel, QAbstractItemModelBase};

    pub const TEXT_ROLE: i32 = 257;
    pub const KEY_ROLE: i32 = 258;
    pub const DEPTH_ROLE: i32 = 259;
    pub const HAS_CHILDREN_ROLE: i32 = 260;
    pub const EXPANDED_ROLE: i32 = 261;
    pub const NAME_ROLE: i32 = 262;
    pub const ICON_ROLE: i32 = 263;
    pub const DESCENDANTS_ROLE: i32 = 264;
    pub const HISTORY_ROLE: i32 = 265;
    pub const MARKER_ROLE: i32 = 266;
    pub const PINNED_ROLE: i32 = 267;
    pub const USAGE_ROLE: i32 = 268;
    pub const STATUS_ROLE: i32 = 269;
    pub const HEAT_ROLE: i32 = 270;
    pub const CELL_MATCH_ROLE: i32 = 271;
    pub const MATCH_START_ROLE: i32 = 272;
    pub const MATCH_END_ROLE: i32 = 273;
    pub const ROW_MATCH_ROLE: i32 = 274;
    pub const COLUMN_ROLE: i32 = 275;
    pub const PID_ROLE: i32 = 276;
    pub const EXECUTABLE_ROLE: i32 = 277;
    pub const NUMERIC_ROLE: i32 = 278;

    pub struct ProcessTreeModel {
        rows: Arc<Vec<TreeRow>>,
        columns: Vec<&'static ColumnDefinition>,
        pinned: Arc<HashSet<ProcessIdentity>>,
        matcher: Option<TextMatcher>,
        search_options: SearchOptions,
        search_query: String,
        icon_cache: Option<Arc<dyn IconCache>>,
        icon_revision: u64,
        column_ids: Vec<String>,
        row_total: i32,
        selected_row: i32,
        selected_key: String,
        cpu_scale_max: f64,
        reset_count: i32,
        source_key: String,
    }

    impl Default for ProcessTreeModel {
        fn default() -> Self {
            Self {
                rows: Arc::new(Vec::new()),
                columns: vec![&COLUMNS[0]],
                pinned: Arc::new(HashSet::new()),
                matcher: None,
                search_options: SearchOptions::default(),
                search_query: String::new(),
                icon_cache: None,
                icon_revision: 0,
                column_ids: vec!["name".into()],
                row_total: 0,
                selected_row: -1,
                selected_key: String::new(),
                cpu_scale_max: 1.0,
                reset_count: 0,
                source_key: String::new(),
            }
        }
    }

    impl ProcessTreeModel {
        qproperty!("columnIds", Member = column_ids, Notify = columns_changed);
        qproperty!("rowTotal", Member = row_total, Notify = rows_changed);
        qproperty!(
            "selectedRow",
            Member = selected_row,
            Notify = selection_changed
        );
        qproperty!(
            "selectedKey",
            Member = selected_key,
            Notify = selection_changed
        );
        qproperty!(
            "cpuScaleMax",
            Member = cpu_scale_max,
            Notify = scale_changed
        );
        qproperty!("resetCount", Member = reset_count, Notify = rows_changed);

        #[qsignal]
        pub fn columns_changed(&mut self);
        #[qsignal]
        pub fn rows_changed(&mut self);
        #[qsignal]
        pub fn selection_changed(&mut self);
        #[qsignal]
        pub fn scale_changed(&mut self);
        /// The rows were replaced for another tab; views reset their scroll.
        #[qsignal]
        pub fn source_replaced(&mut self);

        /// The row of `key`, or -1.
        #[qslot]
        fn row_of(&self, key: String) -> i32 {
            self.rows
                .iter()
                .position(|row| row.identity.key() == key)
                .map_or(-1, |index| index as i32)
        }

        pub fn set_icon_cache(&mut self, cache: Arc<dyn IconCache>) {
            self.icon_cache = Some(cache);
        }

        /// Reconciles the published tree. `source_key` names the tab: a tab
        /// switch replaces the rows outright.
        pub fn apply(
            &mut self,
            view: &TreeView,
            visible_columns: &[String],
            source_key: &str,
            icon_revision: u64,
        ) {
            let columns: Vec<&'static ColumnDefinition> = visible_columns
                .iter()
                .filter_map(|id| column_definition(id))
                .collect();
            let matcher = (!view.tree_search_query.is_empty()).then(|| {
                TextMatcher::new(
                    &view.tree_search_query,
                    view.search_options.match_case,
                    view.search_options.whole_word,
                )
            });
            let search_changed = view.tree_search_query != self.search_query
                || view.search_options != self.search_options;
            let icons_changed = icon_revision != self.icon_revision;
            let columns_changed = columns != self.columns;
            let source_changed = source_key != self.source_key;
            let pinned_before = Arc::clone(&self.pinned);
            self.pinned = Arc::clone(&view.pinned);
            self.matcher = matcher;
            self.search_query.clone_from(&view.tree_search_query);
            self.search_options = view.search_options;
            self.icon_revision = icon_revision;

            if columns_changed || source_changed {
                self.begin_reset_model();
                self.columns = columns;
                self.rows = Arc::clone(&view.rows);
                self.end_reset_model();
                self.reset_count += 1;
                self.column_ids = self.columns.iter().map(|c| c.id.to_owned()).collect();
                self.source_key = source_key.to_owned();
                self.columns_changed();
                if source_changed {
                    self.source_replaced();
                }
            } else {
                self.reconcile(&view.rows, &pinned_before, search_changed, icons_changed);
            }
            let total = self.rows.len() as i32;
            if total != self.row_total {
                self.row_total = total;
                self.rows_changed();
            }
            let selected_row = view
                .selected
                .and_then(|selected| self.rows.iter().position(|row| row.identity == selected))
                .map_or(-1, |index| index as i32);
            let selected_key = view.selected.map(ProcessIdentity::key).unwrap_or_default();
            if selected_row != self.selected_row || selected_key != self.selected_key {
                self.selected_row = selected_row;
                self.selected_key = selected_key;
                self.selection_changed();
            }
            if (view.cpu_scale_max - self.cpu_scale_max).abs() > f64::EPSILON {
                self.cpu_scale_max = view.cpu_scale_max;
                self.scale_changed();
            }
        }

        fn reconcile(
            &mut self,
            next: &Arc<Vec<TreeRow>>,
            pinned_before: &HashSet<ProcessIdentity>,
            search_changed: bool,
            icons_changed: bool,
        ) {
            let before = Arc::clone(&self.rows);
            let prefix = before
                .iter()
                .zip(next.iter())
                .take_while(|(a, b)| a.identity == b.identity)
                .count();
            let suffix = before[prefix..]
                .iter()
                .rev()
                .zip(next[prefix..].iter().rev())
                .take_while(|(a, b)| a.identity == b.identity)
                .count();
            let old_end = before.len() - suffix;
            let new_end = next.len() - suffix;
            if prefix < old_end {
                // Publish the shortened list while Qt asks for data.
                let mut remaining: Vec<TreeRow> =
                    Vec::with_capacity(before.len() - (old_end - prefix));
                remaining.extend_from_slice(&before[..prefix]);
                remaining.extend_from_slice(&before[old_end..]);
                self.begin_remove_rows(&QModelIndex::default(), prefix as i32, old_end as i32 - 1);
                self.rows = Arc::new(remaining);
                self.end_remove_rows();
            }
            if prefix < new_end {
                self.begin_insert_rows(&QModelIndex::default(), prefix as i32, new_end as i32 - 1);
                self.rows = Arc::clone(next);
                self.end_insert_rows();
            } else {
                self.rows = Arc::clone(next);
            }
            // Value changes in the kept prefix and suffix.
            let column_count = self.columns.len();
            let mut spans: Vec<(usize, usize, usize)> = Vec::new();
            let mut compare = |old: &TreeRow, new: &TreeRow, index: usize, this: &Self| {
                if let Some((first, last)) = this.changed_columns(
                    old,
                    new,
                    pinned_before,
                    search_changed,
                    icons_changed,
                    column_count,
                ) {
                    spans.push((index, first, last));
                }
            };
            for index in 0..prefix {
                compare(&before[index], &next[index], index, self);
            }
            for offset in 0..suffix {
                let old = &before[old_end + offset];
                let new_index = new_end + offset;
                compare(old, &next[new_index], new_index, self);
            }
            spans.sort_unstable();
            let mut start = 0;
            while start < spans.len() {
                let (row, first, last) = spans[start];
                let mut end = start;
                while end + 1 < spans.len()
                    && spans[end + 1].0 == spans[end].0 + 1
                    && spans[end + 1].1 == first
                    && spans[end + 1].2 == last
                {
                    end += 1;
                }
                let top_left = self.create_index(row as i32, first as i32, 0);
                let bottom_right = self.create_index(spans[end].0 as i32, last as i32, 0);
                self.data_changed(&top_left, &bottom_right);
                start = end + 1;
            }
        }

        /// The first and last visible column whose cell changed.
        fn changed_columns(
            &self,
            old: &TreeRow,
            new: &TreeRow,
            pinned_before: &HashSet<ProcessIdentity>,
            search_changed: bool,
            icons_changed: bool,
            column_count: usize,
        ) -> Option<(usize, usize)> {
            let row_level = old.depth != new.depth
                || old.has_children != new.has_children
                || old.is_expanded != new.is_expanded
                || old.change_marker != new.change_marker
                || old.search_columns != new.search_columns
                || pinned_before.contains(&old.identity) != self.pinned.contains(&new.identity)
                || (search_changed && (old.search_columns != 0 || new.search_columns != 0));
            if row_level {
                return Some((0, column_count.saturating_sub(1)));
            }
            let mut first = None;
            let mut last = 0;
            for (index, column) in self.columns.iter().enumerate() {
                let changed = match column.id {
                    "name" => {
                        old.record.display_name() != new.record.display_name()
                            || old.descendant_count != new.descendant_count
                            || !Arc::ptr_eq(&old.cpu_history, &new.cpu_history)
                            || old.record.icon != new.record.icon
                            || icons_changed
                            || (old.tree_cpu - new.tree_cpu).abs() > f64::EPSILON
                    }
                    "status" => old.record.status != new.record.status,
                    id => cell_text(old, id) != cell_text(new, id),
                };
                if changed {
                    first.get_or_insert(index);
                    last = index;
                }
            }
            first.map(|first| (first, last))
        }

        fn row(&self, index: &QModelIndex) -> Option<(&TreeRow, &'static ColumnDefinition)> {
            if !index.is_valid() {
                return None;
            }
            let row = self.rows.get(index.row() as usize)?;
            let column = *self.columns.get(index.column() as usize)?;
            Some((row, column))
        }
    }

    impl QAbstractItemModel for ProcessTreeModel {
        fn index(&self, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex {
            if parent.is_valid()
                || row < 0
                || column < 0
                || row as usize >= self.rows.len()
                || column as usize >= self.columns.len()
            {
                return QModelIndex::default();
            }
            self.create_index(row, column, 0)
        }

        fn parent(&self, _child: &QModelIndex) -> QModelIndex {
            QModelIndex::default()
        }

        fn row_count(&self, parent: &QModelIndex) -> i32 {
            if parent.is_valid() {
                0
            } else {
                self.rows.len() as i32
            }
        }

        fn column_count(&self, parent: &QModelIndex) -> i32 {
            if parent.is_valid() {
                0
            } else {
                self.columns.len() as i32
            }
        }

        fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
            let Some((row, column)) = self.row(index) else {
                return QVariant::default();
            };
            let record = &row.record;
            match role {
                0 | TEXT_ROLE => QVariant::from(cell_text(row, column.id)),
                KEY_ROLE => QVariant::from(row.identity.key()),
                DEPTH_ROLE => QVariant::from(row.depth as i32),
                HAS_CHILDREN_ROLE => QVariant::from(row.has_children),
                EXPANDED_ROLE => QVariant::from(row.is_expanded),
                NAME_ROLE => QVariant::from(record.display_name().to_owned()),
                ICON_ROLE => {
                    QVariant::from(icon_url(record.icon.as_ref(), self.icon_cache.as_ref()))
                }
                DESCENDANTS_ROLE => QVariant::from(row.descendant_count as i32),
                HISTORY_ROLE => {
                    let samples: Vec<f64> = row
                        .cpu_history
                        .iter()
                        .map(|sample| f64::from(*sample))
                        .collect();
                    QVariant::from(&samples)
                }
                MARKER_ROLE => QVariant::from(match row.change_marker {
                    ChangeMarker::None => 0,
                    ChangeMarker::Spawned => 1,
                    ChangeMarker::Terminated => 2,
                }),
                PINNED_ROLE => QVariant::from(self.pinned.contains(&row.identity)),
                USAGE_ROLE => QVariant::from(if column.id == "treeCpu" {
                    row.tree_cpu
                } else {
                    record.cpu_usage
                }),
                STATUS_ROLE => QVariant::from(match record.status {
                    processlama_domain::ProcessStatus::Running => 0,
                    processlama_domain::ProcessStatus::Sleeping => 1,
                    processlama_domain::ProcessStatus::Stopped => 2,
                    processlama_domain::ProcessStatus::Zombie => 3,
                    processlama_domain::ProcessStatus::Unknown => 4,
                }),
                HEAT_ROLE => QVariant::from(row.tree_cpu),
                CELL_MATCH_ROLE => QVariant::from(row.search_matches_column(column.id)),
                MATCH_START_ROLE | MATCH_END_ROLE => {
                    let range = if row.search_matches_column(column.id) {
                        self.matcher.as_ref().and_then(|matcher| {
                            matcher.first_match_utf16(&cell_text(row, column.id))
                        })
                    } else {
                        None
                    };
                    let value = range.map_or(
                        -1,
                        |(start, end)| if role == MATCH_START_ROLE { start } else { end } as i32,
                    );
                    QVariant::from(value)
                }
                ROW_MATCH_ROLE => QVariant::from(row.matches_tree_search()),
                COLUMN_ROLE => QVariant::from(column.id.to_owned()),
                PID_ROLE => QVariant::from(record.pid),
                EXECUTABLE_ROLE => QVariant::from(record.executable_path.clone()),
                NUMERIC_ROLE => QVariant::from(column.numeric),
                _ => QVariant::default(),
            }
        }

        fn role_names(&self) -> QHash<i32, QByteArray> {
            QHash::from([
                (TEXT_ROLE, "cellText"),
                (KEY_ROLE, "processKey"),
                (DEPTH_ROLE, "depth"),
                (HAS_CHILDREN_ROLE, "hasChildren"),
                (EXPANDED_ROLE, "expanded"),
                (NAME_ROLE, "processName"),
                (ICON_ROLE, "iconUrl"),
                (DESCENDANTS_ROLE, "descendants"),
                (HISTORY_ROLE, "history"),
                (MARKER_ROLE, "marker"),
                (PINNED_ROLE, "pinned"),
                (USAGE_ROLE, "usage"),
                (STATUS_ROLE, "status"),
                (HEAT_ROLE, "heat"),
                (CELL_MATCH_ROLE, "cellMatch"),
                (MATCH_START_ROLE, "matchStart"),
                (MATCH_END_ROLE, "matchEnd"),
                (ROW_MATCH_ROLE, "rowMatch"),
                (COLUMN_ROLE, "columnId"),
                (PID_ROLE, "pid"),
                (EXECUTABLE_ROLE, "executablePath"),
                (NUMERIC_ROLE, "numeric"),
            ])
        }
    }
}

pub use process_tree_model::ProcessTreeModel;
