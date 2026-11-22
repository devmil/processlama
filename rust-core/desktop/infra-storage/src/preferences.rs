#![cfg_attr(not(target_os = "macos"), allow(dead_code))]
//! One-time import of the Flutter builds' `shared_preferences`.

use serde_json::{Map, Value, json};
use std::path::Path;

const KEYS: [&str; 13] = [
    "polling_interval_ms",
    "remember_tree_expansion",
    "saved_filters",
    "visible_columns",
    "column_widths",
    "inspector_width",
    "process_sort_column",
    "process_sort_direction",
    "appearance_mode",
    "row_heatmap",
    "row_density",
    "language_code",
    "release_channel",
];

/// The Flutter preferences as a `settings.json` document, or None when there
/// are none.
pub fn import_flutter_preferences(directory: &Path) -> Option<Map<String, Value>> {
    let values = read_preferences(directory)?;
    let mut settings = Map::new();
    for key in KEYS {
        if let Some(value) = values.get(&format!("flutter.{key}")) {
            let value = if key == "column_widths" {
                // Stored as a JSON string.
                value
                    .as_str()
                    .and_then(|text| serde_json::from_str(text).ok())
                    .unwrap_or(Value::Null)
            } else {
                value.clone()
            };
            if !value.is_null() {
                settings.insert(key.to_owned(), value);
            }
        }
    }
    let mut document = Map::new();
    if !settings.is_empty() {
        document.insert("settings".into(), Value::Object(settings));
    }
    if let Some(hosts) = values
        .get("flutter.remote_hosts_v1")
        .and_then(Value::as_str)
        .and_then(|text| serde_json::from_str::<Value>(text).ok())
    {
        document.insert("remote_hosts_v1".into(), hosts);
    }
    (!document.is_empty()).then_some(document)
}

fn read_preferences(directory: &Path) -> Option<Map<String, Value>> {
    if cfg!(target_os = "macos") {
        return read_macos_defaults();
    }
    let bytes = std::fs::read(directory.join("shared_preferences.json")).ok()?;
    serde_json::from_slice::<Value>(&bytes).ok()?.as_object().cloned()
}

#[cfg(target_os = "macos")]
fn read_macos_defaults() -> Option<Map<String, Value>> {
    let output = std::process::Command::new("/usr/bin/defaults")
        .args(["export", "de.devmil.processlama", "-"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    parse_plist(&String::from_utf8_lossy(&output.stdout))
}

#[cfg(not(target_os = "macos"))]
fn read_macos_defaults() -> Option<Map<String, Value>> {
    None
}

/// A small XML property list reader: a top-level dict of strings, numbers,
/// booleans and arrays of strings, which is all the preferences hold.
pub(crate) fn parse_plist(xml: &str) -> Option<Map<String, Value>> {
    let body = xml.split_once("<dict>")?.1;
    let mut map = Map::new();
    let mut rest = body;
    while let Some(start) = rest.find("<key>") {
        let after = &rest[start + 5..];
        let end = after.find("</key>")?;
        let key = unescape(&after[..end]);
        let mut value_text = after[end + 6..].trim_start();
        let (value, consumed) = parse_value(value_text)?;
        value_text = &value_text[consumed..];
        map.insert(key, value);
        rest = value_text;
    }
    Some(map)
}

fn parse_value(text: &str) -> Option<(Value, usize)> {
    let tag = |name: &str| -> Option<(String, usize)> {
        let open = format!("<{name}>");
        let close = format!("</{name}>");
        if !text.starts_with(&open) {
            return None;
        }
        let end = text.find(&close)?;
        Some((unescape(&text[open.len()..end]), end + close.len()))
    };
    if text.starts_with("<true/>") {
        return Some((json!(true), 7));
    }
    if text.starts_with("<false/>") {
        return Some((json!(false), 8));
    }
    if let Some((value, used)) = tag("string") {
        return Some((json!(value), used));
    }
    if let Some((value, used)) = tag("integer") {
        return Some((value.trim().parse::<i64>().map_or(Value::Null, |n| json!(n)), used));
    }
    if let Some((value, used)) = tag("real") {
        return Some((value.trim().parse::<f64>().map_or(Value::Null, |n| json!(n)), used));
    }
    if text.starts_with("<array/>") {
        return Some((json!([]), 8));
    }
    if let Some(inner) = text.strip_prefix("<array>") {
        let end = inner.find("</array>")?;
        let mut items = Vec::new();
        let mut body = inner[..end].trim_start();
        while !body.is_empty() {
            let (value, used) = parse_value(body)?;
            items.push(value);
            body = body[used..].trim_start();
        }
        return Some((Value::Array(items), "<array>".len() + end + "</array>".len()));
    }
    // Anything else (dates, data, nested dicts) is skipped as null.
    let end = text.find('>')? + 1;
    Some((Value::Null, end))
}

fn unescape(value: &str) -> String {
    value
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_the_linux_and_windows_json() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("shared_preferences.json"),
            r#"{"flutter.polling_interval_ms": 2000, "flutter.column_widths": "{\"pid\": 90}",
                "flutter.remote_hosts_v1": "{\"version\":1,\"profiles\":[]}", "other": 1}"#,
        )
        .unwrap();
        if cfg!(target_os = "macos") {
            return;
        }
        let document = import_flutter_preferences(dir.path()).unwrap();
        assert_eq!(document["settings"]["polling_interval_ms"], json!(2000));
        assert_eq!(document["settings"]["column_widths"]["pid"], json!(90));
        assert_eq!(document["remote_hosts_v1"]["version"], json!(1));
    }

    #[test]
    fn reads_xml_property_lists() {
        let xml = r#"<?xml version="1.0"?><plist version="1.0"><dict>
            <key>flutter.row_heatmap</key><false/>
            <key>flutter.saved_filters</key><array><string>all:a&amp;b</string></array>
            <key>flutter.inspector_width</key><real>400.5</real>
            <key>flutter.polling_interval_ms</key><integer>500</integer>
            </dict></plist>"#;
        let map = parse_plist(xml).unwrap();
        assert_eq!(map["flutter.row_heatmap"], json!(false));
        assert_eq!(map["flutter.saved_filters"], json!(["all:a&b"]));
        assert_eq!(map["flutter.inspector_width"], json!(400.5));
        assert_eq!(map["flutter.polling_interval_ms"], json!(500));
    }
}
