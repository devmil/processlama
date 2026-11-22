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
            "rust-core/desktop/domain/Cargo.toml": "[dependencies]\nserde_json = {}\n",
            "rust-core/desktop/domain/src/lib.rs": "",
            "rust-core/desktop/application/Cargo.toml": "[dependencies]\nprocesslama-domain = {}\n",
            "rust-core/desktop/application/src/lib.rs": "use processlama_domain::X;\n",
            "rust-core/desktop/qt/Cargo.toml": "[dependencies]\nprocesslama-application = {}\nqtbridge = {}\n",
            "rust-core/desktop/qt/src/lib.rs": "use processlama_application::Y;\nuse qtbridge::qobject;\n",
            "rust-core/desktop/app/Cargo.toml": "[dependencies]\nprocesslama-qt = {}\nprocesslama-infra-local = {}\n",
            "rust-core/desktop/app/src/main.rs": "use processlama_infra_local::Z;\n",
            "rust-core/devmil-remote/src/lib.rs": "",
            "qml/ProcessLama/Main.qml": "import QtQuick\nimport Meridian\nItem {}\n",
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
        result = run(self.fixture({}))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_domain_depending_on_another_layer_is_rejected(self):
        self.assert_rejected(
            {"rust-core/desktop/domain/Cargo.toml": "[dependencies]\nprocesslama-application = {}\n"},
            "domain must not depend on processlama_application",
        )

    def test_application_using_qt_is_rejected(self):
        self.assert_rejected(
            {"rust-core/desktop/application/src/lib.rs": "use qtbridge::qobject;\n"},
            "application must not use qtbridge",
        )

    def test_qt_naming_an_adapter_is_rejected(self):
        self.assert_rejected(
            {"rust-core/desktop/qt/src/lib.rs": "use processlama_infra_remote::SshConnector;\n"},
            "qt must not use processlama_infra_remote",
        )

    def test_adapters_using_each_other_is_rejected(self):
        self.assert_rejected(
            {
                "rust-core/desktop/infra-storage/Cargo.toml": "[dependencies]\nprocesslama-infra-local = {}\n",
                "rust-core/desktop/infra-storage/src/lib.rs": "",
            },
            "infra-storage must not depend on processlama_infra_local",
        )

    def test_dev_dependencies_are_allowed(self):
        files = {
            "rust-core/desktop/infra-storage/Cargo.toml": "[dependencies]\nprocesslama-domain = {}\n[dev-dependencies]\nprocesslama-infra-local = {}\n",
            "rust-core/desktop/infra-storage/src/lib.rs": "",
        }
        self.assertEqual(run(self.fixture(files)).returncode, 0)

    def test_unknown_layer_is_rejected(self):
        self.assert_rejected(
            {"rust-core/desktop/misc/Cargo.toml": "[dependencies]\n", "rust-core/desktop/misc/src/lib.rs": ""},
            "unknown desktop layer",
        )

    def test_transport_importing_the_product_is_rejected(self):
        self.assert_rejected(
            {"rust-core/devmil-remote/src/lib.rs": "use processlama_wire::contract;\n"},
            "devmil_remote must not import",
        )

    def test_qml_loading_code_is_rejected(self):
        self.assert_rejected(
            {"qml/ProcessLama/X.qml": "import QtQuick\nItem { Component.onCompleted: Qt.createQmlObject('', this) }\n"},
            "loads code at run time",
        )
        self.assert_rejected(
            {"qml/ProcessLama/Y.qml": "import Some.Plugin\nItem {}\n"},
            "imports Some.Plugin",
        )


if __name__ == "__main__":
    unittest.main()
