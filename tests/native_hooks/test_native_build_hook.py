"""Exercise the production Dart hook without compiling Rust dependencies."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class NativeBuildHookTest(unittest.TestCase):
    def test_compiler_profile_and_bundled_payload_agree(self):
        for linking in (False, True):
            for target_dir in (None, "cargo-cache", "absolute"):
                with self.subTest(linking=linking, target_dir=target_dir):
                    self.run_hook(linking, target_dir)

    def test_debug_builds_package_the_development_remote_helper(self):
        root, package, args_files = self.run_hook(False, None, dev_helper=True)
        calls = [json.loads(path.read_text()) for path in args_files]
        helper_call = next(args for args in calls if "processlama-remote-helper" in args)
        self.assertEqual(helper_call[helper_call.index("--profile") + 1], "helper-dev")
        self.assertIn("--locked", helper_call)
        descriptor = json.loads(
            (package / "build/remote-helper-dev/linux-x86_64/processlama-remote-helper.json").read_text()
        )
        self.assertEqual(descriptor["target"], "linux-x86_64")
        self.assertTrue((package / "build/remote-helper-dev/linux-x86_64/processlama-remote-helper").is_file())

    def run_hook(self, linking, target_dir, dev_helper=False):
        if dev_helper:
            temporary = tempfile.mkdtemp(prefix="processlama-hook-")
            self.addCleanup(lambda: shutil.rmtree(temporary))
            return self._run_hook(Path(temporary), linking, target_dir, dev_helper)
        with tempfile.TemporaryDirectory(prefix="processlama-hook-") as tmp:
            self._run_hook(Path(tmp), linking, target_dir, dev_helper)

    def _run_hook(self, root, linking, target_dir, dev_helper):
        package = root / "package"
        (package / "rust-core/core/src").mkdir(parents=True)
        (package / "rust-core/core/src/lib.rs").touch()
        (package / "rust-core/core/Cargo.toml").touch()
        (package / "rust-core/telemetry/src").mkdir(parents=True)
        (package / "rust-core/telemetry/src/lib.rs").touch()
        (package / "rust-core/telemetry/Cargo.toml").touch()
        (package / "rust-core/target/debug").mkdir(parents=True)
        (package / "rust-core/target/debug/stale.rs").touch()
        (package / "rust-core/Cargo.toml").touch()
        (package / "rust-core/Cargo.lock").touch()
        tools = root / "bin"
        tools.mkdir()
        cargo = tools / "cargo"
        cargo.write_text(
            f"#!{sys.executable}\n"
            "import json, os, sys\n"
            "from pathlib import Path\n"
            "args = sys.argv[1:]\n"
            "calls = Path(os.environ['HOOK_CARGO_ARGS'])\n"
            "index = len(list(calls.parent.glob(calls.name + '*')))\n"
            "Path(f'{calls}.{index}').write_text(json.dumps(args))\n"
            "manifest = Path(args[args.index('--manifest-path') + 1])\n"
            "target = args[args.index('--target') + 1]\n"
            "profile = 'release' if '--release' in args else 'debug'\n"
            "if '--profile' in args: profile = args[args.index('--profile') + 1]\n"
            "out = Path(os.environ.get('CARGO_TARGET_DIR', manifest.parent / 'target'))\n"
            "if 'processlama-remote-helper' in args:\n"
            "    helper = out / target / profile / 'processlama-remote-helper'\n"
            "    helper.parent.mkdir(parents=True, exist_ok=True)\n"
            "    header = bytearray(64); header[:4] = b'\\x7fELF'; header[4] = 2; header[18] = 62\n"
            "    helper.write_bytes(bytes(header))\n"
            "    sys.exit(0)\n"
            "library = out / target / profile / 'libprocesslama_core.so'\n"
            "library.parent.mkdir(parents=True, exist_ok=True)\n"
            "library.write_text(profile)\n"
        )
        objdump = tools / "objdump"
        objdump.write_text("#!/bin/sh\necho 'GLIBC_2.39 x'\n")
        objdump.chmod(0o755)
        if dev_helper:
            for relative in (
                "scripts/package_remote_helper.py",
                "tooling/remote_wire/contract.json",
                "rust-core/remote-helper/COMPATIBILITY",
            ):
                (package / relative).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, package / relative)
        cargo.chmod(0o755)
        output = root / "output.json"
        config = root / "input.json"
        config.write_text(
            json.dumps(
                {
                    "assets": {},
                    "config": {
                        "build_asset_types": ["code_assets/code"],
                        "extensions": {
                            "code_assets": {
                                "link_mode_preference": "dynamic",
                                "target_architecture": "x64",
                                "target_os": "linux",
                            }
                        },
                        "linking_enabled": linking,
                    },
                    "out_dir_shared": str(root / "shared") + "/",
                    "out_file": str(output),
                    "package_name": "processlama",
                    "package_root": str(package) + "/",
                    "user_defines": {
                        "workspace_pubspec": {
                            "base_path": str(package / "pubspec.yaml"),
                            "defines": {"dev_remote_helper": dev_helper},
                        }
                    },
                }
            )
        )
        environment = os.environ.copy()
        environment["PATH"] = str(tools) + os.pathsep + environment["PATH"]
        environment["HOOK_CARGO_ARGS"] = str(root / "cargo-args.json")
        environment.pop("CARGO_TARGET_DIR", None)
        if target_dir:
            environment["CARGO_TARGET_DIR"] = (
                str(root / "cargo-cache")
                if target_dir == "absolute"
                else target_dir
            )
        result = subprocess.run(
            [
                shutil.which("dart"),
                "--packages=" + str(ROOT / ".dart_tool/package_config.json"),
                str(ROOT / "hook/build.dart"),
                "--config",
                str(config),
            ],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args_files = sorted(root.glob("cargo-args.json.*"))
        args = json.loads(args_files[0].read_text())
        self.assertEqual("--release" in args, linking)
        self.assertIn("--locked", args)
        self.assertEqual(args[args.index("--package") + 1], "processlama_core")
        dependencies = {
            Path(path).relative_to(package).as_posix()
            for path in json.loads(output.read_text())["dependencies"]
            if Path(path).is_relative_to(package)
        }
        self.assertIn("rust-core/core/src/lib.rs", dependencies)
        self.assertIn("rust-core/telemetry/src/lib.rs", dependencies)
        self.assertIn("rust-core/telemetry/Cargo.toml", dependencies)
        self.assertNotIn("rust-core/target/debug/stale.rs", dependencies)
        asset = json.loads(output.read_text())["assets"][0]["encoding"]
        bundled = Path(asset["file"])
        self.assertTrue(bundled.is_relative_to(root / "shared"))
        self.assertEqual(bundled.read_text(), "release" if linking else "debug")
        if not dev_helper:
            self.assertEqual(len(args_files), 1, "no helper build unless enabled")
        return root, package, args_files


if __name__ == "__main__":
    unittest.main()
