#!/usr/bin/env python3
"""Remove old ShaaenFCT releases and completed publishing runs; preserve Git tags."""

import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REPOSITORY = "NLshaen/ShaaenFCT"
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
PUBLISH_RE = re.compile(r"^Publish\s+ShaaenFCT(?:\s+v\d+\.\d+\.\d+)?$", re.I)
RELEASE_NAME_RE = re.compile(r"^shaaenFCT[\s_-]*v?\d+\.\d+\.\d+$", re.I)
MAX_PAGES = 30


def api_request(token, endpoint, method="GET"):
    request = Request(
        f"https://api.github.com/repos/{REPOSITORY}/{endpoint}",
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ShaaenFCT-Release-Cleanup",
        },
    )
    with urlopen(request, timeout=30) as response:
        if method == "DELETE":
            return None
        return json.load(response)


def paginated(token, endpoint, key=None):
    items = []
    for page in range(1, MAX_PAGES + 1):
        delimiter = "&" if "?" in endpoint else "?"
        data = api_request(
            token, f"{endpoint}{delimiter}{urlencode({'per_page': 100, 'page': page})}"
        )
        chunk = data[key] if key else data
        if not isinstance(chunk, list):
            raise ValueError("GitHub response is not a list")
        items.extend(chunk)
        if len(chunk) < 100:
            return items
    raise RuntimeError("Listing exceeds safety limit; no deletions made")


def parse_keep(name, default):
    try:
        keep = int(os.environ.get(name, str(default)))
    except ValueError:
        sys.exit(f"{name} must be an integer between 1 and 100")
    if not 1 <= keep <= 100:
        sys.exit(f"{name} must be between 1 and 100")
    return keep


def eligible_releases(items):
    matching = []
    for release in items:
        match = TAG_RE.fullmatch(release.get("tag_name") or "")
        if not match or release.get("draft") or release.get("prerelease"):
            continue
        if not RELEASE_NAME_RE.fullmatch(release.get("name") or ""):
            continue
        matching.append((tuple(map(int, match.groups())), release))
    return [entry for _, entry in sorted(matching, key=lambda x: x[0], reverse=True)]


def eligible_runs(items):
    result = [
        run for run in items
        if run.get("status") == "completed" and
        PUBLISH_RE.fullmatch(run.get("name") or "")
    ]
    return sorted(
        result, key=lambda run: (run.get("created_at") or "", run["id"]), reverse=True
    )


def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        sys.exit("Unexpected GitHub repository, refusing cleanup")
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        sys.exit("Missing GH_TOKEN")
    keep_releases = parse_keep("KEEP_RELEASES", 3)
    keep_runs = parse_keep("KEEP_PUBLISH_RUNS", 5)
    dry_run = os.environ.get("DRY_RUN", "false").lower() in ("true", "yes", "1")
    current_tag = os.environ.get("RELEASE_TAG", "").strip()

    try:
        # Fetch complete inventories BEFORE any deletion to avoid partial cleanup.
        releases = eligible_releases(paginated(token, "releases"))
        runs = eligible_runs(paginated(token, "actions/runs", "workflow_runs"))
        old_releases = [
            rel for rel in releases[keep_releases:] if rel["tag_name"] != current_tag
        ]
        old_runs = runs[keep_runs:]
        print(f"Keeping {min(len(releases), keep_releases)} releases and "
              f"{min(len(runs), keep_runs)} completed Publish runs")
        print("DRY RUN (no deletions)" if dry_run else "LIVE CLEANUP")
        for rel in old_releases:
            print(f"{'Would delete' if dry_run else 'Deleting'} Release {rel['tag_name']} "
                  "(Git tag preserved)")
            if not dry_run:
                api_request(token, f"releases/{rel['id']}", "DELETE")
        for run in old_runs:
            print(f"{'Would delete' if dry_run else 'Deleting'} "
                  f"workflow run {run['id']} ({run['name']})")
            if not dry_run:
                api_request(token, f"actions/runs/{run['id']}", "DELETE")
        print(f"Cleanup completed: {len(old_releases)} releases and "
              f"{len(old_runs)} runs {'identified' if dry_run else 'deleted'}")
    except HTTPError as exc:
        sys.exit(f"GitHub API error while cleaning: HTTP {exc.code}")
    except URLError as exc:
        sys.exit(f"GitHub connection error while cleaning: {exc.reason}")


if __name__ == "__main__":
    main()
