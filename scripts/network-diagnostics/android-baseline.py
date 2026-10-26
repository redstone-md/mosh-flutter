#!/usr/bin/env python3
"""Read-only Android aggregate baseline collector. Requires Python 3.10+ and adb."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import time
import zipfile

from android_baseline_metrics import PACKAGE, snapshot, summarize


class Adb:
    def __init__(self, executable, serial):
        self.prefix = [executable] + (["-s", serial] if serial else [])
        self.failed = set()

    def read(self, metric, *command):
        try:
            response = subprocess.run(self.prefix + ["shell", *command], capture_output=True,
                                      text=True, encoding="utf-8", errors="replace", timeout=20,
                                      check=False)
        except (subprocess.TimeoutExpired, OSError):
            self.failed.add(metric)
            return ""
        if response.returncode:
            self.failed.add(metric)
            return ""
        return response.stdout

    def check_device(self):
        response = subprocess.run(self.prefix + ["get-state"], capture_output=True,
                                  text=True, timeout=20, check=False)
        if response.returncode or response.stdout.strip() != "device":
            raise ValueError("Connect and authorize exactly one Android device, or pass --serial")


def installed_package(adb):
    text = adb.read("package", "dumpsys", "package", PACKAGE)
    result = {}
    for label, pattern in (("uid", r"\buserId=(\d+)\b"),
                           ("version_code", r"\bversionCode=(\d+)\b"),
                           ("version_name", r"\bversionName=([A-Za-z0-9_.+-]+)")):
        match = re.search(pattern, text)
        if not match:
            raise ValueError("Cannot identify the installed Mosh package and version")
        result[label] = int(match[1]) if label != "version_name" else match[1]
    return result


def apk_identity(adb):
    lines = adb.read("apk_path", "pm", "path", PACKAGE).splitlines()
    if not lines or any(not re.fullmatch(r"package:/[A-Za-z0-9_./+=-]+\.apk", line) for line in lines):
        return None
    hashes = {}
    for path in sorted({line[len("package:"):] for line in lines}):
        digest = adb.read("apk_hash", "sha256sum", path).split()
        hashes[path] = digest[0].lower() if digest and re.fullmatch(r"[a-fA-F0-9]{64}", digest[0]) else None
    return hashes


def verify_apk_identity(before, after):
    if before is not None and after is not None:
        changed = before.keys() != after.keys()
        changed = changed or any(before[path] and after[path] and before[path] != after[path] for path in before)
        if changed:
            raise ValueError("Mosh APK identity changed during measurement; retry on one build")
        if all(before.values()) and all(after.values()):
            return {"apk_sha256": list(before.values()), "apk_identity_status": "verified-at-endpoints"}
    return {"apk_sha256": [], "apk_identity_status": "unavailable"}


def metadata(adb):
    if adb.read("android_user", "am", "get-current-user").strip() != "0":
        raise ValueError("This collector requires the primary Android user; work-profile UID attribution is unsupported")
    package, identity = installed_package(adb), apk_identity(adb)
    properties = {}
    for key in ("ro.product.manufacturer", "ro.product.model", "ro.build.version.release",
                "ro.build.version.sdk", "ro.build.version.security_patch", "ro.kernel.qemu"):
        value = adb.read("device_properties", "getprop", key).strip()
        properties[key] = value[:100] if value else None
    return {"package": PACKAGE, **package, "device": properties}, identity


def arguments(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", help="adb target; the serial is never included in the report")
    parser.add_argument("--output", type=Path, required=True, help="new output directory")
    parser.add_argument("--duration", type=int, default=180, choices=range(1, 3601), metavar="1..3600")
    parser.add_argument("--warmup", type=int, default=120, choices=range(0, 3601), metavar="0..3600")
    parser.add_argument("--phase", choices=["startup", "steady"], default="steady")
    parser.add_argument("--network", choices=["wifi", "mobile", "ethernet", "offline"], required=True)
    parser.add_argument("--ui", choices=["chat", "list", "minimized"], required=True)
    parser.add_argument("--screen", choices=["on", "off"], required=True)
    parser.add_argument("--profile", choices=["empty", "online", "offline", "mixed"], required=True)
    parser.add_argument("--waiting", choices=["baseline", "enabled", "disabled"], default="baseline")
    for count in ("peers", "dms", "groups", "channels"):
        parser.add_argument("--" + count, type=int, required=True)
    args = parser.parse_args(argv)
    if any(getattr(args, key) < 0 for key in ("peers", "dms", "groups", "channels")):
        parser.error("Counts must not be negative")
    if args.phase == "startup" and args.warmup:
        parser.error("Startup measurements require --warmup 0")
    return args


def collect(args, adb):
    build, original_apk = metadata(adb)
    frequency = adb.read("clock_frequency", "getconf", "CLK_TCK").strip()
    frequency = int(frequency) if frequency.isdecimal() else 0
    print(f"Warmup: {args.warmup}s. Keep the chosen scenario unchanged.", flush=True)
    time.sleep(args.warmup)
    started = datetime.now(timezone.utc).isoformat()
    interval_start = time.monotonic()
    before = snapshot(adb, build["uid"])
    print(f"Collecting for {args.duration}s. Mosh continues running normally.", flush=True)
    time.sleep(args.duration)
    after = snapshot(adb, build["uid"])
    elapsed = time.monotonic() - interval_start
    if installed_package(adb) != {key: build[key] for key in ("uid", "version_code", "version_name")}:
        raise ValueError("Mosh installation changed during measurement; retry on one build")
    build.update(verify_apk_identity(original_apk, apk_identity(adb)))
    scenario = {key: getattr(args, key) for key in ("phase", "network", "ui", "screen", "profile",
                                                  "waiting", "peers", "dms", "groups", "channels")}
    return {"collector": "mosh-android-baseline-v1", "build": build, "scenario": scenario,
            "scenario_source": "operator-supplied; counts are not read from chats",
            "started_utc": started, "requested_seconds": args.duration,
            "elapsed_seconds_including_endpoint_queries": elapsed, "warmup_seconds": args.warmup,
            "unavailable_commands": sorted(adb.failed), "acceptance_complete": False,
            "limitations": ["USB debugging and endpoint queries perturb battery/Doze; use wireless adb unplugged",
                            "Endpoint observations cannot prove continuous Doze, call delivery or radio behavior",
                            "No numeric budgets or app-attributed battery drain established by this collector"],
            **summarize(before, after, frequency)}


def main(argv=None):
    args = arguments(argv)
    adb = Adb(args.adb, args.serial)
    adb.check_device()
    if args.output.exists():
        raise ValueError("Output directory already exists; select a new directory for each run")
    report = collect(args, adb)
    args.output.mkdir(parents=True)
    data = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    (args.output / "report.json").write_text(data, encoding="utf-8")
    archive_path = args.output / "mosh-android-baseline.zip"
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("report.json", data)
    print(f"Report ready: {archive_path}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(f"Collection failed: {error}")
    except (OSError, subprocess.TimeoutExpired):
        raise SystemExit("Collection failed: check adb authorization, installed Mosh, arguments and new output path")
    except KeyboardInterrupt:
        raise SystemExit("Collection cancelled. No Android settings or processes were changed.")
