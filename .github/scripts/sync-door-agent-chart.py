#!/usr/bin/env python3
"""Sync door-agent Helm chart entries from a source index to a target index.

Downloads missing chart archives, preserves existing target entries, and
rewrites chart URLs to the target repository. Only operates on the
`door-agent` entry in the index; other entries are left untouched.
"""

import argparse
import hashlib
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

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


def download_file(url: str, dest: str) -> bytes:
    with urllib.request.urlopen(url) as response:
        data = response.read()
    with open(dest, "wb") as f:
        f.write(data)
    return data


def sha256_digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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

    for source_entry in source_entries:
        version = source_entry["version"]
        if version in target_versions:
            continue

        os.makedirs(target_dir, exist_ok=True)
        source_url = chart_url(version, source_url_base)
        dest_path = os.path.join(target_dir, f"door-agent-{version}.tgz")

        data = download_file(source_url, dest_path)

        new_entry = dict(source_entry)
        new_entry["urls"] = [chart_url(version, target_url_base)]
        new_entry["digest"] = sha256_digest(data)

        target_entries.append(new_entry)
        target_versions.add(version)
        changed = True

    target_entries.sort(key=lambda e: parse_version(e["version"]), reverse=True)
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
