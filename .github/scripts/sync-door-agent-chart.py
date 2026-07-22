#!/usr/bin/env python3
"""Sync door-agent Helm chart entries from a source index to a target index.

Downloads missing chart archives, preserves existing target entries, and
rewrites chart URLs to the target repository. Only operates on the
`door-agent` entry in the index; other entries are left untouched.

Reconciliation is based on the **target index contents**:
- Any `door-agent` version in the source index that is missing from the target
  index is downloaded and added.
- Any `door-agent-*.tgz` present in the target directory but missing from the
  target index is also added to the index. This handles the case where a chart
  archive was copied in without a matching index entry.
"""

import argparse
import hashlib
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from typing import Optional

import yaml


def parse_version(version: str) -> tuple:
    """Parse a `vX.Y.Z` semver string into a sortable tuple."""
    stripped = version[1:] if version.startswith("v") else version
    parts = stripped.split(".")
    return tuple(int(part) for part in parts)


def load_index(path_or_url: str) -> dict:
    if path_or_url.startswith(("http://", "https://")):
        with urllib.request.urlopen(path_or_url) as response:
            data = response.read()
    else:
        with open(path_or_url, "rb") as f:
            data = f.read()
    return yaml.safe_load(data)


def save_index(index: dict, path: str) -> None:
    with open(path, "w") as f:
        yaml.dump(index, f, default_flow_style=False, sort_keys=False)


def chart_url(version: str, base_url: str) -> str:
    return f"{base_url}/door-agent-{version}.tgz"


def chart_path(version: str, target_dir: str) -> str:
    return os.path.join(target_dir, f"door-agent-{version}.tgz")


def download_file(url: str, dest: str) -> bytes:
    with urllib.request.urlopen(url) as response:
        data = response.read()
    with open(dest, "wb") as f:
        f.write(data)
    return data


def sha256_digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tgz_version(path: str) -> Optional[str]:
    """Extract the version from a door-agent-VERSION.tgz filename."""
    name = os.path.basename(path)
    match = re.fullmatch(r"door-agent-(v[\w.+-]+)\.tgz", name)
    return match.group(1) if match else None


def read_tgz_data(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def sync_door_agent(
    source_index: dict,
    target_index: dict,
    source_url_base: str,
    target_url_base: str,
    target_dir: str,
) -> bool:
    source_entries = source_index.get("entries", {}).get("door-agent", [])
    target_entries = target_index.setdefault("entries", {}).setdefault("door-agent", [])

    target_versions = {entry["version"] for entry in target_entries}
    changed = False

    # 1. Add entries that exist in source but are missing from target index.
    for source_entry in source_entries:
        version = source_entry["version"]
        if version in target_versions:
            continue

        os.makedirs(target_dir, exist_ok=True)
        dest_path = chart_path(version, target_dir)

        if not os.path.exists(dest_path):
            source_url = chart_url(version, source_url_base)
            data = download_file(source_url, dest_path)
        else:
            data = read_tgz_data(dest_path)

        new_entry = dict(source_entry)
        new_entry["urls"] = [chart_url(version, target_url_base)]
        new_entry["digest"] = sha256_digest(data)

        target_entries.append(new_entry)
        target_versions.add(version)
        changed = True

    # 2. Add entries for tgz files present locally but missing from target index.
    if os.path.isdir(target_dir):
        for filename in sorted(os.listdir(target_dir)):
            version = tgz_version(filename)
            if not version or version in target_versions:
                continue

            dest_path = os.path.join(target_dir, filename)
            data = read_tgz_data(dest_path)

            # Try to inherit metadata from a matching source entry; otherwise build
            # the minimal entry from the chart archive itself.
            source_entry = next(
                (e for e in source_entries if e["version"] == version),
                None,
            )
            if source_entry:
                new_entry = dict(source_entry)
            else:
                # Minimal fallback that lets Helm clients install the chart. The
                # chart archive metadata will be used by `helm repo index` later
                # if the caller runs it, but this keeps the index self-consistent.
                new_entry = {
                    "apiVersion": "v2",
                    "appVersion": version,
                    "name": "door-agent",
                    "type": "application",
                    "version": version,
                }

            new_entry["urls"] = [chart_url(version, target_url_base)]
            new_entry["digest"] = sha256_digest(data)
            if "created" not in new_entry:
                new_entry["created"] = datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )

            target_entries.append(new_entry)
            target_versions.add(version)
            changed = True

    target_entries.sort(key=lambda e: parse_version(e["version"]), reverse=True)
    if changed:
        target_index["generated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync door-agent chart entries.")
    parser.add_argument("--source-index", required=True, help="URL or path to source index.yaml")
    parser.add_argument("--target-index", required=True, help="Path to target index.yaml")
    parser.add_argument("--source-url-base", required=True, help="Base URL for source chart archives")
    parser.add_argument("--target-url-base", required=True, help="Base URL for target chart archives")
    parser.add_argument("--target-dir", required=True, help="Directory to store downloaded archives")
    args = parser.parse_args()

    try:
        target_index = load_index(args.target_index)
    except FileNotFoundError:
        target_index = {"apiVersion": "v1", "entries": {}}

    source_index = load_index(args.source_index)

    changed = sync_door_agent(
        source_index,
        target_index,
        args.source_url_base,
        args.target_url_base,
        args.target_dir,
    )

    save_index(target_index, args.target_index)

    print(f"changed={changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
