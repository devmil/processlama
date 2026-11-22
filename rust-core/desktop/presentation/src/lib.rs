//! Formatting and column metadata shared by the Qt adapter.

use processlama_application::{TreeRow, time};
use processlama_domain::{ProcessPorts, ProcessRecord, SnapshotEntry, SortColumn};

/// `0 B`, `512 B`, `1.5 KB`, … in binary units.
pub fn format_bytes(bytes: u64) -> String {
    if bytes == 0 {
        return "0 B".into();
    }
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{value:.0} {}", UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// `<bytes>/s`.
pub fn format_rate(bytes_per_second: f64) -> String {
    format!("{}/s", format_bytes(bytes_per_second.max(0.0).round() as u64))
}

/// `0.0%` at zero, one decimal under 10, none above.
pub fn format_percent(value: f64) -> String {
    if value <= 0.0 {
        return "0.0%".into();
    }
    if value >= 10.0 {
        format!("{value:.0}%")
    } else {
        format!("{value:.1}%")
    }
}

/// `512 KB`-style sizes for remote helpers and the icon cache.
pub fn format_remote_bytes(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KB", "MB", "GB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 || value >= 10.0 {
        format!("{value:.0} {}", UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// `name · yyyy-MM-dd HH:mm`, or the time alone.
pub fn snapshot_label(entry: &SnapshotEntry) -> String {
    let timestamp = time::format_snapshot_time(entry.generated_at_unix_ms);
    match entry.name.as_deref().map(str::trim) {
        Some(name) if !name.is_empty() => format!("{name} · {timestamp}"),
        _ => timestamp,
    }
}

/// One process tree column.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ColumnDefinition {
    pub id: &'static str,
    pub sort: SortColumn,
    /// The default width; the flexible name column has none.
    pub width: f64,
    pub flex: bool,
    pub numeric: bool,
    /// Cells draw a CPU meter.
    pub meter: bool,
}

const fn column(id: &'static str, sort: SortColumn, width: f64, numeric: bool) -> ColumnDefinition {
    ColumnDefinition {
        id,
        sort,
        width,
        flex: false,
        numeric,
        meter: false,
    }
}

pub const COLUMNS: [ColumnDefinition; 20] = [
    ColumnDefinition {
        id: "name",
        sort: SortColumn::Name,
        width: 0.0,
        flex: true,
        numeric: false,
        meter: false,
    },
    column("pid", SortColumn::Pid, 86.0, true),
    ColumnDefinition {
        meter: true,
        ..column("cpu", SortColumn::Cpu, 82.0, true)
    },
    ColumnDefinition {
        meter: true,
        ..column("treeCpu", SortColumn::TreeCpu, 96.0, true)
    },
    column("gpu", SortColumn::Gpu, 72.0, true),
    column("treeGpu", SortColumn::TreeGpu, 96.0, true),
    column("memory", SortColumn::Memory, 112.0, true),
    column("treeMemory", SortColumn::TreeMemory, 112.0, true),
    column("networkIn", SortColumn::NetworkIn, 94.0, true),
    column("networkOut", SortColumn::NetworkOut, 94.0, true),
    column("treeNetworkIn", SortColumn::TreeNetworkIn, 118.0, true),
    column("treeNetworkOut", SortColumn::TreeNetworkOut, 126.0, true),
    column("storageRead", SortColumn::StorageRead, 104.0, true),
    column("storageWrite", SortColumn::StorageWrite, 104.0, true),
    column("treeStorageRead", SortColumn::TreeStorageRead, 132.0, true),
    column("treeStorageWrite", SortColumn::TreeStorageWrite, 132.0, true),
    column("startTime", SortColumn::StartTime, 96.0, false),
    column("status", SortColumn::Status, 98.0, false),
    column("uid", SortColumn::Uid, 76.0, true),
    column("ports", SortColumn::Ports, 120.0, true),
];

pub fn column_definition(id: &str) -> Option<&'static ColumnDefinition> {
    COLUMNS.iter().find(|column| column.id == id)
}

fn storage(available: bool, value: f64) -> String {
    if available { format_rate(value) } else { "-".into() }
}

fn ports_cell(record: &ProcessRecord) -> String {
    ProcessPorts::of_record(record).map_or_else(|| "-".into(), |ports| ports.cell_text())
}

/// The text a cell shows. The name and status columns format in QML
/// (highlights, localized state), but their text is still the value matched.
pub fn cell_text(row: &TreeRow, column: &str) -> String {
    let record = &row.record;
    match column {
        "name" => record.display_name().to_owned(),
        "pid" => record.pid.to_string(),
        "cpu" => format_percent(record.cpu_usage),
        "treeCpu" => format_percent(row.tree_cpu),
        "gpu" => format_percent(record.gpu_usage),
        "treeGpu" => format_percent(row.tree_gpu),
        "memory" => format_bytes(record.rss_bytes),
        "treeMemory" => format_bytes(row.tree_rss),
        "networkIn" => format_rate(record.network_in_bytes_per_second),
        "networkOut" => format_rate(record.network_out_bytes_per_second),
        "treeNetworkIn" => format_rate(row.tree_network_in),
        "treeNetworkOut" => format_rate(row.tree_network_out),
        "storageRead" => storage(record.storage_io_available, record.storage_read_bytes_per_second),
        "storageWrite" => storage(record.storage_io_available, record.storage_write_bytes_per_second),
        "treeStorageRead" => storage(row.tree_storage_available, row.tree_storage_read),
        "treeStorageWrite" => storage(row.tree_storage_available, row.tree_storage_write),
        "startTime" => time::format_clock(record.start_time_unix_ms),
        "status" => record.status.capitalized().to_owned(),
        "uid" => record.uid.to_string(),
        "ports" => ports_cell(record),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_like_the_flutter_build() {
        assert_eq!(format_bytes(0), "0 B");
        assert_eq!(format_bytes(512), "512 B");
        assert_eq!(format_bytes(1536), "1.5 KB");
        assert_eq!(format_bytes(5 * 1024 * 1024 * 1024), "5.0 GB");
        assert_eq!(format_rate(2048.4), "2.0 KB/s");
        assert_eq!(format_percent(0.0), "0.0%");
        assert_eq!(format_percent(3.14), "3.1%");
        assert_eq!(format_percent(42.6), "43%");
        assert_eq!(format_remote_bytes(512 * 1024), "512 KB");
        assert_eq!(format_remote_bytes(1536 * 1024), "1.5 MB");
        assert_eq!(format_remote_bytes(64 * 1024 * 1024), "64 MB");
    }
}
