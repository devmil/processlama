//! The window's state and commands.
//!
//! Properties are projections the driver sets after each pump; commands post
//! into the inbox and never publish synchronously, so no QML binding re-enters
//! a borrowed bridge object.

use processlama_application::{
    Command, CoreEvent, EventSink, InstallChoice, ProfileDraft, RemoteCommand, WindowActivity,
    diagnostics,
};
use processlama_domain::{
    AppearanceMode, BackgroundRefreshMode, ProcessIdentity, ProcessSignal, ReleaseChannel,
    RowDensity, SearchAspect, SortColumn,
};
use qtbridge::qobject;
use serde_json::Value;
use std::sync::Arc;

#[qobject(ConvertToCamelCase)]
mod app_state {
    use super::*;

    pub struct AppState {
        inbox: Option<Arc<dyn EventSink>>,
        pub(crate) settings: Value,
        pub(crate) platform: Value,
        pub(crate) tabs: Vec<Value>,
        pub(crate) active_tab: String,
        pub(crate) active_tab_index: i32,
        pub(crate) session: Value,
        pub(crate) inspector: Value,
        pub(crate) snapshots: Vec<Value>,
        pub(crate) remote_hosts: Value,
        pub(crate) pinned_rows: Vec<Value>,
        pub(crate) saved_filters: Vec<Value>,
        pub(crate) icon_revision: i32,
        pub(crate) network_available: bool,
        pub(crate) diagnostics_detailed: bool,
        pub startup_snapshot: String,
    }

    impl Default for AppState {
        fn default() -> Self {
            Self {
                inbox: None,
                settings: Value::Null,
                platform: Value::Null,
                tabs: Vec::new(),
                active_tab: "local".into(),
                active_tab_index: 0,
                session: Value::Null,
                inspector: Value::Null,
                snapshots: Vec::new(),
                remote_hosts: Value::Null,
                pinned_rows: Vec::new(),
                saved_filters: Vec::new(),
                icon_revision: 0,
                network_available: true,
                diagnostics_detailed: false,
                startup_snapshot: String::new(),
            }
        }
    }

    impl AppState {
        qproperty!("settings", Member = settings, Notify = settings_changed);
        qproperty!("platform", Member = platform, Notify = platform_changed);
        qproperty!("tabs", Member = tabs, Notify = tabs_changed);
        qproperty!("activeTab", Member = active_tab, Notify = tabs_changed);
        qproperty!(
            "activeTabIndex",
            Member = active_tab_index,
            Notify = tabs_changed
        );
        qproperty!("session", Member = session, Notify = session_changed);
        qproperty!("inspector", Member = inspector, Notify = inspector_changed);
        qproperty!("snapshots", Member = snapshots, Notify = snapshots_changed);
        qproperty!(
            "remoteHosts",
            Member = remote_hosts,
            Notify = remote_hosts_changed
        );
        qproperty!("pinnedRows", Member = pinned_rows, Notify = pinned_changed);
        qproperty!(
            "savedFilters",
            Member = saved_filters,
            Notify = saved_filters_changed
        );
        qproperty!(
            "iconRevision",
            Member = icon_revision,
            Notify = icons_changed
        );
        qproperty!(
            "networkAvailable",
            Member = network_available,
            Notify = platform_changed
        );
        qproperty!(
            "diagnosticsDetailed",
            Member = diagnostics_detailed,
            Notify = diagnostics_changed
        );
        qproperty!(
            "startupSnapshot",
            Member = startup_snapshot,
            Notify = platform_changed
        );

        #[qsignal]
        pub fn settings_changed(&mut self);
        #[qsignal]
        pub fn platform_changed(&mut self);
        #[qsignal]
        pub fn tabs_changed(&mut self);
        #[qsignal]
        pub fn session_changed(&mut self);
        #[qsignal]
        pub fn inspector_changed(&mut self);
        #[qsignal]
        pub fn snapshots_changed(&mut self);
        #[qsignal]
        pub fn remote_hosts_changed(&mut self);
        #[qsignal]
        pub fn pinned_changed(&mut self);
        #[qsignal]
        pub fn saved_filters_changed(&mut self);
        #[qsignal]
        pub fn icons_changed(&mut self);
        #[qsignal]
        pub fn diagnostics_changed(&mut self);

        /// A localized toast: `key` names the message, `args` fill it.
        #[qsignal]
        pub fn toast(&mut self, key: String, args: Vec<String>, tone: String);
        #[qsignal]
        pub fn update_available(
            &mut self,
            installed_version: String,
            installed_build: String,
            version: String,
            build: String,
            installable: bool,
        );
        /// An in-place update download: bytes received of `total`.
        #[qsignal]
        pub fn update_progress(&mut self, received: f64, total: f64);
        #[qsignal]
        pub fn update_installed(&mut self, ok: bool);
        /// The updated app started; the window quits.
        #[qsignal]
        pub fn quit_for_update(&mut self);
        #[qsignal]
        pub fn confirm_helper_install(&mut self, prompt: Value);
        #[qsignal]
        pub fn profile_saved(&mut self, request: i32, profile_id: String, error: String);
        #[qsignal]
        pub fn probe_finished(
            &mut self,
            request: i32,
            outcome: String,
            platform: String,
            compatibility: String,
        );
        #[qsignal]
        pub fn copy_to_clipboard(&mut self, text: String, toast_key: String);

        pub fn set_inbox(&mut self, inbox: Arc<dyn EventSink>) {
            self.inbox = Some(inbox);
        }

        fn send(&self, command: Command) {
            if let Some(inbox) = &self.inbox {
                inbox.post(CoreEvent::Command(command));
            }
        }

        fn identity(key: &str) -> Option<ProcessIdentity> {
            ProcessIdentity::parse_key(key)
        }

        // The explorer

        #[qslot]
        fn set_filter(&mut self, value: String) {
            self.send(Command::SetFilter(value));
        }
        #[qslot]
        fn set_search_aspect(&mut self, value: String) {
            if let Some(aspect) = SearchAspect::parse(&value) {
                self.send(Command::SetSearchAspect(aspect));
            }
        }
        #[qslot]
        fn set_search_match_case(&mut self, value: bool) {
            self.send(Command::SetSearchMatchCase(value));
        }
        #[qslot]
        fn set_search_whole_word(&mut self, value: bool) {
            self.send(Command::SetSearchWholeWord(value));
        }
        #[qslot]
        fn set_tree_search(&mut self, value: String) {
            self.send(Command::SetTreeSearch(value));
        }
        #[qslot]
        fn select_next_tree_search_match(&mut self) {
            self.send(Command::SelectNextTreeSearchMatch);
        }
        #[qslot]
        fn select_previous_tree_search_match(&mut self) {
            self.send(Command::SelectPreviousTreeSearchMatch);
        }
        #[qslot]
        fn toggle_expansion(&mut self, key: String) {
            if let Some(identity) = Self::identity(&key) {
                self.send(Command::ToggleExpansion(identity));
            }
        }
        #[qslot]
        fn select_process(&mut self, key: String) {
            if let Some(identity) = Self::identity(&key) {
                self.send(Command::SelectProcess(identity));
            }
        }
        #[qslot]
        fn select_next_visible(&mut self) {
            self.send(Command::SelectNextVisible);
        }
        #[qslot]
        fn select_previous_visible(&mut self) {
            self.send(Command::SelectPreviousVisible);
        }
        #[qslot]
        fn expand_selected(&mut self) {
            self.send(Command::ExpandSelected);
        }
        #[qslot]
        fn collapse_selected(&mut self) {
            self.send(Command::CollapseSelected);
        }
        #[qslot]
        fn expand_selected_subtree(&mut self) {
            self.send(Command::ExpandSelectedSubtree);
        }
        #[qslot]
        fn collapse_selected_subtree(&mut self) {
            self.send(Command::CollapseSelectedSubtree);
        }
        #[qslot]
        fn focus_selected_subtree(&mut self) {
            self.send(Command::FocusSelectedSubtree);
        }
        #[qslot]
        fn focus_subtree(&mut self, key: String) {
            if let Some(identity) = Self::identity(&key) {
                self.send(Command::FocusSubtree(identity));
            }
        }
        #[qslot]
        fn pop_subtree_focus(&mut self) {
            self.send(Command::PopSubtreeFocus);
        }
        #[qslot]
        fn clear_subtree_focus(&mut self) {
            self.send(Command::ClearSubtreeFocus);
        }
        #[qslot]
        fn sort_by(&mut self, column: String) {
            let sort = processlama_presentation::column_definition(&column)
                .map(|definition| definition.sort);
            if let Some(sort) = sort.or_else(|| SortColumn::parse(&column)) {
                self.send(Command::SortBy(sort));
            }
        }
        #[qslot]
        fn toggle_pin(&mut self, key: String) {
            if let Some(identity) = Self::identity(&key) {
                self.send(Command::TogglePin(identity));
            }
        }
        #[qslot]
        fn set_tree_hovering(&mut self, value: bool) {
            self.send(Command::SetTreeHovering(value));
        }
        #[qslot]
        fn set_tree_context_menu_open(&mut self, value: bool) {
            self.send(Command::SetTreeContextMenuOpen(value));
        }
        #[qslot]
        fn set_modal_overlay_open(&mut self, value: bool) {
            self.send(Command::SetModalOverlayOpen(value));
        }
        #[qslot]
        fn mark_tree_interaction(&mut self) {
            self.send(Command::MarkTreeInteraction);
        }
        #[qslot]
        fn set_window_resizing(&mut self, value: bool) {
            self.send(Command::SetWindowResizing(value));
        }
        /// `focused`, `unfocused` or `hidden`.
        #[qslot]
        fn set_window_activity(&mut self, value: String) {
            let activity = match value.as_str() {
                "hidden" => WindowActivity::Hidden,
                "unfocused" => WindowActivity::Unfocused,
                _ => WindowActivity::Focused,
            };
            self.send(Command::SetWindowActivity(activity));
        }
        #[qslot]
        fn set_inspector_detail_visible(&mut self, value: bool) {
            self.send(Command::SetInspectorDetailVisible(value));
        }
        #[qslot]
        fn toggle_frozen(&mut self) {
            self.send(Command::ToggleFrozen);
        }
        #[qslot]
        fn show_port(&mut self, port: i32) {
            if let Ok(port) = u16::try_from(port) {
                self.send(Command::ShowPort(port));
            }
        }
        #[qslot]
        fn send_signal(&mut self, key: String, signal: String) {
            let signal = match signal.as_str() {
                "terminate" => ProcessSignal::Terminate,
                "kill" => ProcessSignal::Kill,
                "suspend" => ProcessSignal::Suspend,
                "resume" => ProcessSignal::Resume,
                _ => return,
            };
            if let Some(identity) = Self::identity(&key) {
                self.send(Command::SendSignal(identity, signal));
            }
        }
        #[qslot]
        fn refresh(&mut self) {
            self.send(Command::Refresh);
        }

        // Snapshots

        #[qslot]
        fn take_snapshot(&mut self) {
            self.send(Command::TakeSnapshot);
        }
        #[qslot]
        fn open_snapshot(&mut self, path: String) {
            self.send(Command::OpenSnapshot(path));
        }
        #[qslot]
        fn show_live(&mut self) {
            self.send(Command::ShowLive);
        }
        #[qslot]
        fn export_snapshot(&mut self, path: String, target: String) {
            self.send(Command::ExportSnapshot { path, target });
        }
        #[qslot]
        fn rename_snapshot(&mut self, path: String, name: String) {
            self.send(Command::RenameSnapshot { path, name });
        }
        #[qslot]
        fn delete_snapshot(&mut self, path: String) {
            self.send(Command::DeleteSnapshot(path));
        }

        // Settings

        #[qslot]
        fn set_polling_interval(&mut self, value: i32) {
            self.send(Command::SetPollingInterval(value.max(0) as u32));
        }
        #[qslot]
        fn set_remember_tree_expansion(&mut self, value: bool) {
            self.send(Command::SetRememberTreeExpansion(value));
        }
        #[qslot]
        fn set_reduce_background_refresh(&mut self, value: bool) {
            self.send(Command::SetReduceBackgroundRefresh(value));
        }
        #[qslot]
        fn save_current_filter(&mut self) {
            self.send(Command::SaveCurrentFilter);
        }
        #[qslot]
        fn apply_saved_filter(&mut self, value: String) {
            self.send(Command::ApplySavedFilter(value));
        }
        #[qslot]
        fn remove_saved_filter(&mut self, value: String) {
            self.send(Command::RemoveSavedFilter(value));
        }
        #[qslot]
        fn set_visible_columns(&mut self, columns: Vec<String>) {
            self.send(Command::SetVisibleColumns(columns));
        }
        #[qslot]
        fn set_column_width(&mut self, column: String, width: f64) {
            self.send(Command::SetColumnWidth { column, width });
        }
        #[qslot]
        fn reset_column_width(&mut self, column: String) {
            self.send(Command::ResetColumnWidth(column));
        }
        #[qslot]
        fn set_inspector_width(&mut self, width: f64) {
            self.send(Command::SetInspectorWidth(width));
        }
        #[qslot]
        fn reset_inspector_width(&mut self) {
            self.send(Command::ResetInspectorWidth);
        }
        #[qslot]
        fn set_appearance(&mut self, value: String) {
            self.send(Command::SetAppearance(AppearanceMode::parse(&value)));
        }
        #[qslot]
        fn set_row_heatmap(&mut self, value: bool) {
            self.send(Command::SetRowHeatmap(value));
        }
        #[qslot]
        fn set_row_density(&mut self, value: String) {
            self.send(Command::SetRowDensity(RowDensity::parse(&value)));
        }
        #[qslot]
        fn set_release_channel(&mut self, value: String) {
            self.send(Command::SetReleaseChannel(ReleaseChannel::parse(&value)));
        }
        #[qslot]
        fn flush_settings(&mut self) {
            self.send(Command::FlushSettings);
        }

        // Tabs

        #[qslot]
        fn activate_tab(&mut self, key: String) {
            self.send(Command::ActivateTab(key));
        }
        #[qslot]
        fn activate_tab_index(&mut self, index: i32) {
            if let Ok(index) = usize::try_from(index) {
                self.send(Command::ActivateTabIndex(index));
            }
        }
        #[qslot]
        fn cycle_tabs(&mut self, backwards: bool) {
            self.send(Command::CycleTabs { backwards });
        }
        #[qslot]
        fn close_tab(&mut self, key: String) {
            self.send(Command::CloseTab(key));
        }
        #[qslot]
        fn move_tab(&mut self, from: i32, to: i32) {
            if let (Ok(from), Ok(to)) = (usize::try_from(from), usize::try_from(to)) {
                self.send(Command::MoveTab { from, to });
            }
        }

        // Remote hosts

        #[qslot]
        #[allow(clippy::too_many_arguments)]
        fn save_remote_host(
            &mut self,
            request: i32,
            id: String,
            alias: String,
            name: String,
            auto_install: bool,
            auto_reconnect: bool,
            open_on_startup: String,
            background_refresh: String,
        ) {
            let draft = ProfileDraft {
                ssh_alias: alias,
                display_name: name,
                auto_install_helper: auto_install,
                auto_reconnect,
                open_on_startup: match open_on_startup.as_str() {
                    "always" => Some(true),
                    "never" => Some(false),
                    _ => None,
                },
                background_refresh: BackgroundRefreshMode::parse(&background_refresh),
            };
            self.send(Command::Remote(RemoteCommand::SaveProfile {
                request: request.max(0) as u64,
                id: (!id.is_empty()).then_some(id),
                draft,
            }));
        }
        #[qslot]
        fn duplicate_remote_host(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::DuplicateProfile(id)));
        }
        #[qslot]
        fn remove_remote_host(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::RemoveProfile(id)));
        }
        #[qslot]
        fn test_remote_host(&mut self, request: i32, alias: String) {
            self.send(Command::Remote(RemoteCommand::TestConnection {
                request: request.max(0) as u64,
                alias,
            }));
        }
        #[qslot]
        fn open_remote_tab(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::OpenTab(id)));
        }
        #[qslot]
        fn connect_remote_host(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::Connect(id)));
        }
        #[qslot]
        fn disconnect_remote_host(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::Disconnect(id)));
        }
        #[qslot]
        fn answer_helper_install(&mut self, id: String, choice: String) {
            let choice = match choice.as_str() {
                "install" => InstallChoice::Install,
                "installAlways" => InstallChoice::InstallAlways,
                _ => InstallChoice::Cancel,
            };
            self.send(Command::Remote(RemoteCommand::InstallChoice {
                profile_id: id,
                choice,
            }));
        }
        #[qslot]
        fn remove_remote_helper(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::RemoveHelper(id)));
        }
        #[qslot]
        fn copy_network_install_command(&mut self, id: String) {
            self.send(Command::Remote(RemoteCommand::CopyNetworkInstallCommand(
                id,
            )));
        }
        #[qslot]
        fn set_default_background_refresh(&mut self, value: String) {
            if let Some(mode) = BackgroundRefreshMode::parse(&value) {
                self.send(Command::SetDefaultBackgroundRefresh(mode));
            }
        }
        #[qslot]
        fn set_remote_icon_cache_bytes(&mut self, bytes: f64) {
            self.send(Command::SetRemoteIconCacheBytes(bytes.max(0.0) as u64));
        }
        #[qslot]
        fn clear_remote_icon_cache(&mut self) {
            self.send(Command::ClearRemoteIconCache);
        }

        // Platform

        #[qslot]
        fn check_for_updates(&mut self) {
            self.send(Command::CheckForUpdates);
        }
        #[qslot]
        fn install_update(&mut self) {
            self.send(Command::InstallUpdate);
        }
        #[qslot]
        fn relaunch_after_update(&mut self) {
            self.send(Command::RelaunchAfterUpdate);
        }
        #[qslot]
        fn install_network_telemetry(&mut self) {
            self.send(Command::InstallNetworkTelemetry);
        }

        // Diagnostics

        #[qslot]
        fn set_diagnostics_detailed(&mut self, value: bool) {
            diagnostics::set_detailed(value);
            self.diagnostics_detailed = diagnostics::is_detailed();
            self.diagnostics_changed();
        }
        #[qslot]
        fn clear_diagnostics(&mut self) {
            diagnostics::clear();
        }
        #[qslot]
        fn diagnostics_snapshot(&self) -> String {
            let platform = self
                .platform
                .get("os")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            let version = self
                .platform
                .get("version")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            let build = self
                .platform
                .get("build")
                .and_then(Value::as_str)
                .unwrap_or("");
            diagnostics::snapshot("processlama", &format!("{version}+{build}"), platform)
        }
        /// Writes exported text to `url` (a `file:` URL or a path).
        #[qslot]
        fn write_text_file(&self, url: String, text: String) -> bool {
            let path = local_path(&url);
            std::fs::write(path, text).is_ok()
        }
        /// The local path of a `file:` URL from a file dialog.
        #[qslot]
        fn local_file(&self, url: String) -> String {
            local_path(&url)
        }
    }
}

/// Decodes `file:` URLs from QML file dialogs.
pub fn local_path(url: &str) -> String {
    let Some(rest) = url.strip_prefix("file://") else {
        return url.to_owned();
    };
    let mut bytes = Vec::with_capacity(rest.len());
    let raw = rest.as_bytes();
    let mut index = 0;
    while index < raw.len() {
        if raw[index] == b'%'
            && index + 3 <= raw.len()
            && let Ok(hex) = std::str::from_utf8(&raw[index + 1..index + 3])
            && let Ok(byte) = u8::from_str_radix(hex, 16)
        {
            bytes.push(byte);
            index += 3;
            continue;
        }
        bytes.push(raw[index]);
        index += 1;
    }
    let path = String::from_utf8_lossy(&bytes).into_owned();
    // `file:///C:/x` on Windows.
    if path.len() > 3 && path.as_bytes()[0] == b'/' && path.as_bytes()[2] == b':' {
        return path[1..].to_owned();
    }
    path
}

pub use app_state::AppState;

#[cfg(test)]
mod tests {
    use super::local_path;

    #[test]
    fn decodes_file_urls() {
        assert_eq!(local_path("file:///tmp/a%20b.json"), "/tmp/a b.json");
        assert_eq!(local_path("file:///tmp/%C3%A4.json"), "/tmp/ä.json");
        assert_eq!(local_path("file:///tmp/x%2"), "/tmp/x%2");
        assert_eq!(local_path("file:///tmp/ä%"), "/tmp/ä%");
        assert_eq!(local_path("file:///C:/Users/x.json"), "C:/Users/x.json");
        assert_eq!(local_path("/plain/path"), "/plain/path");
    }
}
