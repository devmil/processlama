//! The pump: drains the inbox into the core on the GUI thread, then projects
//! what changed onto the QObjects, one borrow at a time.

use crate::app_state::AppState;
use crate::plumbing::{Inbox, SystemClock, TimerThread};
use crate::tree_model::{ProcessTreeModel, icon_url};
use processlama_application::{
    AppCore, CoreChanges, InspectorView, SourcePhase, ToastTone, TreeView, UiEvent, diagnostics,
};
use processlama_domain::{
    DetailSection, HostOperatingSystem, NetworkRateSource, NetworkUnavailableReason, ProcessPorts,
    RemoteConnectionPhase, SearchOptions, SearchQuery,
};
use processlama_presentation::snapshot_label;
use qtbridge::qobject;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

pub struct Driver {
    pub core: AppCore,
    pub inbox: Arc<Inbox>,
    pub clock: Arc<SystemClock>,
    pub timers: TimerThread,
    pub state: Rc<RefCell<AppState>>,
    pub model: Rc<RefCell<ProcessTreeModel>>,
    pub platform: Value,
    first: bool,
}

#[qobject(ConvertToCamelCase)]
mod pump {
    use super::*;

    #[derive(Default)]
    pub struct Pump {
        pub driver: Option<Rc<RefCell<Driver>>>,
    }

    impl Pump {
        #[qslot]
        fn pump(&mut self) {
            if let Some(driver) = self.driver.clone() {
                driver.borrow_mut().pump();
            }
        }
    }
}

pub use pump::Pump;

impl Driver {
    pub fn new(
        core: AppCore,
        inbox: Arc<Inbox>,
        clock: Arc<SystemClock>,
        timers: TimerThread,
        state: Rc<RefCell<AppState>>,
        model: Rc<RefCell<ProcessTreeModel>>,
        platform: Value,
    ) -> Self {
        model
            .borrow_mut()
            .set_icon_cache(Arc::clone(core.icon_cache()));
        Self {
            core,
            inbox,
            clock,
            timers,
            state,
            model,
            platform,
            first: true,
        }
    }

    pub fn pump(&mut self) {
        let events = self.inbox.take();
        for event in events {
            self.core.handle(event);
        }
        self.sync();
        let deadline = self
            .core
            .next_deadline()
            .map(|at| self.clock.instant_at(at));
        self.timers.schedule(deadline);
    }

    /// Projects what changed. Model first, then the state object, so each
    /// publication runs with only its own object borrowed.
    pub fn sync(&mut self) {
        let mut changes = self.core.take_changes();
        if self.first {
            self.first = false;
            changes = CoreChanges {
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
        }
        let ui_events = self.core.take_ui_events();
        let tree = self.core.active_session().tree().clone();
        let icon_revision = self.core.icons_revision();
        if changes.tree || changes.settings || changes.tabs || changes.icons {
            let key = self.core.active_tab().key.clone();
            let columns = processlama_domain::normalized_visible_columns(
                &self.core.settings().visible_columns,
            );
            self.model
                .borrow_mut()
                .apply(&tree, &columns, &key, icon_revision);
        }
        let mut state = self.state.borrow_mut();
        if changes.settings {
            let value = settings_json(&self.core);
            if state.settings != value {
                state.settings = value;
                state.settings_changed();
            }
        }
        if changes.settings || changes.tree || changes.session_meta || changes.snapshots {
            let value = saved_filters_json(&self.core, &tree);
            if state.saved_filters != value {
                state.saved_filters = value;
                state.saved_filters_changed();
            }
        }
        if changes.network || changes.update || state.platform.is_null() {
            let mut platform = self.platform.clone();
            platform["updateSupported"] = json!(self.core.update_supported());
            platform["networkSupported"] = json!(self.core.network_supported());
            if state.platform != platform
                || state.network_available != self.core.network_available()
            {
                state.platform = platform;
                state.network_available = self.core.network_available();
                state.platform_changed();
            }
        }
        if changes.tabs || changes.connections || changes.remote_hosts {
            let tabs = tabs_json(&self.core);
            let active = self.core.active_tab().key.clone();
            let index = self.core.active_index() as i32;
            if state.tabs != tabs || state.active_tab != active || state.active_tab_index != index {
                state.tabs = tabs;
                state.active_tab = active;
                state.active_tab_index = index;
                state.tabs_changed();
            }
        }
        if changes.tree
            || changes.session_meta
            || changes.connections
            || changes.network
            || changes.tabs
            || changes.snapshots
        {
            let value = session_json(&self.core, &tree);
            if state.session != value {
                state.session = value;
                state.session_changed();
            }
            let pinned = pinned_json(&self.core, &tree);
            if state.pinned_rows != pinned {
                state.pinned_rows = pinned;
                state.pinned_changed();
            }
        }
        if changes.inspector
            || changes.tabs
            || changes.network
            || changes.icons
            || changes.connections
        {
            let value = inspector_json(&self.core, self.core.active_session().inspector());
            if state.inspector != value {
                state.inspector = value;
                state.inspector_changed();
            }
        }
        if changes.snapshots {
            let value: Vec<Value> = self
                .core
                .snapshots()
                .iter()
                .map(|entry| {
                    json!({
                        "path": entry.path,
                        "label": snapshot_label(entry),
                        "count": entry.process_count,
                        "name": entry.name,
                        "generatedAt": entry.generated_at_unix_ms,
                        "platform": entry.platform,
                    })
                })
                .collect();
            if state.snapshots != value {
                state.snapshots = value;
                state.snapshots_changed();
            }
        }
        if changes.remote_hosts || changes.connections || changes.icons {
            let value = remote_hosts_json(&self.core);
            if state.remote_hosts != value {
                state.remote_hosts = value;
                state.remote_hosts_changed();
            }
        }
        if changes.icons {
            state.icon_revision = icon_revision as i32;
            state.icons_changed();
        }
        let detailed = diagnostics::is_detailed();
        if state.diagnostics_detailed != detailed {
            state.diagnostics_detailed = detailed;
            state.diagnostics_changed();
        }
        for event in ui_events {
            match event {
                UiEvent::Toast { key, args, tone } => {
                    let tone = match tone {
                        ToastTone::Neutral => "neutral",
                        ToastTone::Success => "success",
                        ToastTone::Error => "error",
                    };
                    state.toast(key.to_owned(), args, tone.to_owned());
                }
                UiEvent::UpdateAvailable {
                    installed_version,
                    installed_build,
                    version,
                    build,
                    installable,
                } => state.update_available(
                    installed_version,
                    installed_build.to_string(),
                    version,
                    build.to_string(),
                    installable,
                ),
                UiEvent::UpdateProgress { received, total } => {
                    state.update_progress(received as f64, total as f64)
                }
                UiEvent::UpdateInstalled { ok } => state.update_installed(ok),
                UiEvent::QuitForUpdate => state.quit_for_update(),
                UiEvent::ConfirmHelperInstall(prompt) => state.confirm_helper_install(json!({
                    "profileId": prompt.profile_id,
                    "host": prompt.host,
                    "platform": prompt.target.platform_label(),
                    "installPath": prompt.install_path,
                    "build": prompt.build_prefix,
                    "size": prompt.size,
                    "sha256": prompt.sha256_prefix,
                    "isUpdate": prompt.is_update,
                })),
                UiEvent::ProfileSaved {
                    request,
                    profile_id,
                    error,
                } => state.profile_saved(
                    request as i32,
                    profile_id.unwrap_or_default(),
                    error.unwrap_or_default().to_owned(),
                ),
                UiEvent::ProbeFinished {
                    request,
                    outcome,
                    platform,
                    compatibility,
                } => state.probe_finished(
                    request as i32,
                    format!("{outcome:?}"),
                    platform,
                    compatibility,
                ),
                UiEvent::CopyToClipboard { text, toast_key } => {
                    state.copy_to_clipboard(text, toast_key.to_owned())
                }
            }
        }
    }
}

fn settings_json(core: &AppCore) -> Value {
    let settings = core.settings();
    json!({
        "pollingIntervalMs": settings.polling_interval_ms,
        "rememberTreeExpansion": settings.remember_tree_expansion,
        "reduceBackgroundRefresh": settings.reduce_background_refresh,
        "savedFilters": settings.saved_filters,
        "visibleColumns": processlama_domain::normalized_visible_columns(&settings.visible_columns),
        "columnWidths": settings.column_widths,
        "inspectorWidth": settings.inspector_width,
        "appearanceMode": settings.appearance_mode.name(),
        "rowHeatmap": settings.row_heatmap,
        "rowDensity": settings.row_density.name(),
        "languageCode": settings.language_code,
        "releaseChannel": settings.release_channel.name(),
    })
}

fn saved_filters_json(core: &AppCore, tree: &TreeView) -> Vec<Value> {
    core.settings()
        .saved_filters
        .iter()
        .map(|saved| {
            let query = SearchQuery::parse(saved, SearchOptions::default());
            json!({
                "text": saved,
                "count": core.saved_filter_count(saved),
                "selected": tree.filter == query.text && tree.search_options.aspect == query.options.aspect,
            })
        })
        .collect()
}

fn phase_name(phase: RemoteConnectionPhase) -> &'static str {
    phase.name()
}

fn tabs_json(core: &AppCore) -> Vec<Value> {
    core.tabs()
        .iter()
        .map(|tab| match &tab.profile_id {
            None => json!({"key": tab.key, "local": true}),
            Some(profile_id) => {
                let profile = core.remote_hosts().profile(profile_id);
                let state = core.remote().connection_state(profile_id);
                let facts = state
                    .hello
                    .as_ref()
                    .map(|hello| hello.facts.clone())
                    .or_else(|| profile.and_then(|profile| profile.last_known.clone()));
                json!({
                    "key": tab.key,
                    "local": false,
                    "profileId": profile_id,
                    "label": profile.map(|p| p.display_name.clone()).unwrap_or_default(),
                    "alias": profile.map(|p| p.ssh_alias.clone()).unwrap_or_default(),
                    "phase": phase_name(state.phase),
                    "platform": facts.as_ref().map(|f| f.target.platform_label()),
                    "compatibility": facts.as_ref().map(|f| f.compatibility.to_string()),
                })
            }
        })
        .collect()
}

fn source_phase_name(phase: SourcePhase) -> &'static str {
    match phase {
        SourcePhase::Connecting => "connecting",
        SourcePhase::Live => "live",
        SourcePhase::Stale => "stale",
        SourcePhase::Failed => "failed",
    }
}

fn network_source_name(source: NetworkRateSource) -> &'static str {
    match source {
        NetworkRateSource::Ebpf => "ebpf",
        NetworkRateSource::Nettop => "nettop",
        NetworkRateSource::Helper => "helper",
        NetworkRateSource::None => "none",
    }
}

fn session_json(core: &AppCore, tree: &TreeView) -> Value {
    let tab = core.active_tab();
    let session = &tab.session;
    let capabilities = session.capabilities();
    let loaded = session.loaded_snapshot_path().map(str::to_owned);
    let source_label = loaded.as_ref().map(|path| {
        core.snapshots()
            .iter()
            .find(|entry| &entry.path == path)
            .map(snapshot_label)
            .unwrap_or_else(|| path.rsplit(['/', '\\']).next().unwrap_or(path).to_owned())
    });
    let live = loaded.is_none();
    let remote = tab.profile_id.as_ref().map(|profile_id| {
        let profile = core.remote_hosts().profile(profile_id);
        let state = core.remote().connection_state(profile_id);
        let source = session.source_state();
        let target = state.hello.as_ref().map(|hello| hello.facts.target);
        json!({
            "profileId": profile_id,
            "host": profile.map(|p| p.display_name.clone()).unwrap_or_default(),
            "alias": profile.map(|p| p.ssh_alias.clone()).unwrap_or_default(),
            "phase": phase_name(state.phase),
            "failure": state.failure.map(|code| code.name()),
            "needsHelper": state.needs_helper(),
            "connectedSince": state.connected_since,
            "sourcePhase": source_phase_name(source.phase),
            "lastSampleAt": source.last_sample_at_ms,
            "target": target.map(|t| t.wire_name()),
            "installable": capabilities.network_unavailable_reason == Some(NetworkUnavailableReason::ServiceNotInstalled),
        })
    });
    let network_unavailable = live
        && if tab.profile_id.is_some() {
            capabilities.network_source == NetworkRateSource::None
        } else {
            core.network_supported() && !core.network_available()
        };
    json!({
        "key": tab.key,
        "isRemote": tab.profile_id.is_some(),
        "profileId": tab.profile_id,
        "loadedSnapshotPath": loaded,
        "sourceLabel": source_label,
        "platform": tree.snapshot.platform,
        "snapshotError": tree.snapshot.error,
        "filter": session.filter(),
        "searchAspect": session.search_options().aspect.name(),
        "matchCase": session.search_options().match_case,
        "wholeWord": session.search_options().whole_word,
        "frozen": tree.lock.is_frozen,
        "hasQueued": tree.lock.has_queued_structural_mutations,
        "queuedCount": tree.lock.queued_process_count,
        "orderLocked": tree.lock.is_order_locked_by_interaction,
        "processCount": tree.snapshot.processes.len(),
        "focused": tree.focused.is_some(),
        "focusedName": tree.focused_name,
        "focusStackDepth": tree.focus_stack_depth,
        "treeSearchQuery": tree.tree_search_query,
        "treeSearchMatchCount": tree.tree_search_match_count,
        "treeSearchMatchIndex": tree.tree_search_selected_match_index,
        "sortColumn": tree.sort_column.name(),
        "sortAscending": tree.sort_direction == processlama_domain::SortDirection::Ascending,
        "hidepid": capabilities.hidepid,
        "networkSource": network_source_name(capabilities.network_source),
        "networkUnavailable": network_unavailable,
        "linux": capabilities.operating_system == HostOperatingSystem::Linux,
        "remote": remote,
    })
}

fn pinned_json(core: &AppCore, tree: &TreeView) -> Vec<Value> {
    let cache = core.icon_cache();
    tree.rows
        .iter()
        .filter(|row| tree.pinned.contains(&row.identity))
        .map(|row| {
            json!({
                "key": row.identity.key(),
                "name": row.record.display_name(),
                "pid": row.record.pid,
                "iconUrl": icon_url(row.record.icon.as_ref(), Some(cache)),
            })
        })
        .collect()
}

fn ports_json(ports: Option<&ProcessPorts>) -> Value {
    match ports {
        None => Value::Null,
        Some(ports) => {
            json!({"listening": ports.listening, "other": ports.other, "count": ports.count()})
        }
    }
}

fn history(samples: &Arc<[f32]>) -> Value {
    Value::Array(
        samples
            .iter()
            .map(|sample| {
                if sample.is_finite() {
                    json!(f64::from(*sample))
                } else {
                    Value::Null
                }
            })
            .collect(),
    )
}

fn section<T>(section: &DetailSection<T>, value: impl FnOnce(&T) -> Value) -> Value {
    match section {
        DetailSection::Available(inner) => json!({"state": "available", "value": value(inner)}),
        DetailSection::Restricted(reason) => json!({"state": "restricted", "reason": reason}),
        DetailSection::Unsupported(reason) => json!({"state": "unsupported", "reason": reason}),
        DetailSection::NotFound(reason) => json!({"state": "notFound", "reason": reason}),
    }
}

fn inspector_json(core: &AppCore, inspector: &InspectorView) -> Value {
    let Some(process) = &inspector.process else {
        return json!({"hasProcess": false});
    };
    let cache = core.icon_cache();
    let row = inspector.row.as_ref();
    let detail = inspector.detail.as_ref().map(|detail| {
        json!({
            "files": section(&detail.files, |files| Value::Array(files.iter().map(|file| json!({
                "fd": file.fd, "kind": file.kind, "path": file.path,
            })).collect())),
            "sockets": section(&detail.sockets, |sockets| Value::Array(sockets.iter().map(|endpoint| json!({
                "protocol": endpoint.protocol,
                "localAddress": endpoint.local_address,
                "localPort": endpoint.local_port,
                "localApproximate": endpoint.local_address_approximate,
                "remoteAddress": endpoint.remote_address,
                "remotePort": endpoint.remote_port,
                "remoteApproximate": endpoint.remote_address_approximate,
                "state": endpoint.state,
            })).collect())),
            "threads": section(&detail.threads, |threads| json!({
                "summary": threads.summary.as_ref().map(|summary| json!({
                    "threadCount": summary.thread_count,
                    "machSyscallCount": summary.mach_syscall_count,
                })),
                "threads": threads.threads.iter().map(|thread| json!({
                    "id": thread.thread_id,
                    "cpu": thread.cpu_percent,
                    "approximate": thread.cpu_percent_approximate,
                    "state": thread.state,
                })).collect::<Vec<_>>(),
            })),
            "security": section(&detail.security, |security| json!({
                "signingStatus": security.signing_status,
                "signingAuthority": security.signing_authority,
                "teamId": security.team_id,
                "bundleId": security.bundle_id,
                "entitlementsSummary": security.entitlements_summary,
                "gatekeeperOrigin": security.gatekeeper_origin,
                "sandbox": security.sandbox,
                "hardenedRuntime": security.hardened_runtime,
                "architecture": security.architecture,
                "rosettaTranslated": security.rosetta_translated,
            })),
        })
    });
    let owners: Vec<Value> = inspector
        .listener_owners_by_port
        .iter()
        .flat_map(|(port, owners)| {
            owners.iter().map(move |owner| {
                json!({"port": port, "key": owner.identity.key(), "pid": owner.pid, "name": owner.name})
            })
        })
        .collect();
    let histories = inspector.histories.as_ref().map(|h| {
        json!({
            "treeCpu": history(&h.tree_cpu), "treeGpu": history(&h.tree_gpu), "treeRss": history(&h.tree_rss),
            "treeNetIn": history(&h.tree_network_in), "treeNetOut": history(&h.tree_network_out),
            "treeStorageRead": history(&h.tree_storage_read), "treeStorageWrite": history(&h.tree_storage_write),
            "cpu": history(&h.cpu), "gpu": history(&h.gpu), "rss": history(&h.rss),
            "netIn": history(&h.network_in), "netOut": history(&h.network_out),
            "storageRead": history(&h.storage_read), "storageWrite": history(&h.storage_write),
        })
    });
    json!({
        "hasProcess": true,
        "key": inspector.identity.map(|identity| identity.key()),
        "name": process.display_name(),
        "pid": process.pid,
        "ppid": process.ppid,
        "uid": process.uid,
        "user": process.user,
        "status": process.status.name(),
        "threads": process.thread_count,
        "openFiles": process.open_file_count,
        "virtualMemory": process.virtual_memory_bytes,
        "nice": process.nice,
        "priority": process.priority,
        "cpu": process.cpu_usage,
        "gpu": process.gpu_usage,
        "rss": process.rss_bytes,
        "netIn": process.network_in_bytes_per_second,
        "netOut": process.network_out_bytes_per_second,
        "totalNetIn": process.total_network_in_bytes,
        "totalNetOut": process.total_network_out_bytes,
        "storageRead": process.storage_read_bytes_per_second,
        "storageWrite": process.storage_write_bytes_per_second,
        "totalStorageRead": process.total_storage_read_bytes,
        "totalStorageWrite": process.total_storage_write_bytes,
        "storageAvailable": process.storage_io_available,
        "startTime": process.start_time_unix_ms,
        "executable": process.executable_path,
        "bundle": process.app_bundle_path,
        "commandLine": process.command_line,
        "platform": inspector.platform,
        "iconUrl": icon_url(process.icon.as_ref(), Some(cache)),
        "marker": match inspector.change_marker {
            processlama_application::ChangeMarker::None => 0,
            processlama_application::ChangeMarker::Spawned => 1,
            processlama_application::ChangeMarker::Terminated => 2,
        },
        "rowVisible": row.is_some(),
        "tree": row.map(|row| json!({
            "cpu": row.tree_cpu, "gpu": row.tree_gpu, "rss": row.tree_rss,
            "netIn": row.tree_network_in, "netOut": row.tree_network_out,
            "storageRead": row.tree_storage_read, "storageWrite": row.tree_storage_write,
            "storageAvailable": row.tree_storage_available, "descendants": row.descendant_count,
        })),
        "ports": ports_json(inspector.ports.as_ref()),
        "treePorts": ports_json(inspector.tree_ports.as_ref()),
        "listenerOwners": owners,
        "histories": histories,
        "detail": detail,
    })
}

fn remote_hosts_json(core: &AppCore) -> Value {
    let state = core.remote_hosts();
    let profiles: Vec<Value> = state
        .profiles
        .iter()
        .map(|profile| {
            let connection = core.remote().connection_state(&profile.id);
            json!({
                "id": profile.id,
                "displayName": profile.display_name,
                "alias": profile.ssh_alias,
                "autoInstallHelper": profile.auto_install_helper,
                "autoReconnect": profile.auto_reconnect,
                "openOnStartup": profile.open_on_startup,
                "backgroundRefresh": profile.background_refresh.map(|mode| mode.name()),
                "lastKnownPlatform": profile.last_known.as_ref().map(|facts| facts.target.platform_label()),
                "lastKnownCompatibility": profile.last_known.as_ref().map(|facts| facts.compatibility),
                "phase": phase_name(connection.phase),
                "failure": connection.failure.map(|code| code.name()),
                "needsHelper": connection.needs_helper(),
                "open": core.tabs().iter().any(|tab| tab.profile_id.as_deref() == Some(profile.id.as_str())),
            })
        })
        .collect();
    json!({
        "profiles": profiles,
        "defaultBackgroundRefresh": state.default_background_refresh.name(),
        "iconCacheBytes": state.icon_cache_bytes,
        "iconCacheUsed": core.icon_cache().total_bytes(),
    })
}
