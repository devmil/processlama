//! Product payloads of the remote helper protocol and their strict validation.
//!
//! Objects carry exactly their declared keys; absent optional values are `null`. The Dart
//! client validates the same shapes; both sides test against
//! `fixtures/remote_contract_vectors.json`.
use crate::contract::{NetworkReason, NetworkSource, Target};
use serde_json::{Map, Value, json};

/// A payload did not match its declared shape.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InvalidMessage(pub &'static str);

pub type Result<T> = std::result::Result<T, InvalidMessage>;

/// The object in `value` when it has exactly `keys`.
pub fn object<'a>(
    value: &'a Value,
    keys: &[&str],
    what: &'static str,
) -> Result<&'a Map<String, Value>> {
    let map = value.as_object().ok_or(InvalidMessage(what))?;
    if map.len() != keys.len() || !keys.iter().all(|key| map.contains_key(*key)) {
        return Err(InvalidMessage(what));
    }
    Ok(map)
}

pub fn string<'a>(
    map: &'a Map<String, Value>,
    key: &str,
    max: usize,
    what: &'static str,
) -> Result<&'a str> {
    match map.get(key) {
        Some(Value::String(text)) if text.len() <= max && !text.chars().any(char::is_control) => {
            Ok(text)
        }
        _ => Err(InvalidMessage(what)),
    }
}

pub fn boolean(map: &Map<String, Value>, key: &str, what: &'static str) -> Result<bool> {
    map.get(key)
        .and_then(Value::as_bool)
        .ok_or(InvalidMessage(what))
}

pub fn unsigned(map: &Map<String, Value>, key: &str, what: &'static str) -> Result<u64> {
    map.get(key)
        .and_then(Value::as_u64)
        .filter(|value| *value <= (1 << 53))
        .ok_or(InvalidMessage(what))
}

fn hex(text: &str, length: usize) -> bool {
    text.len() == length
        && text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// Network rate availability on the host.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NetworkCapability {
    pub source: NetworkSource,
    pub reason: Option<NetworkReason>,
}

/// What the helper can show; the client never derives this from its own platform.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Capabilities {
    pub gpu: bool,
    pub storage_io: bool,
    pub network: NetworkCapability,
    pub signals: bool,
    pub inspector_files: bool,
    pub inspector_sockets: bool,
    pub inspector_threads: bool,
    pub inspector_security: bool,
    pub icons: bool,
    pub hidepid: bool,
}

/// The product part of the helper's hello.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HelloBody {
    pub target: Target,
    /// Kernel release, at most 128 bytes.
    pub kernel: String,
    /// 32 hex digits derived from the host's machine identity; never the identity itself.
    pub host_instance_id: String,
    /// 16 hex digits of the hostname's SHA-256; the hostname never crosses the wire.
    pub hostname_hash: String,
    pub processtree_revision: String,
    pub compatibility: u64,
    pub uid: u64,
    pub capabilities: Capabilities,
}

impl HelloBody {
    pub fn to_value(&self) -> Value {
        let capabilities = &self.capabilities;
        json!({
            "os": self.target.os(),
            "arch": self.target.arch(),
            "target": self.target.as_str(),
            "kernel": self.kernel,
            "hostInstanceId": self.host_instance_id,
            "hostnameHash": self.hostname_hash,
            "processtreeRevision": self.processtree_revision,
            "compatibility": self.compatibility,
            "account": {"uid": self.uid},
            "capabilities": {
                "gpu": capabilities.gpu,
                "storageIo": capabilities.storage_io,
                "network": {
                    "source": capabilities.network.source.as_str(),
                    "reason": capabilities.network.reason.map(NetworkReason::as_str),
                },
                "signals": capabilities.signals,
                "inspector": {
                    "files": capabilities.inspector_files,
                    "sockets": capabilities.inspector_sockets,
                    "threads": capabilities.inspector_threads,
                    "security": capabilities.inspector_security,
                },
                "icons": capabilities.icons,
                "hidepid": capabilities.hidepid,
            },
            "bounds": {
                "iconBytes": crate::contract::ICON_BYTES,
                "iconsPerFetch": crate::contract::ICONS_PER_FETCH,
                "iconFetchBytes": crate::contract::ICON_FETCH_BYTES,
                "processesPerSample": crate::contract::PROCESSES_PER_SAMPLE,
            },
        })
    }

    /// Validates a hello body.
    ///
    /// # Errors
    /// The value does not have the declared shape.
    pub fn parse(value: &Value) -> Result<Self> {
        let map = object(
            value,
            &[
                "os",
                "arch",
                "target",
                "kernel",
                "hostInstanceId",
                "hostnameHash",
                "processtreeRevision",
                "compatibility",
                "account",
                "capabilities",
                "bounds",
            ],
            "hello",
        )?;
        let target =
            Target::parse(string(map, "target", 32, "target")?).ok_or(InvalidMessage("target"))?;
        if string(map, "os", 16, "os")? != target.os()
            || string(map, "arch", 16, "arch")? != target.arch()
        {
            return Err(InvalidMessage("target"));
        }
        let host_instance_id = string(map, "hostInstanceId", 32, "hostInstanceId")?;
        let hostname_hash = string(map, "hostnameHash", 16, "hostnameHash")?;
        let revision = string(map, "processtreeRevision", 40, "processtreeRevision")?;
        if !hex(host_instance_id, 32)
            || !hex(hostname_hash, 16)
            || !revision.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(InvalidMessage("identity"));
        }
        let account = object(
            map.get("account").unwrap_or(&Value::Null),
            &["uid"],
            "account",
        )?;
        let capabilities = map.get("capabilities").unwrap_or(&Value::Null);
        let caps = object(
            capabilities,
            &[
                "gpu",
                "storageIo",
                "network",
                "signals",
                "inspector",
                "icons",
                "hidepid",
            ],
            "capabilities",
        )?;
        let network = object(
            caps.get("network").unwrap_or(&Value::Null),
            &["source", "reason"],
            "network",
        )?;
        let source = NetworkSource::parse(string(network, "source", 16, "network")?)
            .ok_or(InvalidMessage("network"))?;
        let reason = match network.get("reason") {
            Some(Value::Null) => None,
            Some(Value::String(reason)) => {
                Some(NetworkReason::parse(reason).ok_or(InvalidMessage("network"))?)
            }
            _ => return Err(InvalidMessage("network")),
        };
        let inspector = object(
            caps.get("inspector").unwrap_or(&Value::Null),
            &["files", "sockets", "threads", "security"],
            "inspector",
        )?;
        let bounds = object(
            map.get("bounds").unwrap_or(&Value::Null),
            &[
                "iconBytes",
                "iconsPerFetch",
                "iconFetchBytes",
                "processesPerSample",
            ],
            "bounds",
        )?;
        for key in [
            "iconBytes",
            "iconsPerFetch",
            "iconFetchBytes",
            "processesPerSample",
        ] {
            if unsigned(bounds, key, "bounds")? == 0 {
                return Err(InvalidMessage("bounds"));
            }
        }
        Ok(Self {
            target,
            kernel: string(map, "kernel", 128, "kernel")?.to_owned(),
            host_instance_id: host_instance_id.to_owned(),
            hostname_hash: hostname_hash.to_owned(),
            processtree_revision: revision.to_owned(),
            compatibility: unsigned(map, "compatibility", "compatibility")?,
            uid: unsigned(account, "uid", "account")?,
            capabilities: Capabilities {
                gpu: boolean(caps, "gpu", "capabilities")?,
                storage_io: boolean(caps, "storageIo", "capabilities")?,
                network: NetworkCapability { source, reason },
                signals: boolean(caps, "signals", "capabilities")?,
                inspector_files: boolean(inspector, "files", "inspector")?,
                inspector_sockets: boolean(inspector, "sockets", "inspector")?,
                inspector_threads: boolean(inspector, "threads", "inspector")?,
                inspector_security: boolean(inspector, "security", "inspector")?,
                icons: boolean(caps, "icons", "capabilities")?,
                hidepid: boolean(caps, "hidepid", "capabilities")?,
            },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vectors() -> Vec<Value> {
        let text = include_str!("../../../fixtures/remote_contract_vectors.json");
        let document: Value = serde_json::from_str(text).unwrap();
        document["vectors"].as_array().unwrap().clone()
    }

    #[test]
    fn contract_vectors_are_accepted_or_rejected_as_declared() {
        let mut checked = 0;
        for vector in vectors() {
            let name = vector["name"].as_str().unwrap();
            let valid = vector["valid"].as_bool().unwrap();
            let result = match vector["type"].as_str().unwrap() {
                "helloBody" => HelloBody::parse(&vector["value"]).map(|body| {
                    // Valid bodies round-trip exactly.
                    assert_eq!(body.to_value(), vector["value"], "{name}");
                }),
                _ => continue,
            };
            assert_eq!(result.is_ok(), valid, "{name}");
            checked += 1;
        }
        assert!(checked >= 4);
    }
}
