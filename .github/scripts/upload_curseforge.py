#!/usr/bin/env python3
"""Publish one existing GitHub Release ZIP to the CurseForge WoW Upload API.

Required environment:
  GH_TOKEN, GITHUB_REPOSITORY, CURSEFORGE_API_TOKEN,
  CURSEFORGE_PROJECT_ID, CURSEFORGE_GAME_VERSION_IDS
Optional: RELEASE_TAG (default: latest GitHub Release), CURSEFORGE_RELEASE_TYPE

An uploaded marker asset (CurseForge_<tag>.json) prevents ordinary reruns from
uploading the same release again. Reruns after an upload succeeds but before
its marker is uploaded still require manual checking on CurseForge.
"""
import json
import os
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import zipfile

REPO = "NLshaen/ShaaenFCT"
TAG_PATTERN = re.compile(r"^v\d+\.\d+\.\d+$")
VERSION_PATTERN = re.compile(r"(?im)^##\s*Version:\s*v?(\d+\.\d+\.\d+)\s*$")


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()


def gh_json(*args):
    return json.loads(gh(*args))


def get_release(tag=None):
    endpoint = (f"repos/{REPO}/releases/tags/{tag}" if tag
                else f"repos/{REPO}/releases/latest")
    return gh_json("api", endpoint)


def select_asset(release, tag):
    assets = [a for a in release.get("assets", [])
              if a.get("name", "").lower().endswith(".zip")]
    expected = f"ShaaenFCT_{tag}.zip"
    exact = [a for a in assets if a["name"] == expected]
    if len(exact) == 1:
        return exact[0]["name"]
    # Backward compatibility: 0.7.27/28 had a different archive filename.
    if len(assets) == 1 and assets[0]["name"].lower().startswith("shaaenfct_"):
        return assets[0]["name"]
    raise ValueError(
        f"No unambiguous release ZIP. Expected {expected}; "
        f"available: {[a['name'] for a in assets]}"
    )


def game_version_ids(value):
    parts = [p.strip() for p in value.split(",") if p.strip()]
    if not parts or any(not p.isdigit() or int(p) <= 0 for p in parts):
        raise ValueError("CURSEFORGE_GAME_VERSION_IDS must be positive IDs separated by commas")
    return [int(v) for v in parts]


def inspect_archive(path, tag):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Invalid ZIP member: {bad}")
        toc = archive.read("shaaenFCT/shaaenFCT.toc").decode("utf-8-sig")
    match = VERSION_PATTERN.search(toc)
    if not match or "v" + match.group(1) != tag:
        raise ValueError(f"Archive TOC does not match tag {tag}")


def make_metadata(release, ids, tag, release_type):
    if release_type not in {"release", "beta", "alpha"}:
        raise ValueError("CURSEFORGE_RELEASE_TYPE must be release, beta, or alpha")
    return {
        "changelog": (release.get("body") or f"ShaaenFCT {tag}").strip(),
        "changelogType": "markdown",
        "displayName": f"ShaaenFCT_{tag}",
        "gameVersions": ids,
        "releaseType": release_type,
    }


def main():
    if os.environ.get("GITHUB_REPOSITORY", REPO) != REPO:
        raise ValueError("Refusing to upload for another repository")

    tag = os.environ.get("RELEASE_TAG", "").strip() or None
    if tag and not TAG_PATTERN.fullmatch(tag):
        raise ValueError("RELEASE_TAG must have the form vX.Y.Z")

    release = get_release(tag)
    tag = release["tag_name"]
    if not TAG_PATTERN.fullmatch(tag):
        raise ValueError(f"Invalid release tag: {tag}")
    if release.get("draft") or release.get("prerelease"):
        print(f"Skipping draft or prerelease {tag}")
        return

    # Scheduled fallback only processes newly published releases, not older
    # unmarked releases that predate enabling the automatic workflow.
    max_age_value = os.environ.get("RELEASE_MAX_AGE_HOURS", "").strip()
    if max_age_value:
        if not max_age_value.isdigit() or int(max_age_value) <= 0:
            raise ValueError("RELEASE_MAX_AGE_HOURS must be a positive integer")
        published_at = release.get("published_at")
        if not published_at:
            raise ValueError("GitHub Release has no published_at timestamp")
        published = datetime.fromisoformat(published_at.replace("Z", "+00:00"))
        age_seconds = (datetime.now(timezone.utc) - published).total_seconds()
        if age_seconds > int(max_age_value) * 3600:
            print(f"Skipping old GitHub Release {tag} (published more than "
                  f"{max_age_value} hours ago)")
            return

    marker_name = f"CurseForge_{tag}.json"
    if any(a["name"] == marker_name for a in release.get("assets", [])):
        print(f"Already uploaded {tag} to CurseForge (marker exists); skipping.")
        return

    archive_name = select_asset(release, tag)
    token = os.environ.get("CURSEFORGE_API_TOKEN", "").strip()
    project_id = os.environ.get("CURSEFORGE_PROJECT_ID", "").strip()
    version_ids = game_version_ids(os.environ.get("CURSEFORGE_GAME_VERSION_IDS", ""))
    release_type = os.environ.get("CURSEFORGE_RELEASE_TYPE", "release").strip() or "release"
    if not token:
        raise ValueError("Missing GitHub Actions secret CURSEFORGE_API_TOKEN")
    if not project_id.isdigit() or int(project_id) <= 0:
        raise ValueError("CURSEFORGE_PROJECT_ID must be a positive numeric project ID")

    metadata = make_metadata(release, version_ids, tag, release_type)
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        gh("release", "download", tag, "--repo", REPO,
           "--pattern", archive_name, "--dir", str(root))
        zip_path = root / archive_name
        if not zip_path.is_file() or zip_path.stat().st_size == 0:
            raise RuntimeError("Release ZIP download is empty or missing")
        inspect_archive(zip_path, tag)

        # Auth goes only to wow.curseforge.com; curl never prints the API token.
        upload = subprocess.run(
            ["curl", "--silent", "--show-error", "--fail-with-body",
             "--request", "POST", "--max-time", "180",
             "--header", f"X-Api-Token: {token}",
             "--form-string", "metadata=" + json.dumps(metadata, ensure_ascii=False),
             "--form", f"file=@{zip_path};type=application/zip",
             f"https://wow.curseforge.com/api/projects/{project_id}/upload-file"],
            text=True, capture_output=True,
        )
        if upload.returncode != 0:
            raise RuntimeError(
                "CurseForge upload failed; check the token, project ID, WoW "
                "game-version IDs and Actions logs. HTTP body: " + upload.stdout[:500]
            )
        try:
            result = json.loads(upload.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError("CurseForge did not return valid JSON") from exc
        file_id = result.get("id")
        if not isinstance(file_id, int) or file_id <= 0:
            raise RuntimeError("CurseForge upload response missing a valid file ID")

        marker_path = root / marker_name
        marker_path.write_text(json.dumps({
            "tag": tag, "curseforgeProjectId": int(project_id),
            "curseforgeFileId": file_id,
            "sourceRelease": release.get("html_url"),
        }, indent=2) + "\n", encoding="utf-8")
        gh("release", "upload", tag, str(marker_path), "--repo", REPO)
        print(f"Published {tag} on CurseForge as project {project_id}, file {file_id}.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError, KeyError, zipfile.BadZipFile) as exc:
        print(f"CurseForge publishing error: {exc}", file=sys.stderr)
        sys.exit(1)
