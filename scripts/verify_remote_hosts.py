#!/usr/bin/env python3
"""Remote hosts verification lanes (docs/10_remote_hosts.md §12.3).

  --protocol      Dart and Rust contract and protocol tests
  --helper        the real helper over a local pipe through the launch script, no SSH
  --ssh-loopback  real OpenSSH to a user-mode sshd with an isolated remote home: probe,
                  install, connect, disconnect, reconnect, prune and uninstall
  --containers    Podman sshd hosts (Ubuntu 22.04, x86_64 and arm64 under qemu) and hostile
                  variants: login text, a login script reading stdin, a noexec home,
                  hidepid=2, and an eBPF network snapshot
  --mac           the same flow against $PROCESSLAMA_TEST_MAC_HOST (user@host), cleaned up
  --performance   payload sizes and helper CPU with about 1,000 processes in a container
  --disconnect-matrix
                  kills ssh, kills the helper, stalls its stdout (SIGSTOP), cuts the
                  container's network (tc netem loss 100%) and removes the helper while
                  disconnected; checks phases, staleness and reconnect
  --ui            integration_test/remote_hosts_test.dart in the real Linux app against a
                  container, with screenshots into docs/remote_hosts_evidence/screenshots
  --soak          streams a container with process churn for $PROCESSLAMA_SOAK_MINUTES
                  (default 120); after warm-up the helper's RSS stays within 10 %, and the
                  helper's RSS and the app's post-GC Dart heap grow under 1 MiB per hour

Lanes run in the order given. Each prints one result line; the script exits non-zero when
any lane fails.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUST = ROOT / "rust-core"


def run(command: list[str], *, cwd: Path = ROOT, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, env=env, check=True)


def helper_binary(profile: str = "debug") -> Path:
    arguments = ["cargo", "build", "--locked", "-p", "processlama-remote-helper"]
    if profile == "release":
        arguments.append("--release")
    run(arguments, cwd=RUST)
    target = Path(os.environ.get("CARGO_TARGET_DIR", RUST / "target"))
    if not target.is_absolute():
        target = RUST / target
    return target / profile / "processlama-remote-helper"


def native_library() -> Path:
    """The debug bridge library the lanes load into flutter test."""
    run(["cargo", "build", "--locked", "-p", "processlama_core"], cwd=RUST)
    target = Path(os.environ.get("CARGO_TARGET_DIR", RUST / "target"))
    if not target.is_absolute():
        target = RUST / target
    name = "libprocesslama_core.dylib" if sys.platform == "darwin" else "libprocesslama_core.so"
    return target / "debug" / name


def packaged_host_helper(directory: Path) -> Path:
    """The host's development helper, packaged with its descriptor in directory."""
    helper = helper_binary()
    machine = os.uname().machine
    os_name = "macos" if sys.platform == "darwin" else "linux"
    arch = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}[machine]
    run([
        "python3", "scripts/package_remote_helper.py", "package",
        "--target", f"{os_name}-{arch}", "--binary", str(helper),
        "--output", str(directory), "--no-archive", "--development",
    ])
    return directory


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class LoopbackSshd:
    """A user-mode sshd on 127.0.0.1 with throwaway keys and an isolated remote home.

    Adapted from GitLama's scripts/verify_remote_workspaces.py fixture.
    """

    def __init__(self) -> None:
        self.sshd = shutil.which("sshd") or "/usr/sbin/sshd"
        for tool in ("ssh", "ssh-keygen"):
            if shutil.which(tool) is None:
                raise RuntimeError(f"{tool} is not installed")
        if not Path(self.sshd).exists():
            raise RuntimeError("sshd is not installed")
        self.root = Path(tempfile.mkdtemp(prefix="processlama-remote-ssh-"))
        self.home = self.root / "home"
        self.home.mkdir()
        self.port = free_port()
        self.process: subprocess.Popen[bytes] | None = None
        self.unit: str | None = None

    def __enter__(self) -> "LoopbackSshd":
        try:
            self._start()
        except BaseException:
            self.close()
            raise
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _start(self) -> None:
        keys = self.root / "keys"
        keys.mkdir(mode=0o700)
        for name in ("host", "client"):
            subprocess.run(
                ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(keys / name)],
                check=True,
            )
        (keys / "authorized_keys").write_bytes((keys / "client.pub").read_bytes())
        host_key = (keys / "host.pub").read_text(encoding="utf-8").split()[:2]
        known_hosts = self.root / "known_hosts"
        known_hosts.write_text(f"[127.0.0.1]:{self.port} {' '.join(host_key)}\n", encoding="utf-8")
        untrusted = self.root / "untrusted_known_hosts"
        untrusted.write_text("", encoding="utf-8")
        config = self.root / "sshd_config"
        config.write_text(
            "\n".join(
                [
                    f"Port {self.port}",
                    "ListenAddress 127.0.0.1",
                    f"HostKey {keys / 'host'}",
                    f"PidFile {self.root / 'sshd.pid'}",
                    f"AuthorizedKeysFile {keys / 'authorized_keys'}",
                    "PasswordAuthentication no",
                    "KbdInteractiveAuthentication no",
                    "PubkeyAuthentication yes",
                    "PermitRootLogin no",
                    "UsePAM no",
                    "StrictModes no",
                    "AllowAgentForwarding no",
                    "AllowTcpForwarding no",
                    "X11Forwarding no",
                    "PermitUserEnvironment no",
                    f"SetEnv HOME={self.home}",
                    "LogLevel VERBOSE",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        self.ssh_config = self.root / "ssh_config"
        user = os.environ.get("USER") or os.getlogin()
        entries = []
        for alias, hosts in (("processlama-loopback", known_hosts), ("processlama-untrusted", untrusted)):
            entries += [
                f"Host {alias}",
                "  HostName 127.0.0.1",
                f"  Port {self.port}",
                f"  User {user}",
                f"  IdentityFile {keys / 'client'}",
                "  IdentitiesOnly yes",
                "  IdentityAgent none",
                f"  UserKnownHostsFile {hosts}",
                "  GlobalKnownHostsFile /dev/null",
                "  UpdateHostKeys no",
                "",
            ]
        self.ssh_config.write_text("\n".join(entries), encoding="utf-8")
        # Kept for diagnose(): sshd -e logs to stderr.
        self.log = self.root / "sshd.log"
        command = [self.sshd, "-D", "-e", "-f", str(config)]
        self.unit = self._user_unit()
        if self.unit is not None:
            command = ["systemd-run", "--user", "--quiet", "--pipe", "--collect",
                       f"--unit={self.unit}", *command]
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=self.log.open("wb"),
        )
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", self.port)) == 0:
                    return
            if self.process.poll() is not None:
                raise RuntimeError("the loopback sshd did not start")
            time.sleep(0.05)
        raise RuntimeError("the loopback sshd did not listen")

    def diagnose(self) -> None:
        """Prints what a plain remote command sees and the sshd log, for a failed lane."""
        probe = subprocess.run(
            ["ssh", "-F", str(self.ssh_config), "-o", "BatchMode=yes", "processlama-loopback",
             "exec /bin/sh -c 'echo shell=$0 home=$HOME user=$(id -un); uname -s; uname -m; "
             "ls -ld \"$HOME\"; command -v sh uname mkdir'"],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30,
        )
        print(f"loopback probe exit={probe.returncode}", flush=True)
        print("loopback probe stdout:\n" + probe.stdout, flush=True)
        print("loopback probe stderr:\n" + probe.stderr[-2000:], flush=True)
        if self.log.exists():
            print("sshd log (tail):\n" + self.log.read_text(errors="replace")[-6000:], flush=True)

    def _user_unit(self) -> str | None:
        """A user-manager unit name when sshd must not inherit a system service's context.

        Fedora's sshd-session sets the login's default SELinux context for the session
        shell even when it runs unprivileged. From a system service such as the CI
        runner (system_u:system_r:unconfined_service_t) that transition is refused and
        every remote command fails with "Permission denied". The user's systemd manager
        runs in the login context, so sshd starts there instead.
        """
        try:
            context = Path("/proc/self/attr/current").read_text(encoding="utf-8")
        except OSError:
            return None
        if ":system_r:" not in context or shutil.which("systemd-run") is None:
            return None
        runtime = Path(f"/run/user/{os.getuid()}")
        if not os.environ.get("XDG_RUNTIME_DIR") and runtime.is_dir():
            os.environ["XDG_RUNTIME_DIR"] = str(runtime)
        return f"processlama-loopback-sshd-{self.port}"

    def close(self) -> None:
        if self.unit is not None:
            subprocess.run(["systemctl", "--user", "stop", self.unit],
                           stdin=subprocess.DEVNULL, capture_output=True, check=False)
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        shutil.rmtree(self.root, ignore_errors=True)


def lane_ssh_loopback() -> None:
    library = native_library()
    with tempfile.TemporaryDirectory(prefix="processlama-loopback-helper-") as helpers:
        packaged_host_helper(Path(helpers))
        with LoopbackSshd() as sshd:
            env = dict(
                os.environ,
                PROCESSLAMA_NATIVE_LIBRARY=str(library),
                PROCESSLAMA_SSH_CONFIG=str(sshd.ssh_config),
                PROCESSLAMA_TEST_ALIAS="processlama-loopback",
                PROCESSLAMA_TEST_UNTRUSTED_ALIAS="processlama-untrusted",
                PROCESSLAMA_TEST_REMOTE_HOME=str(sshd.home),
                PROCESSLAMA_REMOTE_HELPER_DIR=helpers,
            )
            try:
                run(["flutter", "test", "test_remote/ssh_loopback_test.dart"], env=env)
            except subprocess.CalledProcessError:
                sshd.diagnose()
                raise
            leftovers = sshd.home / ".local" / "lib" / "processlama"
            if leftovers.exists():
                raise subprocess.CalledProcessError(1, ["leftover helper in the loopback home"])


CONTAINER_VARIANTS = [
    ("base", "amd64"),
    ("base", "arm64"),
    ("login-noise", "amd64"),
    ("login-stdin", "amd64"),
    ("noexec", "amd64"),
    ("hidepid", "amd64"),
    ("ebpf", "amd64"),
    ("zsh", "amd64"),
]
PRIVILEGED_VARIANTS = {"noexec", "hidepid"}
NETWORK_ADMIN_VARIANTS = {"icons", "disconnect"}


def podman(*arguments: str, capture: bool = False) -> str:
    result = subprocess.run(
        ["podman", *arguments],
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout if capture else ""


def release_linux_helpers() -> Path:
    """The glibc 2.35 Linux helpers of this tree, (re)built in the zigbuild container.

    PROCESSLAMA_REMOTE_HELPER_DIR selects prebuilt helpers (CI artifacts) instead.
    """
    prebuilt = os.environ.get("PROCESSLAMA_REMOTE_HELPER_DIR")
    if prebuilt:
        return Path(prebuilt)
    run(["./scripts/build-remote-helpers-linux.sh"])
    return ROOT / "build" / "remote-helper"


class TestHostContainers:
    """One sshd container per variant, reachable on 127.0.0.1 through an ssh config."""

    def __init__(self, variants: list[tuple[str, str]]) -> None:
        self.variants = variants
        self.root = Path(tempfile.mkdtemp(prefix="processlama-remote-containers-"))
        self.containers: list[tuple[str, str, str, str]] = []

    def __enter__(self) -> "TestHostContainers":
        try:
            self._start()
        except BaseException:
            self.close()
            raise
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def _image(self, arch: str) -> str:
        recipe = ROOT / "packaging" / "remote-hosts-test"
        digest = subprocess.run(
            ["sha256sum", str(recipe / "Containerfile"), str(recipe / "entrypoint.sh")],
            capture_output=True, text=True, check=True,
        ).stdout
        tag = f"localhost/processlama-remote-hosts-test:{arch}-" + hashlib.sha256(digest.encode()).hexdigest()[:12]
        if subprocess.run(["podman", "image", "exists", tag]).returncode != 0:
            podman("build", "--arch", arch, "--network=host", "-t", tag, str(recipe))
        return tag

    def _start(self) -> None:
        keys = self.root / "keys"
        keys.mkdir(mode=0o700)
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(keys / "client")], check=True)
        authorized = keys / "authorized_keys"
        authorized.write_bytes((keys / "client.pub").read_bytes())
        authorized.chmod(0o644)
        known_hosts = self.root / "known_hosts"
        entries = []
        hosts = []
        for variant, arch in self.variants:
            image = self._image(arch)
            port = free_port()
            name = f"processlama-remote-test-{variant}-{arch}-{os.getpid()}"
            arguments = [
                "run", "--detach", "--rm", "--name", name, "--arch", arch,
                "-p", f"127.0.0.1:{port}:22",
                "-v", f"{authorized}:/etc/ssh/keys/authorized_keys:ro,z",
                "-e", f"VARIANT={variant}",
            ]
            if variant in PRIVILEGED_VARIANTS:
                arguments += ["--cap-add", "SYS_ADMIN"]
            if variant in NETWORK_ADMIN_VARIANTS:
                arguments += ["--cap-add", "NET_ADMIN"]
            podman(*arguments, image)
            host_key = podman("exec", name, "cat", "/etc/ssh/ssh_host_ed25519_key.pub", capture=True).split()[:2]
            with known_hosts.open("a", encoding="utf-8") as stream:
                stream.write(f"[127.0.0.1]:{port} {' '.join(host_key)}\n")
            alias = f"processlama-{variant}-{arch}"
            self.containers.append((name, alias, variant, arch))
            hosts.append({
                "alias": alias,
                "variant": variant,
                "arch": "arm64" if arch == "arm64" else "x86_64",
                "container": name,
            })
            entries += [
                f"Host {alias}",
                "  HostName 127.0.0.1",
                f"  Port {port}",
                "  User tester",
                f"  IdentityFile {keys / 'client'}",
                "  IdentitiesOnly yes",
                "  IdentityAgent none",
                f"  UserKnownHostsFile {known_hosts}",
                "  GlobalKnownHostsFile /dev/null",
                "  UpdateHostKeys no",
                "",
            ]
        self.ssh_config = self.root / "ssh_config"
        self.ssh_config.write_text("\n".join(entries), encoding="utf-8")
        self.hosts = hosts
        for name, alias, _, _ in self.containers:
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                probe = subprocess.run(
                    ["ssh", "-F", str(self.ssh_config), "-o", "BatchMode=yes", alias, "true"],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                if probe.returncode in (0, 1):
                    break
                time.sleep(1)
            else:
                raise RuntimeError(f"{name} did not accept SSH")

    def leftovers(self) -> list[str]:
        found = []
        for name, _, _, _ in self.containers:
            listing = subprocess.run(
                ["podman", "exec", name, "sh", "-c",
                 "ls -A /home/tester/.local/lib/processlama 2>/dev/null; ls -A /home/tester/.cache/processlama 2>/dev/null"],
                capture_output=True, text=True,
            ).stdout.strip()
            if listing:
                found.append(f"{name}: {listing}")
        return found

    def close(self) -> None:
        for name, _, _, _ in self.containers:
            subprocess.run(["podman", "rm", "--force", "--time", "2", name],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(self.root, ignore_errors=True)


def lane_containers() -> None:
    library = native_library()
    helpers = release_linux_helpers()
    with TestHostContainers(CONTAINER_VARIANTS) as containers:
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_CONTAINERS=json.dumps(containers.hosts),
        )
        run(["flutter", "test", "test_remote/containers_test.dart"], env=env)
        leftovers = containers.leftovers()
        if leftovers:
            print("helpers left behind: " + "; ".join(leftovers), flush=True)
            raise subprocess.CalledProcessError(1, ["leftover helpers"])
        print("cleanup confirmed: no ~/.local/lib/processlama in any container", flush=True)


def mac_ssh_config(directory: Path) -> tuple[Path, str, str]:
    """An ssh config naming the macOS test host with a plain alias."""
    destination = os.environ.get("PROCESSLAMA_TEST_MAC_HOST", "")
    user, _, host = destination.rpartition("@")
    if not host:
        raise RuntimeError("set PROCESSLAMA_TEST_MAC_HOST to user@host")
    config = directory / "ssh_config"
    lines = ["Host processlama-mac", f"  HostName {host}"]
    if user:
        lines.append(f"  User {user}")
    config.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return config, "processlama-mac", destination


def lane_mac() -> None:
    library = native_library()
    helpers = Path(os.environ.get("PROCESSLAMA_REMOTE_HELPER_DIR") or ROOT / "build" / "remote-helper")
    for target in ("macos-arm64", "macos-x86_64"):
        if not (helpers / target / "processlama-remote-helper.json").is_file():
            raise RuntimeError(f"no {target} helper in {helpers}; build it with scripts/build-remote-helpers-macos.sh")
    with tempfile.TemporaryDirectory(prefix="processlama-mac-lane-") as scratch:
        config, alias, destination = mac_ssh_config(Path(scratch))
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(config),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
        )
        try:
            result = subprocess.run(
                ["flutter", "test", "test_remote/mac_test.dart"],
                cwd=ROOT, env=env, capture_output=True, text=True,
            )
            sys.stdout.write(result.stdout[-4000:])
            for line in result.stdout.splitlines():
                if "MAC_RESTRICTED_SECTIONS" in line:
                    print(line.strip(), flush=True)
            if result.returncode != 0:
                sys.stdout.write(result.stderr[-4000:])
                raise subprocess.CalledProcessError(result.returncode, ["flutter", "test"])
        finally:
            listing = subprocess.run(
                ["ssh", "-o", "BatchMode=yes", destination,
                 "ls -A ~/.local/lib/processlama ~/.cache/processlama 2>/dev/null"],
                capture_output=True, text=True,
            ).stdout.strip()
            if listing:
                print(f"helpers left on the macOS host: {listing}", flush=True)
                raise subprocess.CalledProcessError(1, ["leftover helpers"])
            print("cleanup confirmed: no ~/.local/lib/processlama on the macOS host", flush=True)


def run_reporting(command: list[str], env: dict[str, str], marker: str) -> list[str]:
    """Runs a test, prints its tail, and returns the lines carrying marker."""
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    sys.stdout.write(result.stdout[-3000:])
    lines = [line.strip() for line in result.stdout.splitlines() if marker in line]
    for line in dict.fromkeys(lines):
        print(line, flush=True)
    if result.returncode != 0:
        sys.stdout.write(result.stderr[-3000:])
        raise subprocess.CalledProcessError(result.returncode, command)
    return lines


def _png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """An opaque RGB PNG, written with the standard library."""
    import struct
    import zlib

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    row = b"\x00" + bytes(rgb) * width
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(row * height))
        + chunk(b"IEND", b"")
    )


def icon_fixture(directory: Path, count: int = 80) -> None:
    """count applications: a copied sleep binary, a .desktop entry and a PNG or SVG icon."""
    (directory / "bin").mkdir(parents=True)
    (directory / "icons").mkdir()
    applications = directory / ".local" / "share" / "applications"
    applications.mkdir(parents=True)
    for index in range(count):
        name = f"app{index:02d}"
        color = (40 + index * 2 % 200, 200 - index * 2 % 180, (index * 37) % 255)
        if index % 2:
            icon = directory / "icons" / f"{name}.svg"
            icon.write_text(
                '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
                f'<circle cx="32" cy="32" r="28" fill="#{color[0]:02x}{color[1]:02x}{color[2]:02x}"/>'
                f'<text x="16" y="40" font-size="20">{index}</text></svg>',
                encoding="utf-8",
            )
        else:
            size = (32, 48, 64, 128, 256)[index % 5]
            icon = directory / "icons" / f"{name}.png"
            icon.write_bytes(_png(size, size, color))
        (applications / f"{name}.desktop").write_text(
            "[Desktop Entry]\nType=Application\n"
            f"Name=Fixture App {index}\nExec=/home/tester/bin/{name}\n"
            f"Icon=/home/tester/icons/{icon.name}\n",
            encoding="utf-8",
        )


def lane_performance() -> None:
    library = native_library()
    helpers = release_linux_helpers()
    with TestHostContainers([("base", "amd64")]) as containers:
        name, alias, _, _ = containers.containers[0]
        podman("exec", "--user", "tester", "--detach", name, "sh", "-c",
               "for i in $(seq 1 1000); do sleep 3600 & done; wait")
        time.sleep(3)
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_TEST_CONTAINER=name,
        )
        run_reporting(["flutter", "test", "test_remote/performance_test.dart"], env, "PERFORMANCE")
        if containers.leftovers():
            raise subprocess.CalledProcessError(1, ["leftover helpers"])
    with TestHostContainers([("icons", "amd64")]) as containers, tempfile.TemporaryDirectory(
        prefix="processlama-icon-fixture-"
    ) as fixture:
        name, alias, _, _ = containers.containers[0]
        icon_fixture(Path(fixture))
        for entry in ("bin", "icons", ".local"):
            podman("cp", f"{fixture}/{entry}", f"{name}:/home/tester/")
        podman("exec", name, "sh", "-c",
               "for i in $(seq -w 0 79); do cp /bin/sleep /home/tester/bin/app$i; done; "
               "chown -R tester:tester /home/tester")
        podman("exec", "--user", "tester", "--detach", name, "sh", "-c",
               "for i in $(seq -w 0 79); do /home/tester/bin/app$i 3600 & done; wait")
        time.sleep(2)
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_TEST_CONTAINER=name,
        )
        run_reporting(["flutter", "test", "test_remote/icons_performance_test.dart"], env, "ICONS")
        if containers.leftovers():
            raise subprocess.CalledProcessError(1, ["leftover helpers"])


def lane_disconnect_matrix() -> None:
    library = native_library()
    helpers = release_linux_helpers()
    with TestHostContainers([("disconnect", "amd64")]) as containers:
        name, alias, _, _ = containers.containers[0]
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_TEST_CONTAINER=name,
        )
        run_reporting(["flutter", "test", "test_remote/disconnect_test.dart"], env, "DISCONNECT")
        leftovers = containers.leftovers()
        if leftovers:
            print("helpers left behind: " + "; ".join(leftovers), flush=True)
            raise subprocess.CalledProcessError(1, ["leftover helpers"])
        print("cleanup confirmed: no ~/.local/lib/processlama in the container", flush=True)


def lane_ui() -> None:
    helpers = release_linux_helpers()
    screenshots = ROOT / "docs" / "remote_hosts_evidence" / "screenshots"
    screenshots.mkdir(parents=True, exist_ok=True)
    with TestHostContainers([("base", "amd64")]) as containers, tempfile.TemporaryDirectory(
        prefix="processlama-ui-home-"
    ) as home:
        name, alias, _, _ = containers.containers[0]
        env = dict(
            os.environ,
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_TEST_CONTAINER=name,
            PROCESSLAMA_SCREENSHOT_DIR=str(screenshots),
            # podman keeps its storage under the user's own data directory.
            PROCESSLAMA_PODMAN_XDG_DATA_HOME=os.environ.get(
                "XDG_DATA_HOME", str(Path.home() / ".local" / "share")
            ),
            # The app's support files (icon cache, logs) stay out of the user's.
            XDG_DATA_HOME=f"{home}/data",
            XDG_CACHE_HOME=f"{home}/cache",
        )
        run(["flutter", "test", "integration_test/remote_hosts_test.dart", "-d", "linux"], env=env)
        leftovers = containers.leftovers()
        if leftovers:
            print("helpers left behind: " + "; ".join(leftovers), flush=True)
            raise subprocess.CalledProcessError(1, ["leftover helpers"])
        print("cleanup confirmed: no ~/.local/lib/processlama in the container", flush=True)


def lane_soak() -> None:
    library = native_library()
    helpers = release_linux_helpers()
    with TestHostContainers([("base", "amd64")]) as containers:
        name, alias, _, _ = containers.containers[0]
        # Churn: a short-lived process every second changes the topology.
        podman("exec", "--user", "tester", "--detach", name, "sh", "-c",
               "while true; do sleep 3 & sleep 1; done")
        env = dict(
            os.environ,
            PROCESSLAMA_NATIVE_LIBRARY=str(library),
            PROCESSLAMA_SSH_CONFIG=str(containers.ssh_config),
            PROCESSLAMA_REMOTE_HELPER_DIR=str(helpers),
            PROCESSLAMA_TEST_ALIAS=alias,
            PROCESSLAMA_TEST_CONTAINER=name,
        )
        run_reporting(["flutter", "test", "--enable-vmservice", "test_remote/soak_test.dart"], env, "SOAK")
        if containers.leftovers():
            raise subprocess.CalledProcessError(1, ["leftover helpers"])
        print("cleanup confirmed: no ~/.local/lib/processlama in the container", flush=True)


def lane_protocol() -> None:
    run(["python3", "tooling/remote_wire/generate.py", "--check"])
    run(["cargo", "test", "--locked", "-p", "processlama_wire", "-p", "devmil_remote"], cwd=RUST)
    run(["dart", "test"], cwd=ROOT / "packages" / "devmil_remote")
    run(["flutter", "test", "test/remote"])


def lane_helper() -> None:
    helper = Path(os.environ.get("PROCESSLAMA_REMOTE_HELPER") or helper_binary())
    run(["cargo", "test", "--locked", "-p", "processlama-remote-helper"], cwd=RUST)
    env = dict(os.environ, PROCESSLAMA_REMOTE_HELPER=str(helper))
    run(["flutter", "test", "test_remote/helper_pipe_test.dart"], env=env)


LANES = {
    "protocol": lane_protocol,
    "helper": lane_helper,
    "ssh_loopback": lane_ssh_loopback,
    "containers": lane_containers,
    "mac": lane_mac,
    "performance": lane_performance,
    "disconnect_matrix": lane_disconnect_matrix,
    "soak": lane_soak,
    "ui": lane_ui,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    for name in LANES:
        parser.add_argument(f"--{name.replace('_', '-')}", action="store_true")
    arguments = parser.parse_args()
    selected = [name for name in LANES if getattr(arguments, name)]
    if not selected:
        parser.error("choose at least one lane")
    failures = 0
    for name in selected:
        started = time.monotonic()
        try:
            LANES[name]()
        except subprocess.CalledProcessError as error:
            failures += 1
            print(f"FAIL  --{name.replace('_', '-')} ({error.cmd[0]} exited {error.returncode})", flush=True)
            continue
        print(f"ok    --{name.replace('_', '-')} ({time.monotonic() - started:.0f} s)", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
