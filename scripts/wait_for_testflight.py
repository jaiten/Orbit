"""Confirm the exact uploaded build finishes Apple processing without exposing signing material."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def encode(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def raw_signature(der):
    """OpenSSL emits ASN.1 ECDSA signatures; JWT requires fixed-width R || S."""
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError("Unexpected ECDSA signature")
    values, cursor = [], 2
    for _ in range(2):
        if der[cursor] != 2:
            raise ValueError("Unexpected ECDSA integer")
        size = der[cursor + 1]
        value = der[cursor + 2:cursor + 2 + size]
        if not value or len(value) != size or value[0] & 0x80:
            raise ValueError("Invalid ECDSA integer")
        values.append(int.from_bytes(value, "big").to_bytes(32, "big"))
        cursor += 2 + size
    if cursor != len(der):
        raise ValueError("Unexpected trailing signature data")
    return b"".join(values)


def token():
    key_id = os.environ["ASC_KEY_ID"]
    key_path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    now = int(time.time())
    header = encode(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    payload = encode(json.dumps({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    message = f"{header}.{payload}".encode("ascii")
    result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)], input=message, capture_output=True)
    if result.returncode:
        raise RuntimeError("Could not sign the App Store Connect request")
    return message.decode("ascii") + "." + encode(raw_signature(result.stdout))


def get(path, parameters=None):
    query = "?" + urllib.parse.urlencode(parameters) if parameters else ""
    request = urllib.request.Request(API + path + query, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (429, 500, 502, 503, 504):
            return None
        raise RuntimeError(f"App Store Connect processing check failed (HTTP {error.code})") from None
    except (TimeoutError, urllib.error.URLError):
        return None


def await_build(app_id, number, timeout=1200, request=get, sleep=time.sleep, clock=time.monotonic):
    deadline = clock() + timeout
    previous = None
    while clock() < deadline:
        response = request("/builds", {"filter[app]": app_id, "filter[version]": number, "limit": "10"})
        builds = response.get("data", []) if response else []
        build = next((entry for entry in builds if entry.get("attributes", {}).get("version") == number), None)
        state = build.get("attributes", {}).get("processingState") if build else "AWAITING_UPLOAD"
        if state != previous:
            print(f"TestFlight build {number}: {state}", flush=True)
            previous = state
        if state in ("FAILED", "INVALID"):
            raise RuntimeError(f"Apple processing rejected build {number}: {state}")
        if state == "VALID":
            if build["attributes"].get("expired"):
                raise RuntimeError(f"TestFlight build {number} is expired")
            return build
        sleep(min(30, max(0, deadline - clock())))
    raise TimeoutError(f"Apple has not finished processing build {number}; check App Store Connect before distributing it")


def main():
    archive = Path(os.environ["RUNNER_TEMP"]) / "Orbit.xcarchive/Products/Applications/Orbit.app/Info.plist"
    with archive.open("rb") as source:
        info = plistlib.load(source)
    app_response = get("/apps", {"filter[bundleId]": info["CFBundleIdentifier"], "limit": "2"})
    if not app_response or len(app_response.get("data", [])) != 1:
        raise RuntimeError("Could not identify the uploaded Orbit app in App Store Connect")
    app_id = app_response["data"][0]["id"]
    number = str(info["CFBundleVersion"])
    build = await_build(app_id, number)
    try:
        details = get(f"/builds/{build['id']}/buildBetaDetail")
    except RuntimeError:
        details = None  # Processing is already verified; this relationship is optional metadata.
    internal = (details or {}).get("data", {}).get("attributes", {}).get("internalBuildState", "unknown")
    print(f"Apple processing succeeded: Orbit {info['CFBundleShortVersionString']} ({number}); internal TestFlight state: {internal}.")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a") as output:
            output.write(f"\n### TestFlight processing verified\n\nOrbit {info['CFBundleShortVersionString']} ({number}): **VALID**. Internal testing state: **{internal}**.\n\n[Open TestFlight](https://appstoreconnect.apple.com/apps/{app_id}/testflight/ios)\n")


if __name__ == "__main__":
    main()
