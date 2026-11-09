//! Writes stray text before and after isolating the protocol descriptors, then one frame.
fn main() {
    #[cfg(unix)]
    {
        let (_input, mut output) = devmil_remote::streams::protocol_streams().unwrap();
        println!("stray stdout after isolation");
        let _ = std::process::Command::new("echo")
            .arg("child output")
            .status();
        devmil_remote::frame::write_frame(&mut output, b"{\"ok\":true}").unwrap();
    }
}
