"""scripts/package_remote_helper.py: descriptors, floors, archives and bundling."""

import hashlib
import importlib.util
import json
import os
import stat
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "package_remote_helper", ROOT / "scripts" / "package_remote_helper.py"
)
package_remote_helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(package_remote_helper)

TARGETS = ["linux-x86_64", "linux-arm64", "macos-arm64", "macos-x86_64"]


def elf(machine: int) -> bytes:
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = 2
    header[18:20] = machine.to_bytes(2, "little")
    return bytes(header) + b"helper"


def macho(cpu: int) -> bytes:
    return b"\xcf\xfa\xed\xfe" + cpu.to_bytes(4, "little") + bytes(24) + b"helper"


BINARIES = {
    "linux-x86_64": elf(62),
    "linux-arm64": elf(183),
    "macos-arm64": macho(0x0100000C),
    "macos-x86_64": macho(0x01000007),
}


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="processlama-package-"))
        self.addCleanup(lambda: __import__("shutil").rmtree(self.directory))
        tools = self.directory / "tools"
        tools.mkdir()
        self.glibc = "2.34"
        for name in ("objdump", "aarch64-linux-gnu-objdump", "x86_64-linux-gnu-objdump"):
            tool = tools / name
            tool.write_text(
                "#!/bin/sh\n"
                f'cat "{self.directory}/glibc" 2>/dev/null\n'
            )
            tool.chmod(0o755)
        self.old_path = os.environ["PATH"]
        os.environ["PATH"] = f"{tools}{os.pathsep}{self.old_path}"
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self.old_path))
        self.set_glibc("2.34")

    def set_glibc(self, version: str):
        (self.directory / "glibc").write_text(
            f"0000 DF *UND* 0000 GLIBC_2.2.5 memcpy\n0000 DF *UND* 0000 GLIBC_{version} x\n"
        )

    def binary(self, target: str) -> Path:
        path = self.directory / f"{target}.bin"
        path.write_bytes(BINARIES[target])
        return path

    def package_all(self, output: Path):
        for target in TARGETS:
            package_remote_helper.package(target, self.binary(target), output)

    def test_descriptor_records_build_size_digest_and_floor(self):
        output = self.directory / "out"
        descriptor = package_remote_helper.package(
            "linux-x86_64", self.binary("linux-x86_64"), output
        )
        data = BINARIES["linux-x86_64"]
        version = package_remote_helper.compatibility_version()
        self.assertEqual(descriptor["buildId"], str(version).rjust(40, "0"))
        self.assertEqual(descriptor["size"], len(data))
        self.assertEqual(descriptor["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(descriptor["glibcFloor"], "2.34")
        stored = json.loads((output / "linux-x86_64" / "processlama-remote-helper.json").read_text())
        self.assertEqual(stored, descriptor)

    def test_archives_are_reproducible_and_contain_only_the_helper(self):
        first = self.directory / "first"
        second = self.directory / "second"
        package_remote_helper.package("macos-arm64", self.binary("macos-arm64"), first)
        package_remote_helper.package("macos-arm64", self.binary("macos-arm64"), second)
        name = "processlama-remote-helper-macos-arm64.tar.gz"
        self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
        with tarfile.open(first / name) as archive:
            members = {member.name: member for member in archive.getmembers()}
        self.assertEqual(
            set(members),
            {"macos-arm64/processlama-remote-helper", "macos-arm64/processlama-remote-helper.json"},
        )
        # Reproducible, and representable in a ZIP (1980 or later) for the Windows bundle.
        self.assertEqual(
            members["macos-arm64/processlama-remote-helper"].mtime,
            package_remote_helper.ARCHIVE_MTIME,
        )
        self.assertGreaterEqual(package_remote_helper.ARCHIVE_MTIME, 315532800)

    def test_a_newer_glibc_than_the_floor_is_refused(self):
        self.set_glibc("2.39")
        with self.assertRaisesRegex(package_remote_helper.PackageError, "newer than the 2.35"):
            package_remote_helper.package(
                "linux-arm64", self.binary("linux-arm64"), self.directory / "out"
            )

    def test_a_binary_for_another_machine_is_refused(self):
        with self.assertRaisesRegex(package_remote_helper.PackageError, "does not match"):
            package_remote_helper.package(
                "linux-arm64", self.binary("linux-x86_64"), self.directory / "out"
            )
        with self.assertRaisesRegex(package_remote_helper.PackageError, "Mach-O"):
            package_remote_helper.package(
                "macos-arm64", self.binary("linux-x86_64"), self.directory / "out"
            )

    def test_unpack_restores_the_tree_and_rejects_other_members(self):
        artifacts = self.directory / "artifacts"
        self.package_all(artifacts)
        restored = self.directory / "restored"
        self.assertEqual(package_remote_helper.unpack(artifacts, restored), sorted(TARGETS))
        for target in TARGETS:
            package_remote_helper.verify(restored, target)
        hostile = self.directory / "hostile"
        hostile.mkdir()
        with tarfile.open(hostile / "processlama-remote-helper-linux-x86_64.tar.gz", "w:gz") as archive:
            payload = self.directory / "payload"
            payload.write_bytes(b"x")
            archive.add(payload, arcname="../escape")
        with self.assertRaisesRegex(package_remote_helper.PackageError, "unexpected member"):
            package_remote_helper.unpack(hostile, self.directory / "nowhere")

    def test_bundle_requires_every_target_when_asked(self):
        source = self.directory / "source"
        package_remote_helper.package("linux-x86_64", self.binary("linux-x86_64"), source)
        dest = self.directory / "bundle"
        self.assertEqual(package_remote_helper.bundle(source, dest, require=False), ["linux-x86_64"])
        with self.assertRaisesRegex(package_remote_helper.PackageError, "missing remote helpers"):
            package_remote_helper.bundle(source, dest, require=True)
        self.package_all(source)
        self.assertEqual(package_remote_helper.bundle(source, dest, require=True), TARGETS)
        mode = stat.S_IMODE((dest / "linux-arm64" / "processlama-remote-helper").stat().st_mode)
        self.assertEqual(mode, 0o644)

    def test_bundle_refuses_a_helper_that_does_not_match_its_descriptor(self):
        source = self.directory / "source"
        package_remote_helper.package("linux-x86_64", self.binary("linux-x86_64"), source)
        helper = source / "linux-x86_64" / "processlama-remote-helper"
        helper.write_bytes(helper.read_bytes() + b"tampered")
        with self.assertRaisesRegex(package_remote_helper.PackageError, "does not match its descriptor"):
            package_remote_helper.bundle(source, self.directory / "bundle", require=False)

    def test_refresh_describes_re_signed_binaries(self):
        source = self.directory / "source"
        package_remote_helper.package("macos-x86_64", self.binary("macos-x86_64"), source)
        helper = source / "macos-x86_64" / "processlama-remote-helper"
        helper.write_bytes(helper.read_bytes() + b"signature")
        self.assertEqual(package_remote_helper.refresh(source), ["macos-x86_64"])
        package_remote_helper.verify(source, "macos-x86_64")

    def test_every_package_script_bundles_the_helpers(self):
        for script in ("package-linux.sh", "package-release.sh"):
            text = (ROOT / "scripts" / script).read_text()
            self.assertIn("package_remote_helper.py\" bundle", text, script)
        windows = (ROOT / "scripts" / "package-windows.ps1").read_text()
        self.assertIn("PROCESSLAMA_REQUIRE_REMOTE_HELPER", windows)
        self.assertIn('"linux-x86_64", "linux-arm64", "macos-arm64", "macos-x86_64"', windows)


if __name__ == "__main__":
    unittest.main()
