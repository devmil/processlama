use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use libbpf_rs::skel::{OpenSkel, Skel, SkelBuilder};
use libbpf_rs::{MapCore, MapFlags};
use serde::Serialize;

mod network {
    include!(concat!(env!("OUT_DIR"), "/network.skel.rs"));
}
use network::*;

const SNAPSHOT_PATH: &str = "/run/processlama/network.json";
const SNAPSHOT_SCHEMA: u32 = 1;
const SAMPLE_INTERVAL: Duration = Duration::from_millis(500);

#[derive(Debug, Clone, Copy, Default)]
struct ProcessLifetime {
    start_ticks: u64,
}

#[derive(Debug, Serialize)]
struct NetworkSnapshot {
    schema: u32,
    captured_at_unix_ms: u64,
    processes: Vec<ProcessCounters>,
}

#[derive(Debug, Serialize)]
struct ProcessCounters {
    pid: i32,
    bytes_in: u64,
    bytes_out: u64,
}

fn main() -> Result<()> {
    let mut open_object = std::mem::MaybeUninit::uninit();
    let builder = NetworkSkelBuilder::default();
    let open_skeleton = builder
        .open(&mut open_object)
        .context("open eBPF network sampler")?;
    let mut skeleton = open_skeleton.load().context("load eBPF network sampler")?;
    skeleton.attach().context("attach eBPF network probes")?;

    let snapshot_path = Path::new(SNAPSHOT_PATH);
    let mut known_lifetimes = HashMap::<i32, ProcessLifetime>::new();
    loop {
        let tracked_pids = tracked_pids(&skeleton.maps.counters);
        let current_lifetimes = process_lifetimes(&tracked_pids);
        prune_reused_or_terminated_processes(
            &skeleton.maps.counters,
            &known_lifetimes,
            &current_lifetimes,
        );
        known_lifetimes = current_lifetimes;

        let snapshot = snapshot_from_map(&skeleton.maps.counters)?;
        write_snapshot_atomically(snapshot_path, &snapshot)?;
        thread::sleep(SAMPLE_INTERVAL);
    }
}

fn snapshot_from_map<M: MapCore>(map: &M) -> Result<NetworkSnapshot> {
    let mut processes = Vec::new();
    for key in map.keys() {
        if key.len() != 4 {
            continue;
        }
        let pid = u32::from_ne_bytes(key[..4].try_into().expect("key length checked"));
        let Some(value) = map
            .lookup(&key, MapFlags::ANY)
            .context("read network counter map")?
        else {
            continue;
        };
        if value.len() < 16 || pid == 0 || pid > i32::MAX as u32 {
            continue;
        }
        processes.push(ProcessCounters {
            pid: pid as i32,
            bytes_in: u64::from_ne_bytes(value[0..8].try_into().expect("value length checked")),
            bytes_out: u64::from_ne_bytes(value[8..16].try_into().expect("value length checked")),
        });
    }
    processes.sort_by_key(|process| process.pid);
    Ok(NetworkSnapshot {
        schema: SNAPSHOT_SCHEMA,
        captured_at_unix_ms: unix_now_ms(),
        processes,
    })
}

fn tracked_pids<M: MapCore>(map: &M) -> HashSet<i32> {
    map.keys()
        .filter_map(|key| {
            let bytes: [u8; 4] = key.get(..4)?.try_into().ok()?;
            i32::try_from(u32::from_ne_bytes(bytes)).ok()
        })
        .filter(|pid| *pid > 0)
        .collect()
}

fn process_lifetimes(pids: &HashSet<i32>) -> HashMap<i32, ProcessLifetime> {
    let mut lifetimes = HashMap::new();
    for &pid in pids {
        let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) else {
            continue;
        };
        let Some(start_ticks) = process_start_ticks(&stat) else {
            continue;
        };
        lifetimes.insert(pid, ProcessLifetime { start_ticks });
    }
    lifetimes
}

fn process_start_ticks(stat: &str) -> Option<u64> {
    let command_end = stat.rfind(')')?;
    stat[command_end + 1..]
        .split_whitespace()
        .nth(19)?
        .parse()
        .ok()
}

fn prune_reused_or_terminated_processes<M: MapCore>(
    map: &M,
    previous: &HashMap<i32, ProcessLifetime>,
    current: &HashMap<i32, ProcessLifetime>,
) {
    let current_pids = current.keys().copied().collect::<HashSet<_>>();
    for key in map.keys().collect::<Vec<_>>() {
        if key.len() != 4 {
            continue;
        }
        let pid = u32::from_ne_bytes(key[..4].try_into().expect("key length checked"));
        let Ok(pid) = i32::try_from(pid) else {
            let _ = map.delete(&key);
            continue;
        };
        let lifetime_changed = previous
            .get(&pid)
            .zip(current.get(&pid))
            .is_some_and(|(old, new)| old.start_ticks != new.start_ticks);
        if !current_pids.contains(&pid) || lifetime_changed {
            let _ = map.delete(&key);
        }
    }
}

fn write_snapshot_atomically(path: &Path, snapshot: &NetworkSnapshot) -> Result<()> {
    let parent = path.parent().context("network snapshot has no parent")?;
    fs::create_dir_all(parent).context("create network snapshot directory")?;
    let temporary = temporary_path(path);
    let bytes = serde_json::to_vec(snapshot).context("serialize network snapshot")?;
    fs::write(&temporary, bytes).context("write network snapshot")?;
    fs::rename(&temporary, path).context("publish network snapshot")?;
    Ok(())
}

fn temporary_path(path: &Path) -> PathBuf {
    let Some(file_name) = path.file_name() else {
        return path.with_extension("tmp");
    };
    path.with_file_name(format!(".{}.tmp", file_name.to_string_lossy()))
}

fn unix_now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_proc_stat_start_ticks_after_parenthesized_name() {
        let stat = "42 (name with spaces) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 12345";
        assert_eq!(process_start_ticks(stat), Some(12345));
    }

    #[test]
    fn snapshot_path_matches_shared_fixture() {
        let fixture = include_str!("../../../fixtures/linux_network_snapshot_path.txt");
        assert_eq!(fixture.trim(), SNAPSHOT_PATH);
    }

    #[test]
    fn temporary_snapshot_stays_in_runtime_directory() {
        assert_eq!(
            temporary_path(Path::new(SNAPSHOT_PATH)),
            Path::new("/run/processlama/.network.json.tmp")
        );
    }
}
