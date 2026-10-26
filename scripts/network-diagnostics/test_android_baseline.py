"""Collector command-boundary fixtures; these are not phone measurements."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
SPEC = importlib.util.spec_from_file_location("baseline", HERE / "android-baseline.py")
baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(baseline)


class Phone:
    """An adb command fixture, with deliberately sensitive unrelated fields."""

    def __init__(self):
        self.sample = -1

    def run(self, args, **_kwargs):
        command = args[1:]
        if command[:1] == ["-s"]:
            command = command[2:]
        if command == ["get-state"]:
            value = "device"
        else:
            value = self.shell(command[1:])
        return subprocess.CompletedProcess(args, 0, value, "")

    def shell(self, command):
        if command == ["am", "get-current-user"]:
            return "0"
        if command == ["dumpsys", "package", "app.mosh.mosh"]:
            return "userId=10123\nversionCode=42 minSdk=26\nversionName=0.24.3\nSECRET_MESSAGE"
        if command == ["pm", "path", "app.mosh.mosh"]:
            return "package:/data/app/fixture/base.apk"
        if command[:1] == ["sha256sum"]:
            return "a" * 64 + " /data/app/fixture/base.apk"
        if command[:1] == ["getprop"]:
            return {"ro.build.version.sdk": "36", "ro.kernel.qemu": "0"}.get(command[1], "fixture")
        if command == ["getconf", "CLK_TCK"]:
            return "100"
        if command == ["pidof", "app.mosh.mosh"]:
            self.sample += 1
            return "321"
        if command == ["cat", "/proc/321/stat"]:
            fields = ["S"] + ["0"] * 21
            fields[11], fields[12], fields[19] = str(100 + self.sample * 20), "5", "500"
            return "321 (app.mosh.mosh) " + " ".join(fields)
        if command == ["dumpsys", "netstats", "detail"]:
            return ("Dev stats:\n ident=[] uid=-1 set=ALL tag=0x0\n st=1 rb=999999 rp=8 tb=9 tp=2\n"
                    "UID stats:\n ident=[networkId=SECRET_SSID] uid=10123 set=DEFAULT tag=0x0\n"
                    f" st=1 rb={1000 + self.sample * 600} rp=10 tb={100 + self.sample * 80} tp=4\n"
                    " ident=[] uid=55555 set=DEFAULT tag=0x0\n st=1 rb=999999 rp=8 tb=9 tp=2\n"
                    "UID tag stats:\n ident=[] uid=10123 set=DEFAULT tag=0x0\n st=1 rb=999999 rp=8 tb=9 tp=2")
        if command == ["dumpsys", "batterystats", "--checkin"]:
            return (f"9,10123,l,wl,SECRET_WAKELOCK,0,f,0,{100 + self.sample * 50},p,2,0,w,0\n"
                    f"9,10123,l,apk,{2 + self.sample},app.mosh.mosh,SECRET_SERVICE,0,0,0\n"
                    "9,55555,l,wl,OTHER_APP,0,f,0,99999,p,50,0,w,0\n")
        if command == ["dumpsys", "battery"]:
            return f"AC powered: false\nUSB powered: false\nWireless powered: false\nlevel: {80 - self.sample}\nscale: 100\nCharge counter: {4000000 - self.sample * 10}\n"
        if command == ["dumpsys", "power"]:
            return "mWakefulness=Awake\nSECRET_WAKELOCK"
        raise AssertionError(f"Unexpected adb command: {command}")


class CollectorTest(unittest.TestCase):
    def collect(self, phone):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        output = Path(self.work.name, "report")
        arguments = ["--output", str(output), "--duration", "1", "--warmup", "0",
                     "--network", "wifi", "--ui", "chat", "--screen", "on",
                     "--profile", "offline", "--peers", "13", "--dms", "8",
                     "--groups", "2", "--channels", "1"]
        with patch("subprocess.run", side_effect=phone.run), patch("time.sleep"), \
                patch("time.monotonic", side_effect=range(100, 500)):
            baseline.main(arguments)
        with zipfile.ZipFile(output / "mosh-android-baseline.zip") as archive:
            self.assertEqual(archive.namelist(), ["report.json"])
            data = archive.read("report.json")
        self.assertNotIn(b"SECRET", data)
        self.assertNotIn(b"OTHER_APP", data)
        return json.loads(data)

    def test_reports_only_selected_app_aggregates_with_explicit_metric_scope(self):
        report = self.collect(Phone())
        self.assertEqual(report["network"]["delta"]["rx_bytes"], 600)
        self.assertEqual(report["network"]["delta"]["tx_bytes"], 80)
        self.assertEqual(report["network"]["scope"], "uid-history-not-process")
        self.assertEqual(report["cpu"]["delta_ticks"], 20)
        self.assertEqual(report["wakelocks"]["partial_ms_delta"], 50)
        self.assertEqual(report["wakeups"]["apk_wakeups_delta"], 1)
        self.assertEqual(report["battery"]["level_delta"], -1)
        self.assertEqual(report["scenario"]["dms"], 8)
        self.assertFalse(report["acceptance_complete"])

    def test_refuses_a_work_profile_instead_of_attributing_its_traffic_to_primary_user(self):
        class WorkProfile(Phone):
            def shell(self, command):
                if command == ["am", "get-current-user"]:
                    return "10"
                return super().shell(command)

        with self.assertRaisesRegex(ValueError, "primary Android user"):
            self.collect(WorkProfile())

    def test_nonroot_denials_are_missing_metrics_and_never_zero_usage(self):
        class Restricted(Phone):
            def run(self, args, **kwargs):
                if "cat" in args or any(key in args for key in ("battery", "batterystats")):
                    return subprocess.CompletedProcess(args, 1, "", "SECRET_PERMISSION_DETAIL")
                if "netstats" in args:
                    raise subprocess.TimeoutExpired(args, 20, output="SECRET_TIMEOUT_DETAIL")
                return super().run(args, **kwargs)

        report = self.collect(Restricted())
        for key in ("cpu", "network", "battery", "wakeups", "wakelocks"):
            self.assertEqual(report[key]["status"], "unavailable", key)
        self.assertIn("network", report["unavailable_commands"])

    def test_restarts_and_reset_histories_cannot_be_reported_as_idle_savings(self):
        class Reset(Phone):
            def shell(self, command):
                value = super().shell(command)
                if self.sample == 1 and command[:1] == ["cat"]:
                    return value.replace(" 500 ", " 600 ")
                if self.sample == 1 and command == ["dumpsys", "netstats", "detail"]:
                    return value.replace("rb=1600", "rb=1")
                if self.sample == 1 and command == ["dumpsys", "batterystats", "--checkin"]:
                    return value.replace("150,p", "1,p").replace("apk,3,", "apk,0,")
                return value

        report = self.collect(Reset())
        for key in ("cpu", "network", "wakeups", "wakelocks"):
            self.assertEqual(report[key]["status"], "unavailable", key)

    def test_supported_android_bucket_and_extended_wakelock_formats_preserve_totals(self):
        class OlderBuckets(Phone):
            def shell(self, command):
                value = super().shell(command)
                if "netstats" in command:
                    for short, long in (("st", "bucketStart"), ("rb", "rxBytes"),
                                        ("rp", "rxPackets"), ("tb", "txBytes"), ("tp", "txPackets")):
                        value = value.replace(short + "=", long + "=")
                if "batterystats" in command:
                    value = value.replace(",f,0,", ",f,0,0,0,0,").replace(",p,2,", ",p,2,0,0,0,")
                    value += f"9,10123,l,apk,{2 + self.sample},app.mosh.mosh,OTHER_SERVICE,0,0,0\n"
                return value

        report = self.collect(OlderBuckets())
        self.assertEqual(report["network"]["delta"],
                         {"rx_bytes": 600, "rx_packets": 0, "tx_bytes": 80, "tx_packets": 0})
        self.assertEqual(report["wakeups"]["apk_wakeups_delta"], 1)
        self.assertEqual(report["wakelocks"]["partial_ms_delta"], 50)


if __name__ == "__main__":
    unittest.main()
