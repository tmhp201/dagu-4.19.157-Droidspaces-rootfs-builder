#!/usr/bin/env python3
"""Regenerate rootfs.json from the assets of one release.

The file keeps the format the Droidspaces app reads when a repository URL is
added, so the release can be consumed without editing the JSON by hand.
"""
import argparse
import hashlib
import json
import os
import re
import sys

METADATA = {
    "name": "Dagu KDE (Debian 13)",
    "distro": "Debian",
    "description": (
        "Debian 13 with KDE Plasma on X11, systemd, Docker and dual-stack "
        "networking for Droidspaces on the Xiaomi Pad 5 Pro 12.4."
    ),
    "author": "dagu-4.19.157-Droidspaces-rootfs-builder",
    "architecture": "aarch64",
    "file": "Dagu-KDE",
}

ASSET_RE = re.compile(
    r"^(?P<file>.+)-Droidspaces-rootfs-(?P<arch>[^-]+)-(?P<date>\d{8})-(?P<version>.+)\.tar\.xz$"
)


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--assets", required=True, help="directory holding the release tarballs")
    ap.add_argument("--repo", required=True, help="owner/name of the GitHub repository")
    ap.add_argument("--tag", required=True, help="release tag the assets were uploaded to")
    ap.add_argument("--out", default="rootfs.json")
    args = ap.parse_args()

    entries = []
    for name in sorted(os.listdir(args.assets)):
        m = ASSET_RE.match(name)
        if not m:
            continue
        path = os.path.join(args.assets, name)
        entry = dict(METADATA)
        entry.update(
            {
                "download_url": f"https://github.com/{args.repo}/releases/download/{args.tag}/{name}",
                "sha256": digest(path),
                "size_bytes": os.path.getsize(path),
                "version": args.tag,
                "build_date": m.group("date"),
            }
        )
        entries.append(entry)

    if not entries:
        print("no release assets found", file=sys.stderr)
        return 1

    entries.sort(key=lambda e: e["name"])
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2)
        f.write("\n")
    print(f"wrote {args.out} with {len(entries)} entry/entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
