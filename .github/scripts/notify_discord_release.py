#!/usr/bin/env python3
"""Post a ShaaenFCT GitHub Release and its changelog to a Discord webhook."""

import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

REPOSITORY = "NLshaen/ShaaenFCT"
TAG_PATTERN = re.compile(r"v\d+\.\d+\.\d+")


def get_release(token, tag):
    endpoint = f"releases/tags/{quote(tag)}" if tag else "releases/latest"
    request = Request(
        f"https://api.github.com/repos/{REPOSITORY}/{endpoint}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ShaaenFCT-Discord-Release",
        },
    )
    with urlopen(request, timeout=20) as response:
        return json.load(response)


def discord_payload(release):
    tag = release["tag_name"]
    url = release["html_url"]
    body = re.sub(r"<!--.*?-->", "", release.get("body") or "", flags=re.S).strip()
    if not body:
        body = "Consultez les notes de version sur GitHub."
    if len(body) > 3700:
        shortened = body[:3650].rsplit("\n", 1)[0]
        body = (shortened or body[:3650]).rstrip() + f"\n\n… [Lire le changelog complet]({url})"

    zip_assets = [
        asset for asset in release.get("assets", [])
        if asset.get("name", "").lower().endswith(".zip")
    ]
    downloads = (zip_assets[0]["browser_download_url"] if zip_assets else url)
    embed = {
        "title": f"ShaaenFCT {tag}"[:256],
        "url": url,
        "description": body,
        "color": 0x35B86B,
        "fields": [{
            "name": "Téléchargement",
            "value": f"[📦 Télécharger ShaaenFCT]({downloads})",
            "inline": False,
        }],
        "footer": {"text": "ShaaenFCT • GitHub Releases"},
    }
    if release.get("published_at"):
        embed["timestamp"] = release["published_at"]
    return {
        "username": "ShaaenFCT Releases",
        "allowed_mentions": {"parse": []},
        "embeds": [embed],
    }


def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        sys.exit("Unexpected GitHub repository")
    webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook:
        sys.exit("Missing GitHub Actions secret: DISCORD_WEBHOOK_URL")
    parts = urlsplit(webhook)
    if parts.scheme != "https" or parts.hostname not in {"discord.com", "discordapp.com"} or not parts.path.startswith("/api/webhooks/"):
        sys.exit("DISCORD_WEBHOOK_URL must be a valid Discord HTTPS webhook URL")
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        sys.exit("Missing GH_TOKEN")
    tag = os.environ.get("RELEASE_TAG", "").strip()
    if tag and not TAG_PATTERN.fullmatch(tag):
        sys.exit("RELEASE_TAG must look like v0.7.29")

    try:
        release = get_release(token, tag)
    except HTTPError as error:
        sys.exit(f"GitHub API HTTP error: {error.code}")
    except URLError as error:
        sys.exit(f"GitHub API connection error: {error.reason}")

    if release.get("draft") or release.get("prerelease"):
        print(f"Skipping draft/prerelease {release['tag_name']}")
        return

    payload = json.dumps(discord_payload(release), ensure_ascii=False).encode("utf-8")
    request = Request(
        webhook,
        data=payload,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
            # Discord's HTTP API requires an identifying User-Agent. The
            # default Python-urllib agent can be blocked by Cloudflare (403).
            "User-Agent": "DiscordBot (https://github.com/NLshaen/ShaaenFCT, 1.0.1)",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=20) as response:
            if response.status not in (200, 204):
                sys.exit(f"Unexpected Discord HTTP status {response.status}")
    except HTTPError as error:
        # Show only the HTTP status and Discord's numeric API code: never
        # print the webhook URL/token or untrusted HTML response body.
        response_body = error.read(4096)
        try:
            details = json.loads(response_body)
        except (ValueError, UnicodeDecodeError):
            details = {}
        discord_code = details.get("code") if isinstance(details, dict) else None
        if isinstance(discord_code, int):
            sys.exit(f"Discord HTTP error: {error.code} (Discord API code: {discord_code})")
        if error.code == 403:
            sys.exit("Discord HTTP error: 403 (non-JSON response; possible Cloudflare block)")
        sys.exit(f"Discord HTTP error: {error.code}")
    except URLError as error:
        sys.exit(f"Discord connection error: {error.reason}")

    print(f"Posted {release['tag_name']} changelog to Discord")


if __name__ == "__main__":
    main()
