//! Embeds the QML, Meridian, fonts and brand art as one Qt resource.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("manifest dir"));
    let root = manifest.join("../../..").canonicalize().expect("repository root");
    let version = fs::read_to_string(root.join("VERSION")).expect("VERSION");
    let mut lines = version.lines();
    let marketing = lines.next().unwrap_or("0.0.0").trim().to_owned();
    let build = lines.next().unwrap_or("0").trim().to_owned();
    println!("cargo:rustc-env=PROCESSLAMA_VERSION={marketing}");
    println!("cargo:rustc-env=PROCESSLAMA_BUILD={build}");
    println!("cargo:rerun-if-changed={}", root.join("VERSION").display());
    println!("cargo:rerun-if-env-changed=PROCESSLAMA_RELEASE_CHANNEL");

    let groups: Vec<(PathBuf, &str, fn(&Path) -> bool)> = vec![
        (root.join("qml/ProcessLama"), "ProcessLama", |_| true),
        (root.join("qml/Meridian"), "Meridian", |_| true),
        (root.join("assets/fonts/geist"), "ProcessLama/fonts", |p| {
            p.extension().is_some_and(|e| e == "ttf")
        }),
        (root.join("resources/brand"), "ProcessLama/brand", |p| {
            p.extension().is_some_and(|e| e == "svg" || e == "png")
        }),
    ];
    let mut document = String::from("<RCC>\n  <qresource prefix=\"/\">\n");
    for (directory, alias_root, keep) in &groups {
        println!("cargo:rerun-if-changed={}", directory.display());
        let mut files = Vec::new();
        collect(directory, &mut files);
        files.sort();
        for file in files.into_iter().filter(|f| keep(f)) {
            println!("cargo:rerun-if-changed={}", file.display());
            let relative = file
                .strip_prefix(directory)
                .expect("inside its root")
                .to_string_lossy()
                .replace('\\', "/");
            document.push_str(&format!(
                "    <file alias=\"{}/{}\">{}</file>\n",
                escape(alias_root),
                escape(&relative),
                escape(&file.to_string_lossy())
            ));
        }
    }
    document.push_str("  </qresource>\n</RCC>\n");
    let out = PathBuf::from(env::var("OUT_DIR").expect("out dir"));
    let qrc = out.join("processlama.qrc");
    fs::write(&qrc, document).expect("write qrc");
    let rcc = find_rcc().expect("Qt rcc was not found; set RCC or install the Qt 6 development tools");
    let status = Command::new(&rcc)
        .args(["-binary", "-o"])
        .arg(out.join("processlama.rcc"))
        .arg(&qrc)
        .status()
        .expect("start rcc");
    assert!(status.success(), "rcc failed");
}

fn collect(directory: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(&path, files);
        } else {
            files.push(path);
        }
    }
}

fn escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn find_rcc() -> Option<PathBuf> {
    if let Some(configured) = env::var_os("RCC") {
        return Some(PathBuf::from(configured));
    }
    let exe = if cfg!(windows) { "rcc.exe" } else { "rcc" };
    let configured = env::var("QMAKE").ok();
    println!("cargo:rerun-if-env-changed=QMAKE");
    for qmake in configured.iter().map(String::as_str).chain(["qmake6", "qmake"]) {
        for key in ["QT_HOST_LIBEXECS", "QT_HOST_BINS", "QT_INSTALL_LIBEXECS", "QT_INSTALL_BINS"] {
            if let Ok(output) = Command::new(qmake).args(["-query", key]).output()
                && output.status.success()
            {
                let candidate = PathBuf::from(String::from_utf8_lossy(&output.stdout).trim()).join(exe);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }
    }
    None
}
