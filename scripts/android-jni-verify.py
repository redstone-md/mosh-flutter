#!/usr/bin/env python3
"""Check native-only JNI Zero entry points in the final APK, after R8."""
import argparse
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


REQUIRED = {
    "org.jni_zero.JniZero": (
        ("init", "java.lang.Object[]", ()),
        ("crashIfMultiplexingMisaligned", "void", ("long", "long")),
    ),
    "org.jni_zero.CommonApis": (
        ("mapToArray", "java.lang.Object[]", ("java.util.Map",)),
        ("arrayToMap", "java.util.Map", ("java.lang.Object[]",)),
    ),
}


def read_classes(apk, dexdump):
    classes = {}
    with zipfile.ZipFile(apk) as archive, tempfile.TemporaryDirectory() as work:
        files = [name for name in archive.namelist()
                 if re.fullmatch(r"classes\d*\.dex", name)]
        if not files:
            raise ValueError("APK contains no DEX files")
        for name in files:
            dex = Path(work, name)
            dex.write_bytes(archive.read(name))
            output = subprocess.check_output([dexdump, "-l", "xml", str(dex)])
            for package in ET.fromstring(output).findall("package"):
                for cls in package.findall("class"):
                    classes[package.attrib["name"] + "." + cls.attrib["name"]] = cls
    return classes


def verify(apk, dexdump):
    classes = read_classes(apk, dexdump)
    for name, required in REQUIRED.items():
        if name not in classes:
            raise ValueError(f"Missing JNI class: {name}")
        methods = {
            (method.attrib["name"], method.attrib["return"],
             tuple(param.attrib["type"] for param in method.findall("parameter")))
            for method in classes[name].findall("method")
            if method.attrib["static"] == "true"
        }
        for method in required:
            if method not in methods:
                raise ValueError(f"Missing JNI method/signature: {name}.{method}")
    print("JNI Zero classes and native-callable method signatures verified in APK DEX.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("--dexdump", required=True)
    args = parser.parse_args()
    try:
        verify(args.apk, args.dexdump)
    except (ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")
