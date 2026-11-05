#!/usr/bin/env python3
"""Check the final APK's DEX after R8: JNI Zero and Mosh native entry points
survive, and no proprietary Google SDK is packaged."""
import argparse
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


REQUIRED = {
    "app.mosh.mosh.MoshNative": (
        ("initialize", "void", ("android.content.Context",)),
        ("notifyNetworkChanged", "int", ()),
        ("setTransferExecution", "int", ("java.lang.String", "java.lang.String", "long", "boolean")),
        ("setTransferInteractive", "int", ("boolean",)),
    ),
    "{jni_zero}.JniZero": (
        ("init", "java.lang.Object[]", ()),
        ("crashIfMultiplexingMisaligned", "void", ("long", "long")),
    ),
    "{jni_zero}.CommonApis": (
        ("mapToArray", "java.lang.Object[]", ("java.util.Map",)),
        ("arrayToMap", "java.util.Map", ("java.lang.Object[]",)),
    ),
}

# F-Droid-format repositories (IzzyOnDroid) reject these closed SDKs.
NONFREE = ("com.google.android.gms.", "com.google.mlkit.", "com.google.firebase.")


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


def verify(apk, dexdump, jni_zero):
    classes = read_classes(apk, dexdump)
    nonfree = sorted({name.rsplit(".", 1)[0] for name in classes if name.startswith(NONFREE)})
    if nonfree:
        raise ValueError("Proprietary Google SDK packaged: " + ", ".join(nonfree))
    for template, required in REQUIRED.items():
        name = template.format(jni_zero=jni_zero)
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
    print("JNI Zero and Mosh native-callable method signatures verified in APK DEX; "
          "no proprietary Google SDK packaged.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("--dexdump", required=True)
    # LiveKit's libwebrtc, packaged by the libwebrtc call engine, prefixes it.
    parser.add_argument("--jni-zero-package", default="org.jni_zero")
    args = parser.parse_args()
    try:
        verify(args.apk, args.dexdump, args.jni_zero_package)
    except (ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")
