#![cfg(unix)]

#[test]
fn protocol_stdout_carries_only_frames() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_devmil-remote-isolation-probe"))
        .output()
        .unwrap();
    assert!(output.status.success());
    let mut expected = 11_u32.to_be_bytes().to_vec();
    expected.extend_from_slice(b"{\"ok\":true}");
    assert_eq!(output.stdout, expected);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("stray stdout after isolation"));
    assert!(stderr.contains("child output"));
}
