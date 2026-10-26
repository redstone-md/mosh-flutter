"""Allowlisted aggregate readers. Raw Android service dumps never leave memory."""
import csv
import re
import time


PACKAGE = "app.mosh.mosh"
NETWORK_FIELDS = {
    "rx_bytes": ("rb", "rxBytes"), "rx_packets": ("rp", "rxPackets"),
    "tx_bytes": ("tb", "txBytes"), "tx_packets": ("tp", "txPackets"),
}


def unavailable(reason):
    return {"status": "unavailable", "reason": reason}


def integers(text):
    return {name: int(value) for name, value in re.findall(r"(\w+)=(-?\d+)", text)}


def network_totals(text, uid):
    totals = dict.fromkeys(NETWORK_FIELDS, 0)
    section, selected, seen = False, False, False
    for line in text.splitlines():
        if line.strip().endswith("stats:"):
            section, selected = line.strip() == "UID stats:", False
        if "uid=" in line:
            selected = section and re.search(rf"\buid={uid}\b", line) is not None
            selected = selected and re.search(r"\btag=0x0\b", line) is not None
        if not selected or not re.search(r"\b(?:st|bucketStart)=", line):
            continue
        values = integers(line)
        for target, aliases in NETWORK_FIELDS.items():
            value = next((values[key] for key in aliases if key in values), None)
            if value is None or value < 0:
                return None
            totals[target] += value
        seen = True
    return totals if seen else None


def battery_values(text):
    values = {}
    for label, key in (("level", "level"), ("scale", "scale"),
                       ("Charge counter", "charge_counter_uah"),
                       ("temperature", "temperature_tenths_c")):
        match = re.search(rf"^\s*{label}:\s*(-?\d+)\s*$", text, re.MULTILINE)
        if match:
            values[key] = int(match[1])
    for source in ("AC", "USB", "Wireless", "Dock"):
        match = re.search(rf"^\s*{source} powered:\s*(true|false)\s*$", text, re.MULTILINE)
        if match:
            values[source.lower() + "_powered"] = match[1] == "true"
    return values


def battery_usage(text, uid):
    partial_ms, wakeups, found = 0, None, False
    try:
        for row in csv.reader(text.splitlines()):
            if len(row) < 5 or row[1:3] != [str(uid), "l"]:
                continue
            if row[3] == "wl":
                marker = row.index("p", 5)
                value = int(row[marker - 1])
                if value < 0:
                    return None
                partial_ms += value
                found = True
            if row[3] == "apk" and len(row) > 5 and row[5] == PACKAGE:
                value = int(row[4])
                if value < 0:
                    return None
                # APK wakeups repeat per service in the same package.
                wakeups = max(wakeups or 0, value)
    except (ValueError, csv.Error):
        return None
    return {"partial_ms": partial_ms if found else None, "apk_wakeups": wakeups}


def process_sample(adb):
    pid = adb.read("pid", "pidof", PACKAGE).strip()
    if not pid.isdecimal():
        return None
    fields = adb.read("cpu", "cat", f"/proc/{pid}/stat").rsplit(") ", 1)
    try:
        stat = fields[1].split()
        ticks, started = int(stat[11]) + int(stat[12]), int(stat[19])
    except (IndexError, ValueError):
        return None
    return {"pid": int(pid), "started_ticks": started, "ticks": ticks,
            "sample_monotonic": time.monotonic()}


def snapshot(adb, uid):
    cpu = process_sample(adb)
    network = network_totals(adb.read("network", "dumpsys", "netstats", "detail"), uid)
    usage = battery_usage(adb.read("wakelocks", "dumpsys", "batterystats", "--checkin"), uid)
    battery = battery_values(adb.read("battery", "dumpsys", "battery"))
    power = adb.read("screen", "dumpsys", "power")
    match = re.search(r"\bmWakefulness=(Awake|Asleep|Dozing|Dreaming)\b", power)
    return {"cpu": cpu, "network": network, "usage": usage, "battery": battery,
            "screen_observed": match[1] if match else "unavailable"}


def counter_delta(before, after, keys):
    if before is None or after is None or any(before.get(k) is None or after.get(k) is None for k in keys):
        return None
    result = {key: after[key] - before[key] for key in keys}
    return result if all(value >= 0 for value in result.values()) else None


def summarize_cpu(before, after, ticks_per_second):
    if not before or not after:
        return unavailable("Android denied process counters or Mosh was not running")
    if (before["pid"], before["started_ticks"]) != (after["pid"], after["started_ticks"]):
        return unavailable("Mosh process restarted during measurement")
    elapsed = after["sample_monotonic"] - before["sample_monotonic"]
    ticks = after["ticks"] - before["ticks"]
    if ticks < 0 or elapsed <= 0 or ticks_per_second <= 0:
        return unavailable("Process counter reset or unsupported clock frequency")
    return {"status": "available", "scope": "main-process-one-core-percent",
            "delta_ticks": ticks, "clock_ticks_per_second": ticks_per_second,
            "elapsed_seconds": elapsed, "cpu_ms": ticks * 1000 / ticks_per_second,
            "one_core_percent": ticks * 100 / ticks_per_second / elapsed}


def summarize(before, after, ticks_per_second):
    network = counter_delta(before["network"], after["network"], NETWORK_FIELDS)
    partial = counter_delta(before["usage"], after["usage"], ["partial_ms"])
    wakeups = counter_delta(before["usage"], after["usage"], ["apk_wakeups"])
    result = {"cpu": summarize_cpu(before["cpu"], after["cpu"], ticks_per_second),
              "network": unavailable("UID history absent, denied, malformed or reset"),
              "wakelocks": unavailable("UID partial-wakelock counters absent, denied or reset"),
              "wakeups": unavailable("APK wakeup counters absent, denied or reset"),
              "process_network": unavailable("Nonroot Android exposes UID history, not process traffic"),
              "kernel_wakeups": unavailable("Kernel wakeups cannot be attributed from these nonroot counters")}
    if network is not None:
        result["network"] = {"status": "available", "scope": "uid-history-not-process", "delta": network,
                             "interval_exact": False,
                             "limitation": "Android history may be stale/bucketed; zero does not prove no traffic"}
    if partial is not None:
        result["wakelocks"] = {"status": "available", "scope": "uid-sum-may-overlap",
                               "partial_ms_delta": partial["partial_ms"]}
    if wakeups is not None:
        result["wakeups"] = {"status": "available", "scope": "apk-not-kernel",
                             "apk_wakeups_delta": wakeups["apk_wakeups"]}
    result["battery"] = {"scope": "whole-phone-net-change-not-app-attribution",
                         "status": "available" if before["battery"] and after["battery"] else "unavailable",
                         "before": before["battery"], "after": after["battery"]}
    for key in ("level", "charge_counter_uah"):
        if key in before["battery"] and key in after["battery"]:
            result["battery"][key + "_delta"] = after["battery"][key] - before["battery"][key]
    result["screen_observed"] = {"before": before["screen_observed"], "after": after["screen_observed"]}
    return result
