#!/usr/bin/env python3
"""Keep the version in README.md synchronized with the addon TOC."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
toc = (root / "shaaenFCT.toc").read_text(encoding="utf-8")
match = re.search(r"(?im)^##\s*Version:\s*v?(\d+\.\d+\.\d+)\s*$", toc)
if not match:
    raise SystemExit("Cannot find a valid ## Version in shaaenFCT.toc")

version = match.group(1)
readme_path = root / "README.md"
readme = readme_path.read_text(encoding="utf-8")
updated, replacements = re.subn(
    r"(?m)^Current (?:release|version):[ \t]*\*\*v?\d+\.\d+\.\d+\*\*\.?[ \t]*$",
    f"Current version: **v{version}**.",
    readme,
    count=1,
)
if replacements != 1:
    raise SystemExit("Cannot find Current release/version line in README.md")

updated = re.sub(
    r"(?m)^The original full addon archive is provided separately.*$",
    "Download the latest addon package from [GitHub Releases](https://github.com/NLshaen/ShaaenFCT/releases/latest).",
    updated,
    count=1,
)
if updated != readme:
    readme_path.write_text(updated, encoding="utf-8")
    print(f"README.md updated to v{version}")
else:
    print(f"README.md already matches v{version}")
