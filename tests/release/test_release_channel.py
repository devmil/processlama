import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseChannelTest(unittest.TestCase):
    def test_promotes_beta_base_to_stable_and_increments_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "VERSION").write_text("2.4.0-beta.7\n31\n")
            command = f"""
set -euo pipefail
export MIM_REPO_ROOT={root!s}
export MIM_RELEASE_CHANNEL=stable
source {ROOT / 'scripts/lib/release-channel.sh'}
mim_bump_release_channel_version promote
"""
            subprocess.run(["bash", "-c", command], check=True, capture_output=True, text=True)
            self.assertEqual((root / "VERSION").read_text(), "2.4.0\n32\n")

    def test_rejects_promote_on_beta_channel(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "VERSION").write_text("2.4.0-beta.7\n31\n")
            command = f"""
export MIM_REPO_ROOT={root!s}
export MIM_RELEASE_CHANNEL=beta
source {ROOT / 'scripts/lib/release-channel.sh'}
mim_bump_release_channel_version promote
"""
            result = subprocess.run(["bash", "-c", command], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("requires --channel stable", result.stderr)


if __name__ == "__main__":
    unittest.main()
