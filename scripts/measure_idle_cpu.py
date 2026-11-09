#!/usr/bin/env python3
"""Measures a Linux build's idle CPU the way docs/09 does.

Launches the executable with a private XDG root, waits for the warm-up, then
reads /proc/<pid>/task/*/stat (utime + stime) for the measurement window and
prints the average as a percentage of one CPU.

Usage: measure_idle_cpu.py EXECUTABLE [--warmup 10] [--seconds 120]
"""

import argparse
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

TICKS = os.sysconf("SC_CLK_TCK")


def process_ticks(pid: int) -> int:
    total = 0
    for stat in Path(f"/proc/{pid}/task").glob("*/stat"):
        try:
            fields = stat.read_text().rsplit(")", 1)[1].split()
        except OSError:
            continue
        total += int(fields[11]) + int(fields[12])
    return total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable")
    parser.add_argument("--warmup", type=float, default=10)
    parser.add_argument("--seconds", type=float, default=120)
    arguments = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="processlama-cpu-"))
    environment = dict(os.environ)
    for name in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
        environment[name] = str(root / name.lower())
    process = subprocess.Popen(
        [arguments.executable],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        time.sleep(arguments.warmup)
        if process.poll() is not None:
            print("the application exited during warm-up", file=sys.stderr)
            return 1
        start_ticks, start = process_ticks(process.pid), time.monotonic()
        time.sleep(arguments.seconds)
        end_ticks, end = process_ticks(process.pid), time.monotonic()
        percent = (end_ticks - start_ticks) / TICKS / (end - start) * 100
        print(f"{percent:.2f}% of one CPU over {end - start:.0f} s")
        return 0
    finally:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
