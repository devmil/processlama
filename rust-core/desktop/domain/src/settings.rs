//! Application preferences.

use serde_json::{Map, Value, json};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum AppearanceMode {
    #[default]
    System,
    Light,
    Dark,
}

impl AppearanceMode {
    pub const fn name(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }
    pub fn parse(value: &str) -> Self {
        match value {
            "light" => Self::Light,
            "dark" => Self::Dark,
            _ => Self::System,
        }
    }
}

/// How tall rows in the process tree and other lists are.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum RowDensity {
    #[default]
    Compact,
    Regular,
    Comfortable,
}

impl RowDensity {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Compact => "compact",
            Self::Regular => "regular",
            Self::Comfortable => "comfortable",
        }
    }
    pub fn parse(value: &str) -> Self {
        match value {
            "regular" => Self::Regular,
            "comfortable" => Self::Comfortable,
            _ => Self::Compact,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum ReleaseChannel {
    #[default]
    Stable,
    Beta,
}

impl ReleaseChannel {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Stable => "stable",
            Self::Beta => "beta",
        }
    }
    pub fn parse(value: &str) -> Self {
        if value == "beta" {
            Self::Beta
        } else {
            Self::Stable
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum SortDirection {
    Ascending,
    #[default]
    Descending,
}

impl SortDirection {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Ascending => "ascending",
            Self::Descending => "descending",
        }
    }
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "ascending" => Some(Self::Ascending),
            "descending" => Some(Self::Descending),
            _ => None,
        }
    }
    pub fn flipped(self) -> Self {
        match self {
            Self::Ascending => Self::Descending,
            Self::Descending => Self::Ascending,
        }
    }
}

/// What the process tree sorts siblings by.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum SortColumn {
    Tree,
    Pid,
    Name,
    Cpu,
    #[default]
    TreeCpu,
    Gpu,
    TreeGpu,
    Memory,
    TreeMemory,
    NetworkIn,
    NetworkOut,
    TreeNetworkIn,
    TreeNetworkOut,
    StorageRead,
    StorageWrite,
    TreeStorageRead,
    TreeStorageWrite,
    StartTime,
    Status,
    Uid,
    Ports,
}

impl SortColumn {
    pub const ALL: [Self; 21] = [
        Self::Tree,
        Self::Pid,
        Self::Name,
        Self::Cpu,
        Self::TreeCpu,
        Self::Gpu,
        Self::TreeGpu,
        Self::Memory,
        Self::TreeMemory,
        Self::NetworkIn,
        Self::NetworkOut,
        Self::TreeNetworkIn,
        Self::TreeNetworkOut,
        Self::StorageRead,
        Self::StorageWrite,
        Self::TreeStorageRead,
        Self::TreeStorageWrite,
        Self::StartTime,
        Self::Status,
        Self::Uid,
        Self::Ports,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            Self::Tree => "tree",
            Self::Pid => "pid",
            Self::Name => "name",
            Self::Cpu => "cpu",
            Self::TreeCpu => "treeCpu",
            Self::Gpu => "gpu",
            Self::TreeGpu => "treeGpu",
            Self::Memory => "memory",
            Self::TreeMemory => "treeMemory",
            Self::NetworkIn => "networkIn",
            Self::NetworkOut => "networkOut",
            Self::TreeNetworkIn => "treeNetworkIn",
            Self::TreeNetworkOut => "treeNetworkOut",
            Self::StorageRead => "storageRead",
            Self::StorageWrite => "storageWrite",
            Self::TreeStorageRead => "treeStorageRead",
            Self::TreeStorageWrite => "treeStorageWrite",
            Self::StartTime => "startTime",
            Self::Status => "status",
            Self::Uid => "uid",
            Self::Ports => "ports",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|column| column.name() == value)
    }

    /// The direction a column sorts in when first selected.
    pub const fn default_direction(self) -> SortDirection {
        match self {
            Self::Tree | Self::Name | Self::Status | Self::StartTime | Self::Ports => {
                SortDirection::Ascending
            }
            _ => SortDirection::Descending,
        }
    }

    /// Sorts whose order cannot change between metric-only samples.
    pub const fn is_stable(self) -> bool {
        matches!(self, Self::Tree | Self::Pid | Self::StartTime)
    }
}

/// The process tree columns, in their default order.
pub const AVAILABLE_COLUMNS: [&str; 20] = [
    "name",
    "pid",
    "cpu",
    "treeCpu",
    "gpu",
    "treeGpu",
    "memory",
    "treeMemory",
    "networkIn",
    "networkOut",
    "treeNetworkIn",
    "treeNetworkOut",
    "storageRead",
    "storageWrite",
    "treeStorageRead",
    "treeStorageWrite",
    "startTime",
    "status",
    "uid",
    "ports",
];

pub fn is_available_column(id: &str) -> bool {
    AVAILABLE_COLUMNS.contains(&id)
}

/// Known, distinct columns with `name` first when missing.
pub fn normalized_visible_columns(columns: &[String]) -> Vec<String> {
    let mut visible: Vec<String> = Vec::new();
    for column in columns {
        if is_available_column(column) && !visible.contains(column) {
            visible.push(column.clone());
        }
    }
    if !visible.iter().any(|column| column == "name") {
        visible.insert(0, "name".into());
    }
    visible
}

pub fn default_visible_columns() -> Vec<String> {
    AVAILABLE_COLUMNS
        .iter()
        .map(|id| (*id).to_owned())
        .collect()
}

pub const DEFAULT_POLLING_INTERVAL_MS: u32 = 1000;
pub const MIN_POLLING_INTERVAL_MS: u32 = 250;
pub const MAX_POLLING_INTERVAL_MS: u32 = 10_000;
pub const DEFAULT_INSPECTOR_WIDTH: f64 = 360.0;
pub const MIN_INSPECTOR_WIDTH: f64 = 240.0;
pub const MAX_INSPECTOR_WIDTH: f64 = 720.0;
pub const MAX_SAVED_FILTERS: usize = 10;
pub const SUPPORTED_LANGUAGES: [&str; 2] = ["en", "de"];

#[derive(Clone, Debug, PartialEq)]
pub struct AppSettings {
    pub polling_interval_ms: u32,
    pub remember_tree_expansion: bool,
    /// Refresh less often while another window has the focus or the window
    /// is minimized.
    pub reduce_background_refresh: bool,
    pub saved_filters: Vec<String>,
    pub visible_columns: Vec<String>,
    pub column_widths: BTreeMap<String, f64>,
    pub inspector_width: f64,
    pub process_sort_column: SortColumn,
    pub process_sort_direction: SortDirection,
    pub appearance_mode: AppearanceMode,
    pub row_heatmap: bool,
    pub row_density: RowDensity,
    pub language_code: String,
    pub release_channel: ReleaseChannel,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            polling_interval_ms: DEFAULT_POLLING_INTERVAL_MS,
            remember_tree_expansion: true,
            reduce_background_refresh: true,
            saved_filters: Vec::new(),
            visible_columns: default_visible_columns(),
            column_widths: BTreeMap::new(),
            inspector_width: DEFAULT_INSPECTOR_WIDTH,
            process_sort_column: SortColumn::TreeCpu,
            process_sort_direction: SortDirection::Descending,
            appearance_mode: AppearanceMode::System,
            row_heatmap: true,
            row_density: RowDensity::Compact,
            language_code: "en".into(),
            release_channel: ReleaseChannel::Stable,
        }
    }
}

impl AppSettings {
    pub fn to_json(&self) -> Value {
        json!({
            "polling_interval_ms": self.polling_interval_ms,
            "remember_tree_expansion": self.remember_tree_expansion,
            "reduce_background_refresh": self.reduce_background_refresh,
            "saved_filters": self.saved_filters,
            "visible_columns": self.visible_columns,
            "column_widths": self.column_widths,
            "inspector_width": self.inspector_width,
            "process_sort_column": self.process_sort_column.name(),
            "process_sort_direction": self.process_sort_direction.name(),
            "appearance_mode": self.appearance_mode.name(),
            "row_heatmap": self.row_heatmap,
            "row_density": self.row_density.name(),
            "language_code": self.language_code,
            "release_channel": self.release_channel.name(),
        })
    }

    /// Reads stored settings; missing or malformed fields keep their defaults.
    pub fn from_json(value: &Value, defaults: &AppSettings) -> Self {
        let empty = Map::new();
        let map = value.as_object().unwrap_or(&empty);
        let mut settings = defaults.clone();
        if let Some(v) = map.get("polling_interval_ms").and_then(Value::as_f64) {
            settings.polling_interval_ms =
                (v as u32).clamp(MIN_POLLING_INTERVAL_MS, MAX_POLLING_INTERVAL_MS);
        }
        if let Some(v) = map.get("remember_tree_expansion").and_then(Value::as_bool) {
            settings.remember_tree_expansion = v;
        }
        if let Some(v) = map
            .get("reduce_background_refresh")
            .and_then(Value::as_bool)
        {
            settings.reduce_background_refresh = v;
        }
        if let Some(v) = map.get("saved_filters").and_then(Value::as_array) {
            settings.saved_filters = v
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect();
        }
        if let Some(v) = map.get("visible_columns").and_then(Value::as_array) {
            let columns: Vec<String> = v
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect();
            if !is_legacy_compact_column_set(&columns) {
                settings.visible_columns = columns;
            }
        }
        if let Some(v) = map.get("column_widths").and_then(Value::as_object) {
            settings.column_widths = v
                .iter()
                .filter(|(key, _)| is_available_column(key))
                .filter_map(|(key, value)| value.as_f64().map(|width| (key.clone(), width)))
                .collect();
        }
        if let Some(v) = map.get("inspector_width").and_then(Value::as_f64) {
            settings.inspector_width = v;
        }
        if let Some(column) = map
            .get("process_sort_column")
            .and_then(Value::as_str)
            .and_then(SortColumn::parse)
        {
            settings.process_sort_column = column;
        }
        if let Some(direction) = map
            .get("process_sort_direction")
            .and_then(Value::as_str)
            .and_then(SortDirection::parse)
        {
            settings.process_sort_direction = direction;
        }
        if let Some(v) = map.get("appearance_mode").and_then(Value::as_str) {
            settings.appearance_mode = AppearanceMode::parse(v);
        }
        if let Some(v) = map.get("row_heatmap").and_then(Value::as_bool) {
            settings.row_heatmap = v;
        }
        if let Some(v) = map.get("row_density").and_then(Value::as_str) {
            settings.row_density = RowDensity::parse(v);
        }
        if let Some(v) = map.get("language_code").and_then(Value::as_str) {
            settings.language_code = v.to_owned();
        }
        if let Some(v) = map.get("release_channel").and_then(Value::as_str) {
            settings.release_channel = ReleaseChannel::parse(v);
        }
        settings
    }
}

/// The four-column default of very early builds; it is replaced by the full set.
fn is_legacy_compact_column_set(columns: &[String]) -> bool {
    const LEGACY: [&str; 4] = ["name", "pid", "memory", "status"];
    columns.len() == LEGACY.len() && LEGACY.iter().all(|id| columns.iter().any(|c| c == id))
}

/// Saved filters: trimmed, distinct ignoring case, at most ten.
pub fn normalize_saved_filters(values: &[String]) -> Vec<String> {
    let mut filters = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() || !seen.insert(trimmed.to_lowercase()) {
            continue;
        }
        filters.push(trimmed.to_owned());
    }
    filters.truncate(MAX_SAVED_FILTERS);
    filters
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_round_trips() {
        let mut settings = AppSettings {
            polling_interval_ms: 2000,
            ..AppSettings::default()
        };
        settings.column_widths.insert("pid".into(), 99.0);
        settings.saved_filters = vec!["all:foo".into()];
        settings.release_channel = ReleaseChannel::Beta;
        settings.reduce_background_refresh = false;
        let back = AppSettings::from_json(&settings.to_json(), &AppSettings::default());
        assert_eq!(back, settings);
    }

    #[test]
    fn stored_settings_without_the_energy_setting_save_energy() {
        let settings = AppSettings::from_json(&json!({}), &AppSettings::default());
        assert!(settings.reduce_background_refresh);
    }

    #[test]
    fn legacy_columns_are_replaced() {
        let value = json!({"visible_columns": ["name", "pid", "memory", "status"]});
        let settings = AppSettings::from_json(&value, &AppSettings::default());
        assert_eq!(settings.visible_columns, default_visible_columns());
    }

    #[test]
    fn normalized_columns_put_name_first() {
        let columns = vec!["pid".to_owned(), "bogus".into(), "pid".into()];
        assert_eq!(normalized_visible_columns(&columns), vec!["name", "pid"]);
    }

    #[test]
    fn filters_are_normalized() {
        let values: Vec<String> = vec![" a ".into(), "A".into(), "".into(), "b".into()];
        assert_eq!(normalize_saved_filters(&values), vec!["a", "b"]);
    }
}
