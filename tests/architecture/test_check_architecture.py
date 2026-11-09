"""The architecture check accepts the repository and rejects each forbidden edge."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "check_architecture.py"


def run(root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root)],
        capture_output=True,
        text=True,
        check=False,
    )


class ArchitectureCheckTest(unittest.TestCase):
    def test_repository_passes(self):
        result = run(ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)

    def fixture(self, files: dict[str, str]) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="processlama-arch-"))
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(directory)]))
        base = {
            "lib/rust/api.dart": "",
            "lib/repositories/impl/bridge.dart": "import '../../rust/api.dart';\n",
            "rust-core/core/Cargo.toml": "[dependencies]\nprocesslama_telemetry = {}\n",
            "rust-core/core/src/lib.rs": "pub mod api;\n",
            "rust-core/core/src/api.rs": "",
            "rust-core/telemetry/Cargo.toml": "[dependencies]\nprocesstree = {}\n",
            "rust-core/telemetry/src/lib.rs": "",
        }
        base.update(files)
        for name, content in base.items():
            path = directory / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        return directory

    def assert_rejected(self, files: dict[str, str], fragment: str):
        result = run(self.fixture(files))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(fragment, result.stderr)

    def test_clean_fixture_passes(self):
        self.assertEqual(run(self.fixture({})).returncode, 0)

    def test_widget_importing_the_bridge_is_rejected(self):
        self.assert_rejected(
            {"lib/screens/view.dart": "import '../rust/api.dart';\n"},
            "imports the Rust bridge",
        )
        self.assert_rejected(
            {"lib/services/s.dart": "import 'package:processlama/rust/api.dart';\n"},
            "imports the Rust bridge",
        )

    def test_widget_importing_devmil_remote_is_rejected(self):
        self.assert_rejected(
            {"lib/screens/view.dart": "import 'package:devmil_remote/devmil_remote.dart';\n"},
            "imports devmil_remote",
        )
        self.assert_rejected(
            {"lib/models/host.dart": "import 'package:devmil_remote/devmil_remote.dart';\n"},
            "imports devmil_remote",
        )
        self.assert_rejected(
            {"lib/repositories/remote.dart": "import 'package:devmil_remote/devmil_remote.dart';\n"},
            "imports devmil_remote",
        )

    def test_services_and_repository_implementations_may_use_devmil_remote(self):
        result = run(
            self.fixture(
                {
                    "lib/services/impl/hosts.dart": "import 'package:devmil_remote/devmil_remote.dart';\n",
                    "lib/repositories/impl/ssh.dart": "import 'package:devmil_remote/devmil_remote.dart';\n",
                }
            )
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_shared_dart_package_importing_the_app_is_rejected(self):
        self.assert_rejected(
            {
                "packages/devmil_remote/lib/src/channel.dart":
                    "import 'package:processlama/models/models.dart';\n"
            },
            "shared package imports",
        )

    def test_enum_index_mapping_is_rejected(self):
        self.assert_rejected(
            {"lib/repositories/impl/map.dart": "final s = Status.values[dto.status.index];\n"},
            "values[...index]",
        )

    def test_crates_depending_on_the_core_are_rejected(self):
        self.assert_rejected(
            {"rust-core/remote-helper/Cargo.toml": "[dependencies]\nprocesslama_core = {}\n"},
            "depends on processlama_core",
        )
        self.assert_rejected(
            {"rust-core/telemetry/src/lib.rs": "use processlama_core::api;\n"},
            "uses processlama_core",
        )

    def test_shared_crate_using_processlama_is_rejected(self):
        self.assert_rejected(
            {
                "rust-core/devmil-remote/Cargo.toml":
                    "[dependencies]\nprocesslama-wire = {}\n",
                "rust-core/devmil-remote/src/lib.rs": "",
            },
            "shared crate depends on processlama_wire",
        )
        self.assert_rejected(
            {
                "rust-core/devmil-remote/Cargo.toml": "[dependencies]\n",
                "rust-core/devmil-remote/src/lib.rs": "use processlama_telemetry::x;\n",
            },
            "shared crate uses processlama_telemetry",
        )

    def test_core_modules_importing_the_facade_are_rejected(self):
        self.assert_rejected(
            {"rust-core/core/src/network.rs": "use crate::api::ProcessSnapshotDto;\n"},
            "imports the bridge facade",
        )


if __name__ == "__main__":
    unittest.main()
