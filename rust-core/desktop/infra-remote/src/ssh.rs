//! The system OpenSSH client: discovery, the version floor and fixed arguments.

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

pub const MINIMUM_OPENSSH: (u32, u32) = (8, 9);
const VERSION_PROBE_TIMEOUT: Duration = Duration::from_secs(5);

/// Options every connection uses; the alias's `~/.ssh/config` supplies the rest.
pub const FIXED_ARGUMENTS: &[&str] = &[
    "-T",
    "-o", "RequestTTY=no",
    "-o", "StdinNull=no",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=yes",
    "-o", "ForwardAgent=no",
    "-o", "ForwardX11=no",
    "-o", "ClearAllForwardings=yes",
    "-o", "GSSAPIDelegateCredentials=no",
    "-o", "ControlMaster=no",
    "-o", "ControlPath=none",
    "-o", "ForkAfterAuthentication=no",
    "-o", "RemoteCommand=none",
    "-o", "SessionType=default",
    "-o", "PermitLocalCommand=no",
    "-o", "ConnectTimeout=10",
    "-o", "ConnectionAttempts=1",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=3",
];

/// The account's login shell may be zsh or fish; scripts are POSIX sh.
pub fn posix_shell_command(script: &str) -> String {
    format!("exec /bin/sh -c '{}'", script.replace('\'', "'\\''"))
}

/// The full argument list, or None for an alias that is not a plain host alias.
pub fn arguments(alias: &str, remote_command: &str, config_file: Option<&str>) -> Option<Vec<String>> {
    if !processlama_domain::is_valid_alias(alias) {
        return None;
    }
    let mut arguments = Vec::with_capacity(FIXED_ARGUMENTS.len() + 5);
    if let Some(config) = config_file {
        arguments.push("-F".to_owned());
        arguments.push(config.to_owned());
    }
    arguments.extend(FIXED_ARGUMENTS.iter().map(|argument| (*argument).to_owned()));
    arguments.push("--".to_owned());
    arguments.push(alias.to_owned());
    arguments.push(remote_command.to_owned());
    Some(arguments)
}

/// `OpenSSH_9.6p1` or `OpenSSH_for_Windows_8.9`.
pub fn parse_version(text: &str) -> Option<(u32, u32)> {
    let start = text.find("OpenSSH_")? + "OpenSSH_".len();
    let rest = text[start..].strip_prefix("for_Windows_").unwrap_or(&text[start..]);
    let mut parts = rest.splitn(2, '.');
    let major: String = parts.next()?.chars().take_while(char::is_ascii_digit).collect();
    let minor: String = parts.next()?.chars().take_while(char::is_ascii_digit).collect();
    if major.is_empty() || minor.is_empty() || major.len() > 4 || minor.len() > 4 {
        return None;
    }
    Some((major.parse().ok()?, minor.parse().ok()?))
}

pub fn is_supported(text: &str) -> bool {
    parse_version(text).is_some_and(|version| version >= MINIMUM_OPENSSH)
}

/// `/usr/bin/ssh`, then absolute `PATH` entries other than the working directory.
pub fn resolve_executable() -> Option<PathBuf> {
    let current = std::env::current_dir().ok();
    let mut candidates: Vec<PathBuf> = Vec::new();
    if cfg!(windows) {
        if let Some(root) = std::env::var_os("SystemRoot") {
            candidates.push(Path::new(&root).join("System32").join("OpenSSH").join("ssh.exe"));
        }
        if let Some(path) = std::env::var_os("PATH") {
            for entry in std::env::split_paths(&path) {
                if entry.is_absolute() && current.as_deref() != Some(entry.as_path()) {
                    candidates.push(entry.join("ssh.exe"));
                }
            }
        }
    } else {
        candidates.push(PathBuf::from("/usr/bin/ssh"));
        if let Some(path) = std::env::var_os("PATH") {
            for entry in std::env::split_paths(&path) {
                if entry.is_absolute() && current.as_deref() != Some(entry.as_path()) {
                    candidates.push(entry.join("ssh"));
                }
            }
        }
    }
    candidates.into_iter().find(|candidate| candidate.is_file())
}

/// `ssh -V` output (stderr), or None when the probe failed.
pub fn read_version(executable: &Path) -> Option<String> {
    let mut child = Command::new(executable)
        .arg("-V")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;
    let deadline = Instant::now() + VERSION_PROBE_TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
    let mut text = String::new();
    use std::io::Read;
    child.stderr.take()?.take(4096).read_to_string(&mut text).ok()?;
    Some(text)
}

/// Starts `ssh` in its own process group so its descendants end with it.
pub fn spawn(executable: &Path, arguments: &[String]) -> std::io::Result<Child> {
    let mut command = Command::new(executable);
    command
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // CREATE_NO_WINDOW
        command.creation_flags(0x0800_0000);
    }
    command.spawn()
}

/// Terminates the child's process group: TERM, then KILL after `grace`.
pub fn terminate(child: &mut Child, grace: Duration) {
    if matches!(child.try_wait(), Ok(Some(_))) {
        return;
    }
    #[cfg(unix)]
    {
        if let Some(pid) = rustix::process::Pid::from_raw(child.id() as i32) {
            let _ = rustix::process::kill_process_group(pid, rustix::process::Signal::TERM);
            let deadline = Instant::now() + grace;
            while Instant::now() < deadline {
                if matches!(child.try_wait(), Ok(Some(_))) {
                    return;
                }
                std::thread::sleep(Duration::from_millis(25));
            }
            let _ = rustix::process::kill_process_group(pid, rustix::process::Signal::KILL);
        }
    }
    #[cfg(not(unix))]
    {
        let _ = grace;
    }
    let _ = child.kill();
    let _ = child.wait();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_openssh_versions() {
        assert_eq!(parse_version("OpenSSH_9.6p1 Ubuntu-3ubuntu13, OpenSSL 3.0.13"), Some((9, 6)));
        assert_eq!(parse_version("OpenSSH_for_Windows_8.9p1, LibreSSL 3.4.3"), Some((8, 9)));
        assert!(is_supported("OpenSSH_8.9p1"));
        assert!(!is_supported("OpenSSH_8.8p1"));
        assert!(!is_supported("Dropbear v2022.83"));
    }

    #[test]
    fn quotes_scripts_for_sh() {
        assert_eq!(posix_shell_command("printf 'a'"), "exec /bin/sh -c 'printf '\\''a'\\'''");
    }

    #[test]
    fn rejects_unsafe_aliases() {
        assert!(arguments("-oProxyCommand=x", "true", None).is_none());
        let arguments = arguments("build-box", "true", None).unwrap();
        assert_eq!(&arguments[arguments.len() - 3..], ["--", "build-box", "true"]);
    }
}
