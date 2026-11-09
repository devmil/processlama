//! Descriptor isolation for a stdio helper.
//!
//! Adapted from GitLama's remote helper (`gitlama/rust-core/remote-helper/src/main.rs`).

/// Moves the protocol to private descriptors. Standard input becomes `/dev/null` and standard
/// output becomes standard error, so no child process or stray `print!` can touch the
/// protocol stream.
///
/// # Errors
/// A descriptor could not be duplicated or `/dev/null` could not be opened.
#[cfg(unix)]
pub fn protocol_streams() -> std::io::Result<(std::fs::File, std::fs::File)> {
    use rustix::fs::{Mode, OFlags};
    let input = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdin(), 3)?;
    let output = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdout(), 3)?;
    let null = rustix::fs::open("/dev/null", OFlags::RDONLY | OFlags::CLOEXEC, Mode::empty())?;
    rustix::stdio::dup2_stdin(&null)?;
    rustix::stdio::dup2_stdout(rustix::stdio::stderr())?;
    Ok((std::fs::File::from(input), std::fs::File::from(output)))
}
