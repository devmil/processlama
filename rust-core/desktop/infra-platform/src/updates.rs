//! Update checks against the published release list.

use crate::appimage::{self, AppImageUpdate};
use processlama_application::{InstalledVersion, UpdateCheck, UpdateChecker};
use processlama_domain::ReleaseChannel;
use serde_json::Value;
use std::io::Read;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

pub const RELEASE_MANIFEST_URL: &str = "https://devmil.de/processlama/_data/releases.json";
#[cfg(target_os = "macos")]
pub const SPARKLE_FEED_URL: &str = "https://devmil.de/processlama/download/appcast.xml";

/// Reads the newest release of `channel` from `releases.json` (schema 2).
pub fn parse_release_manifest(
    document: &str,
    channel: ReleaseChannel,
    installed_build: u64,
) -> Result<UpdateCheck, String> {
    Ok(read_release(document, channel, installed_build)?.0)
}

/// The check and the newest release entry of `channel`.
fn read_release(
    document: &str,
    channel: ReleaseChannel,
    installed_build: u64,
) -> Result<(UpdateCheck, Value), String> {
    let value: Value = serde_json::from_str(document).map_err(|e| e.to_string())?;
    if value.get("schemaVersion").and_then(Value::as_u64) != Some(2) {
        return Err("The release list has an unsupported format.".into());
    }
    let track = match channel {
        ReleaseChannel::Beta => value.get("beta"),
        ReleaseChannel::Stable => Some(&value),
    }
    .filter(|track| track.is_object())
    .ok_or_else(|| "The selected release channel is missing.".to_owned())?;
    let latest = track.get("latest").unwrap_or(&Value::Null);
    if latest.is_null() {
        return Ok((UpdateCheck::NoPublishedRelease, Value::Null));
    }
    let version = latest
        .get("version")
        .and_then(Value::as_str)
        .ok_or_else(|| "The latest release entry is invalid.".to_owned())?;
    let build = latest
        .get("build")
        .and_then(Value::as_f64)
        .ok_or_else(|| "The latest release entry is invalid.".to_owned())? as u64;
    let check = if build > installed_build {
        UpdateCheck::UpdateAvailable {
            version: version.to_owned(),
            build,
            installable: false,
        }
    } else {
        UpdateCheck::UpToDate
    };
    Ok((check, latest.clone()))
}

pub struct ReleaseUpdateChecker {
    installed: InstalledVersion,
    manifest_url: String,
    /// The AppImage this process runs from: it updates in place.
    appimage: Option<PathBuf>,
    /// The verified update of the last check.
    pending: Mutex<Option<AppImageUpdate>>,
}

impl ReleaseUpdateChecker {
    pub fn new(installed: InstalledVersion, manifest_url: Option<String>) -> Self {
        Self {
            installed,
            manifest_url: manifest_url.unwrap_or_else(|| RELEASE_MANIFEST_URL.to_owned()),
            appimage: appimage::running_appimage(),
            pending: Mutex::new(None),
        }
    }

    fn fetch(&self) -> Result<String, String> {
        if !self.manifest_url.starts_with("https://") {
            return Err("The release list must use HTTPS.".into());
        }
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(10))
            .timeout(Duration::from_secs(25))
            .build();
        let response = agent
            .get(&self.manifest_url)
            .set("Accept", "application/json")
            .call()
            .map_err(http_error)?;
        response.into_string().map_err(|e| e.to_string())
    }
}

fn http_error(error: ureq::Error) -> String {
    match error {
        ureq::Error::Status(code, _) => format!("The release server returned HTTP {code}."),
        other => other.to_string(),
    }
}

impl UpdateChecker for ReleaseUpdateChecker {
    fn is_supported(&self) -> bool {
        true
    }

    fn installed(&self) -> InstalledVersion {
        self.installed.clone()
    }

    fn configure(&self, channel: ReleaseChannel) {
        #[cfg(target_os = "macos")]
        crate::macos::configure_sparkle(SPARKLE_FEED_URL, channel);
        #[cfg(not(target_os = "macos"))]
        let _ = channel;
    }

    fn check(&self, channel: ReleaseChannel) -> Result<UpdateCheck, String> {
        #[cfg(target_os = "macos")]
        if crate::macos::sparkle_available() {
            crate::macos::check_with_sparkle();
            return Ok(UpdateCheck::NativeCheckerOpened);
        }
        let document = self.fetch()?;
        let (mut check, latest) = read_release(&document, channel, self.installed.build)?;
        let update = match (&check, &self.appimage) {
            (UpdateCheck::UpdateAvailable { .. }, Some(_)) => appimage::select_update(
                &latest,
                std::env::consts::ARCH,
                appimage::UPDATE_PUBLIC_KEY,
            ),
            _ => None,
        };
        if let UpdateCheck::UpdateAvailable { installable, .. } = &mut check {
            *installable = update.is_some();
        }
        *self.pending.lock().unwrap_or_else(|e| e.into_inner()) = update;
        Ok(check)
    }

    fn install(&self, progress: &mut dyn FnMut(u64, u64)) -> Result<(), String> {
        let target = self
            .appimage
            .as_ref()
            .ok_or_else(|| "This installation cannot update itself.".to_owned())?;
        let update = self
            .pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .ok_or_else(|| "Check for updates first.".to_owned())?;
        // Connect and idle bounds; a slow but moving download may finish.
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(Duration::from_secs(15))
            .timeout_read(Duration::from_secs(60))
            .build();
        let response = agent.get(&update.url).call().map_err(http_error)?;
        let body = response.into_reader().take(update.size + 1);
        appimage::install_from(body, &update, target, progress)
    }

    fn relaunch(&self) -> Result<(), String> {
        let image = self
            .appimage
            .as_ref()
            .ok_or_else(|| "This installation cannot update itself.".to_owned())?;
        appimage::relaunch(image)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DOCUMENT: &str = r#"{"schemaVersion": 2, "latest": null,
        "beta": {"latest": {"version": "1.0.0-beta.40", "build": 47}}}"#;

    #[test]
    fn reads_the_selected_channel() {
        assert_eq!(
            parse_release_manifest(DOCUMENT, ReleaseChannel::Stable, 1).unwrap(),
            UpdateCheck::NoPublishedRelease
        );
        assert_eq!(
            parse_release_manifest(DOCUMENT, ReleaseChannel::Beta, 45).unwrap(),
            UpdateCheck::UpdateAvailable {
                version: "1.0.0-beta.40".into(),
                build: 47,
                installable: false,
            }
        );
        assert_eq!(
            parse_release_manifest(DOCUMENT, ReleaseChannel::Beta, 47).unwrap(),
            UpdateCheck::UpToDate
        );
        assert!(parse_release_manifest("{}", ReleaseChannel::Beta, 1).is_err());
    }
}
