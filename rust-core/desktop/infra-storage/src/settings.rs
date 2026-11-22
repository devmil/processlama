use crate::files::write_atomically;
use processlama_application::SettingsStore;
use processlama_domain::{AppSettings, RemoteHostsState, SUPPORTED_LANGUAGES, ReleaseChannel};
use serde_json::{Map, Value};
use std::path::PathBuf;
use std::sync::Mutex;

/// `settings.json` with a `settings` object and the `remote_hosts_v1` value.
pub struct FileSettingsStore {
    path: PathBuf,
    defaults: AppSettings,
    /// Serializes writes of both sections into the one file.
    document: Mutex<Map<String, Value>>,
}

impl FileSettingsStore {
    /// `system_language` picks the default language; `default_channel` the
    /// release channel a build defaults to.
    pub fn open(directory: PathBuf, system_language: &str, default_channel: ReleaseChannel) -> Self {
        let path = directory.join("settings.json");
        let mut defaults = AppSettings::default();
        let language = system_language.to_lowercase();
        if SUPPORTED_LANGUAGES.contains(&language.as_str()) {
            defaults.language_code = language;
        }
        defaults.release_channel = default_channel;
        let mut document = std::fs::read(&path)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .and_then(|value| value.as_object().cloned());
        if document.is_none() {
            // First launch of the Qt build: take the Flutter preferences.
            document = crate::preferences::import_flutter_preferences(&directory);
            if let Some(imported) = &document {
                let _ = write_atomically(&path, &serde_json::to_vec_pretty(&Value::Object(imported.clone())).unwrap_or_default());
            }
        }
        Self {
            path,
            defaults,
            document: Mutex::new(document.unwrap_or_default()),
        }
    }

    fn write(&self, key: &str, value: Value) -> Result<(), String> {
        let mut document = self.document.lock().map_err(|_| "settings lock".to_owned())?;
        document.insert(key.to_owned(), value);
        let bytes = serde_json::to_vec_pretty(&Value::Object(document.clone())).map_err(|e| e.to_string())?;
        write_atomically(&self.path, &bytes).map_err(|e| e.to_string())
    }
}

impl SettingsStore for FileSettingsStore {
    fn load_settings(&self) -> AppSettings {
        let document = self.document.lock().map(|d| d.clone()).unwrap_or_default();
        document
            .get("settings")
            .map_or_else(|| self.defaults.clone(), |value| AppSettings::from_json(value, &self.defaults))
    }

    fn save_settings(&self, settings: &AppSettings) -> Result<(), String> {
        self.write("settings", settings.to_json())
    }

    fn load_remote_hosts(&self) -> RemoteHostsState {
        let document = self.document.lock().map(|d| d.clone()).unwrap_or_default();
        document
            .get("remote_hosts_v1")
            .map(RemoteHostsState::from_json)
            .unwrap_or_default()
    }

    fn save_remote_hosts(&self, state: &RemoteHostsState) -> Result<(), String> {
        self.write("remote_hosts_v1", state.to_json())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_and_remote_hosts_share_one_file() {
        let dir = tempfile::tempdir().unwrap();
        let store = FileSettingsStore::open(dir.path().to_owned(), "de", ReleaseChannel::Stable);
        assert_eq!(store.load_settings().language_code, "de");
        let mut settings = store.load_settings();
        settings.polling_interval_ms = 2000;
        store.save_settings(&settings).unwrap();
        let mut hosts = RemoteHostsState::default();
        hosts.open_tabs.clear();
        hosts.icon_cache_bytes = 2 * 1024 * 1024;
        store.save_remote_hosts(&hosts).unwrap();
        let reopened = FileSettingsStore::open(dir.path().to_owned(), "en", ReleaseChannel::Stable);
        assert_eq!(reopened.load_settings().polling_interval_ms, 2000);
        assert_eq!(reopened.load_remote_hosts().icon_cache_bytes, 2 * 1024 * 1024);
    }
}
