//! ProcessLama's composition root: builds the core over its adapters, the Qt
//! objects and the QML window, and owns every lifetime until exit.

mod hooks;

use hooks::PlatformHooks;
use processlama_application::{AppCore, CorePorts, InstalledVersion, diagnostics};
use processlama_domain::ReleaseChannel;
use processlama_infra_local::{LocalTelemetryAdapter, configure_icon_cache, local_operating_system};
use processlama_infra_platform::{LinuxNetworkService, ReleaseUpdateChecker};
use processlama_infra_remote::SshConnector;
use processlama_infra_storage::{FileIconCache, FileSettingsStore, FileSnapshotStore, application_support_dir};
use processlama_qt::{AppState, Driver, Inbox, ProcessTreeModel, Pump, SystemClock, TimerThread, WorkerPool};
use qtbridge::qtbridge_type_lib::QVariant;
use qtbridge::{QApp, QObjectHolder};
use serde_json::{Value, json};
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

static RESOURCES: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/processlama.rcc"));

const VERSION: &str = env!("PROCESSLAMA_VERSION");
const BUILD: &str = env!("PROCESSLAMA_BUILD");

/// The Qt application name: on Linux it is the Wayland app id and must match
/// the desktop entry.
const APPLICATION_NAME: &str = if cfg!(target_os = "linux") {
    "de.devmil.processlama"
} else {
    "ProcessLama"
};

fn default_release_channel() -> ReleaseChannel {
    match option_env!("PROCESSLAMA_RELEASE_CHANNEL") {
        Some(channel) => ReleaseChannel::parse(channel),
        None => ReleaseChannel::Stable,
    }
}

fn os_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "linux"
    }
}

/// The license documents the About dialog lists, by package.
fn license_packages() -> Value {
    let root = |name: &str, text: &str| json!({"name": name, "licenses": [text]});
    Value::Array(vec![
        root("ProcessLama", include_str!("../../../../LICENSE")),
        root("ProcessLama notices", include_str!("../../../../LICENSES/NOTICE.txt")),
        root(
            "ProcessLama network eBPF program",
            include_str!("../../../../LICENSES/GPL-2.0-only.txt"),
        ),
        root("libbpf", include_str!("../../../../LICENSES/libbpf-BSD-2-Clause.txt")),
        root("libbpf-rs", include_str!("../../../../LICENSES/libbpf-rs-BSD-2-Clause.txt")),
        root("Geist", include_str!("../../../../LICENSES/Geist-OFL-1.1.txt")),
        json!({"name": "Qt", "licenses": [
            include_str!("../../../../LICENSES/QT-NOTICE.md"),
            include_str!("../../../../LICENSES/LGPL-3.0.txt"),
        ]}),
        root(
            "Rust production dependencies",
            include_str!("../../../../LICENSES/RUST-DEPENDENCIES.md"),
        ),
    ])
}

/// A snapshot document passed on the command line opens at startup.
fn startup_snapshot() -> Option<String> {
    std::env::args()
        .skip(1)
        .find(|argument| !argument.starts_with('-') && argument.ends_with(".json"))
}

fn main() {
    diagnostics::info("process_start");
    let mut application = QApp::new();
    application.application_name(APPLICATION_NAME);
    assert!(
        qtbridge::qresource::register_bytes(RESOURCES),
        "failed to register the embedded QML resource"
    );

    let support = application_support_dir();
    configure_icon_cache(Some(std::env::temp_dir().join("processlama/process-icons")));

    let inbox = Inbox::new();
    let clock = SystemClock::new();
    let workers = WorkerPool::new(4);
    let language = sys_locale::get_locale()
        .map(|locale| locale.split(['-', '_']).next().unwrap_or("en").to_owned())
        .unwrap_or_else(|| "en".to_owned());
    let installed = InstalledVersion {
        version: VERSION.to_owned(),
        build: BUILD.parse().unwrap_or(0),
    };
    let ports = CorePorts {
        sink: inbox.clone(),
        executor: workers.clone(),
        clock: clock.clone(),
        local: Box::new(LocalTelemetryAdapter::new(inbox.clone())),
        local_os: local_operating_system(),
        snapshots: Arc::new(FileSnapshotStore::new(&support)),
        settings: Arc::new(FileSettingsStore::open(support.clone(), &language, default_release_channel())),
        updates: Arc::new(ReleaseUpdateChecker::new(
            installed,
            std::env::var("PROCESSLAMA_RELEASE_MANIFEST_URL").ok(),
        )),
        network: Arc::new(LinuxNetworkService),
        remote: Arc::new(SshConnector::new()),
        icon_cache: Arc::new(FileIconCache::open(support.join("remote-icons/v1"))),
    };
    let core = AppCore::new(ports);

    let state = Rc::new(RefCell::new(AppState::default()));
    AppState::attach_qobject(&state);
    state.borrow_mut().set_inbox(inbox.clone());
    if let Some(path) = startup_snapshot() {
        state.borrow_mut().startup_snapshot = path;
    }
    let model = Rc::new(RefCell::new(ProcessTreeModel::default()));
    ProcessTreeModel::attach_qobject(&model);
    let platform = json!({
        "os": os_name(),
        "version": VERSION,
        "build": BUILD,
        "hyprland": std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some(),
    });
    let timers = TimerThread::start(inbox.clone());
    let driver = Rc::new(RefCell::new(Driver::new(
        core,
        inbox.clone(),
        clock,
        timers,
        Rc::clone(&state),
        Rc::clone(&model),
        platform,
    )));
    let pump = Rc::new(RefCell::new(Pump::default()));
    Pump::attach_qobject(&pump);
    pump.borrow_mut().driver = Some(Rc::clone(&driver));
    driver.borrow_mut().pump();
    inbox.bind(pump.borrow().get_qml_method_invoker());

    let hooks = Rc::new(RefCell::new(PlatformHooks::default()));
    PlatformHooks::attach_qobject(&hooks);

    // PROCESSLAMA_QML_DIR loads the QML from a checkout instead of the
    // embedded resource, for iterating on the UI without rebuilding.
    let (import_path, main_qml) = match std::env::var("PROCESSLAMA_QML_DIR") {
        Ok(dir) if !dir.is_empty() => {
            let dir = std::path::Path::new(&dir).canonicalize().unwrap_or_else(|_| dir.clone().into());
            (
                dir.display().to_string(),
                format!("file://{}/ProcessLama/Main.qml", dir.display()),
            )
        }
        _ => ("qrc:/".to_owned(), "qrc:/ProcessLama/Main.qml".to_owned()),
    };
    let properties = vec![
        ("app", state.borrow().as_qvariant()),
        ("treeModel", model.borrow().as_qvariant()),
        ("hooks", hooks.borrow().as_qvariant()),
        ("licensePackages", QVariant::from(license_packages().to_string())),
    ];
    let exit_code = application
        .add_import_path(&import_path)
        .with_initial_properties(&properties)
        .load_qml_from_file(&main_qml)
        .run();

    {
        let mut driver = driver.borrow_mut();
        driver.core.dispose();
        driver.timers.stop();
    }
    // Close the QML engine while the context objects are still alive.
    drop(application);
    workers.shutdown();
    drop(pump);
    drop(hooks);
    if exit_code != 0 {
        std::process::exit(exit_code);
    }
}
