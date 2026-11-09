import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseResumeTest(unittest.TestCase):
    def test_resolves_annotated_release_tag_behind_current_main(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            self.git(repository, "init", "-q")
            self.git(repository, "config", "user.name", "Release Test")
            self.git(repository, "config", "user.email", "release@example.invalid")
            self.write_release_files(repository)
            self.git(repository, "add", ".")
            self.git(repository, "commit", "-qm", "release")
            release_commit = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "tag", "-am", "release", "v1.0.0-beta.11-13")
            (repository / "pipeline-fix").write_text("fixed\n")
            self.git(repository, "add", "pipeline-fix")
            self.git(repository, "commit", "-qm", "fix release pipeline")

            command = f"""
set -euo pipefail
export MIM_REPO_ROOT={repository!s}
source {ROOT / 'scripts/lib/release-git.sh'}
mim_resolve_existing_release_commit
"""
            result = subprocess.run(
                ["bash", "-c", command],
                check=True,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.stdout.strip(), release_commit)

    def test_rejects_lightweight_release_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            self.git(repository, "init", "-q")
            self.git(repository, "config", "user.name", "Release Test")
            self.git(repository, "config", "user.email", "release@example.invalid")
            self.write_release_files(repository)
            self.git(repository, "add", ".")
            self.git(repository, "commit", "-qm", "release")
            self.git(repository, "tag", "v1.0.0-beta.11-13")

            command = f"""
export MIM_REPO_ROOT={repository!s}
source {ROOT / 'scripts/lib/release-git.sh'}
mim_resolve_existing_release_commit
"""
            result = subprocess.run(
                ["bash", "-c", command], capture_output=True, text=True
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("existing annotated tag", result.stderr)

    def test_resolves_untagged_prepared_release_before_pipeline_fix(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = self.prepare_untagged_release(directory)
            candidate = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            (repository / "pipeline-fix").write_text("fixed\n")
            self.git(repository, "add", ".")
            self.git(repository, "commit", "-qm", "fix pipeline")
            result = self.resolve(repository)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), candidate)
            self.assertEqual(self.git(repository, "tag", "--list").stdout, "")

    def test_rejects_unprepared_untagged_version(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = self.prepare_untagged_release(directory, subject="ordinary edit")
            result = self.resolve(repository)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no prepared release commit", result.stderr)

    def test_rejects_changed_preparation_metadata(self):
        for name in ["pubspec.yaml", "CHANGELOG.md", "RELEASE_NOTES.md"]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                repository = self.prepare_untagged_release(directory)
                with (repository / name).open("a") as stream:
                    stream.write("changed\n")
                self.git(repository, "add", ".")
                self.git(repository, "commit", "-qm", "change metadata")
                result = self.resolve(repository)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("changed after release preparation", result.stderr)

    def test_rejects_dirty_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = self.prepare_untagged_release(directory)
            (repository / "RELEASE_NOTES.md").write_text("uncommitted\n")
            result = self.resolve(repository)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("clean committed checkout", result.stderr)

    def test_rejects_missing_released_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = self.prepare_untagged_release(directory)
            (repository / "RELEASE_NOTES.md").write_text("## [Unreleased Beta]\n")
            self.git(repository, "add", ".")
            self.git(repository, "commit", "--amend", "--no-edit", "-q")
            result = self.resolve(repository)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("has no released", result.stderr)

    def test_publication_tags_candidate_instead_of_tooling_checkout(self):
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        command = re.search(r"            git tag -a .*?(?=            git push)", workflow, re.S).group()
        command = command.replace("${{ needs.prepare.outputs.tag }}", "v1.0.0-beta.11-13")
        command = command.replace("${{ needs.prepare.outputs.version }}", "1.0.0-beta.11")
        command = command.replace("${{ needs.prepare.outputs.build }}", "13")
        with tempfile.TemporaryDirectory() as directory:
            repository = self.prepare_untagged_release(directory)
            candidate = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            (repository / "pipeline-fix").write_text("fixed\n")
            self.git(repository, "add", ".")
            self.git(repository, "commit", "-qm", "fix pipeline")
            command = command.replace("${{ needs.prepare.outputs.release_sha }}", candidate)
            subprocess.run(["bash", "-euc", command], cwd=repository, check=True)
            self.assertEqual(self.git(repository, "rev-parse", "v1.0.0-beta.11-13^{commit}").stdout.strip(), candidate)
            self.assertEqual(self.git(repository, "cat-file", "-t", "v1.0.0-beta.11-13").stdout.strip(), "tag")

    def prepare_untagged_release(self, directory, subject="Beta release v1.0.0-beta.11 (build 13)"):
        repository = Path(directory)
        self.git(repository, "init", "-q")
        self.git(repository, "config", "user.name", "Release Test")
        self.git(repository, "config", "user.email", "release@example.invalid")
        self.write_release_files(repository)
        self.git(repository, "add", ".")
        self.git(repository, "commit", "-qm", subject)
        return repository

    @staticmethod
    def resolve(repository):
        return subprocess.run(
            ["bash", "-euc", f"source {ROOT / 'scripts/lib/release-git.sh'}; mim_resolve_existing_release_commit"],
            env={**os.environ, "MIM_REPO_ROOT": str(repository)},
            capture_output=True, text=True,
        )

    @staticmethod
    def write_release_files(repository):
        (repository / "VERSION").write_text("1.0.0-beta.11\n13\n")
        (repository / "pubspec.yaml").write_text("version: 1.0.0-beta.11+13\n")
        notes = "## [1.0.0-beta.11] - 2026-09-20\n\n- Fixed publishing.\n"
        (repository / "CHANGELOG.md").write_text(notes)
        (repository / "RELEASE_NOTES.md").write_text(notes)

    @staticmethod
    def git(repository, *arguments):
        return subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
