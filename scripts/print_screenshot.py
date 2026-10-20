"""Print one exported XCTest screenshot as base64 so it can be read from a job log.

Used only on manually dispatched iOS runs; artifacts remain the normal route.
Usage: python3 scripts/print_screenshot.py <TestAttachments dir> <attachment name prefix>
"""
from pathlib import Path
import base64
import json
import subprocess
import sys
import textwrap

folder, prefix = Path(sys.argv[1]), sys.argv[2]


def files(node):
    if isinstance(node, dict):
        if "exportedFileName" in node and any(isinstance(v, str) and v.startswith(prefix) for v in node.values()):
            yield node["exportedFileName"]
        for value in node.values():
            yield from files(value)
    elif isinstance(node, list):
        for value in node:
            yield from files(value)


manifest = folder / "manifest.json"
if not manifest.exists():
    sys.exit(f"No manifest in {folder}")
for name in files(json.loads(manifest.read_text())):
    small = Path("/tmp") / "orbit-screenshot.jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "900",
                    str(folder / name), "--out", str(small)], check=True, capture_output=True)
    print("BEGIN_SCREENSHOT " + prefix)
    print("\n".join(textwrap.wrap(base64.b64encode(small.read_bytes()).decode(), 4000)))
    print("END_SCREENSHOT")
    break
else:
    sys.exit(f"No attachment named {prefix!r}")
