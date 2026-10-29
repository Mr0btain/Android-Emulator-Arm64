#!/usr/bin/env python3
"""Install an Android system image into the SDK without sdkmanager.

sdkmanager enforces each image's minimum emulator revision and would replace
our native emulator with Google's x86-64 one to satisfy it. This unpacks an
already downloaded (and checksum-verified) image zip and writes the same
package.xml sdkmanager would, so avdmanager and the IDE see it as installed.

usage: install-sysimg.py <sys-img2-N.xml> <package path> <image.zip>
  e.g. install-sysimg.py out/sysimg/gapis.xml \
         'system-images;android-37.0;google_apis;arm64-v8a' out/sysimg/arm64-v8a-37.0_r08.zip
"""
import hashlib
import os
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

COMMON = "http://schemas.android.com/repository/android/common/02"
XSI = "http://www.w3.org/2001/XMLSchema-instance"


def main(index, path, archive):
    sdk = os.environ.get("ANDROID_HOME") or os.path.expanduser("~/Android/Sdk")
    root = ET.parse(index).getroot()
    pkg = next((p for p in root.iter("remotePackage") if p.get("path") == path), None)
    if pkg is None:
        sys.exit(f"{path} not in {index}")

    want = pkg.findtext("archives/archive/complete/checksum")
    sha1 = hashlib.sha1()
    with open(archive, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            sha1.update(chunk)
    if sha1.hexdigest() != want:
        sys.exit(f"checksum mismatch: {sha1.hexdigest()} != {want}")

    dest = os.path.join(sdk, *path.split(";"))
    if os.path.exists(dest):
        sys.exit(f"{dest} already exists; remove it first")

    # The zip holds a single top-level directory (e.g. arm64-v8a/).
    with tempfile.TemporaryDirectory(dir=sdk) as tmp:
        with zipfile.ZipFile(archive) as z:
            z.extractall(tmp)
        (top,) = os.listdir(tmp)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(os.path.join(tmp, top), dest)

    # remotePackage -> localPackage: same type-details/revision/display-name,
    # no archives or channel; keep the license it references.
    lic_id = pkg.find("uses-license").get("ref")
    lic = next(l for l in root.iter("license") if l.get("id") == lic_id)
    out = ET.Element(f"{{{COMMON}}}repository")
    # type-details carries xsi:type="sys-img:sysImgDetailsType"; that prefix
    # only appears inside an attribute value, so declare it by hand.
    ET.register_namespace("xsi", XSI)
    ET.register_namespace("common", COMMON)
    for prefix, uri in (("sys-img", root.tag[1:].split("}")[0]),):
        out.set(f"xmlns:{prefix}", uri)
    out.append(lic)
    local = ET.SubElement(out, "localPackage", path=path, obsolete="false")
    # No <dependencies>: the emulator min-revision would make the IDE offer to
    # "update" our native emulator to Google's x86-64 one.
    for tag in ("type-details", "revision", "display-name", "uses-license"):
        el = pkg.find(tag)
        if el is not None:
            local.append(el)
    ET.ElementTree(out).write(os.path.join(dest, "package.xml"),
                              encoding="UTF-8", xml_declaration=True)
    print(f"installed {path} r{pkg.findtext('revision/major')} -> {dest}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
