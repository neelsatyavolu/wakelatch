"""Fills Wakelatch's App Store listing through the App Store Connect API.

Usage: ASC_KEY_DIR=<dir> python3 -I scripts/asc_listing.py <version> [build-number]
Reads text from docs/appstore.md and screenshots from .impeccable/review/release/*.png.
Never prints keys or tokens. Prints one line per step.
"""
import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc import call  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "co.xanom.wakelatch"
SHOTS = ["2-tomorrow", "4-ringing", "5-challenge", "3-picker", "6-released", "7-night", "1-onboarding"]


def ok(status, data, what):
    if status >= 300:
        sys.exit(f"error: {what}: {status} {json.dumps(data.get('errors', data))[:600]}")
    return data


def get(path, what):
    return ok(*call("GET", path), what)["data"]


def section(md, name):
    m = re.search(rf"^## {re.escape(name)}[^\n]*\n(.*?)(?=^## |\Z)", md, re.S | re.M)
    return m.group(1).strip() if m else ""


def listing():
    md = (ROOT / "docs/appstore.md").read_text()
    urls = dict(re.findall(r"- (\w[\w ]*): (\S+)", section(md, "URLs")))
    return {
        "subtitle": section(md, "Subtitle"),
        "promo": section(md, "Promotional text"),
        "keywords": section(md, "Keywords"),
        "description": section(md, "Description"),
        "notes": section(md, "Review notes"),
        "support": urls["Support"],
        "marketing": urls["Marketing"],
        "privacy": urls["Privacy policy"],
    }


def main():
    version = sys.argv[1]
    build_number = sys.argv[2] if len(sys.argv) > 2 else None
    text = listing()
    app = get(f"/v1/apps?filter%5BbundleId%5D={BUNDLE_ID}", "find app")[0]
    app_id = app["id"]
    print(f"app {app_id}")

    ok(*call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id, "attributes": {
        "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}}), "content rights")
    print("content rights set")

    infos = get(f"/v1/apps/{app_id}/appInfos", "app infos")
    info = next((i for i in infos if i["attributes"].get("appStoreState") != "READY_FOR_SALE"), infos[0])
    info_id = info["id"]
    ok(*call("PATCH", f"/v1/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "UTILITIES"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}}}}}), "categories")
    print("categories set")

    loc = get(f"/v1/appInfos/{info_id}/appInfoLocalizations", "app info localizations")[0]
    ok(*call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {
        "type": "appInfoLocalizations", "id": loc["id"],
        "attributes": {"subtitle": text["subtitle"], "privacyPolicyUrl": text["privacy"]}}}), "subtitle")
    print("subtitle and privacy URL set")

    status, data = call("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration")
    rating = ok(status, data, "age rating")["data"]
    attrs = {k: ("NONE" if isinstance(v, str) else False) for k, v in rating["attributes"].items()
             if isinstance(v, (str, bool)) and k not in ("kidsAgeBand", "koreaAgeRatingOverride", "ageRatingOverride")}
    ok(*call("PATCH", f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {
        "type": "ageRatingDeclarations", "id": rating["id"], "attributes": attrs}}), "age rating")
    print("age rating set (all none)")

    versions = get(f"/v1/apps/{app_id}/appStoreVersions?filter%5Bplatform%5D=IOS", "versions")
    editable = [v for v in versions if v["attributes"]["appStoreState"] in
                ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
    if editable:
        ver = editable[0]
        if ver["attributes"]["versionString"] != version:
            ok(*call("PATCH", f"/v1/appStoreVersions/{ver['id']}", {"data": {
                "type": "appStoreVersions", "id": ver["id"], "attributes": {"versionString": version}}}), "version string")
    else:
        ver = ok(*call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}), "create version")["data"]
    ver_id = ver["id"]
    ok(*call("PATCH", f"/v1/appStoreVersions/{ver_id}", {"data": {"type": "appStoreVersions", "id": ver_id,
        "attributes": {"releaseType": "MANUAL", "copyright": "2026 Wakelatch contributors"}}}), "release type")
    print(f"version {version} ({ver_id}), manual release")

    vloc = get(f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations", "version localizations")[0]
    ok(*call("PATCH", f"/v1/appStoreVersionLocalizations/{vloc['id']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": vloc["id"], "attributes": {
            "description": text["description"], "keywords": text["keywords"],
            "promotionalText": text["promo"], "supportUrl": text["support"],
            "marketingUrl": text["marketing"]}}}), "description")
    print("description, keywords, URLs set")

    upload_screenshots(vloc["id"])

    if build_number:
        builds = get(f"/v1/builds?filter%5Bapp%5D={app_id}&filter%5Bversion%5D={build_number}", "find build")
        if not builds:
            sys.exit(f"error: build {build_number} not found yet")
        ok(*call("PATCH", f"/v1/appStoreVersions/{ver_id}/relationships/build",
                 {"data": {"type": "builds", "id": builds[0]["id"]}}), "attach build")
        print(f"build {build_number} attached ({builds[0]['attributes']['processingState']})")


def upload_screenshots(vloc_id):
    sets = get(f"/v1/appStoreVersionLocalizations/{vloc_id}/appScreenshotSets", "screenshot sets")
    display = "APP_IPHONE_67"
    shot_set = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display), None)
    if shot_set:
        for old in get(f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots", "old screenshots"):
            call("DELETE", f"/v1/appScreenshots/{old['id']}")
    else:
        shot_set = ok(*call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display},
            "relationships": {"appStoreVersionLocalization": {"data": {
                "type": "appStoreVersionLocalizations", "id": vloc_id}}}}}), "screenshot set")["data"]
    for name in SHOTS:
        path = ROOT / ".impeccable/review/release" / f"{name}.png"
        blob = path.read_bytes()
        shot = ok(*call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": shot_set["id"]}}}}}),
            f"reserve {name}")["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = blob[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
            for h in op.get("requestHeaders", []):
                req.add_header(h["name"], h["value"])
            urllib.request.urlopen(req, timeout=120).read()
        ok(*call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}}), f"commit {name}")
        print(f"screenshot {name} uploaded")


if __name__ == "__main__":
    main()
