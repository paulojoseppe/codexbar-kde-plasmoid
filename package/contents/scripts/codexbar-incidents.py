#!/usr/bin/env python3
"""Fetch recent OpenAI and Anthropic status incidents as compact JSON."""

from __future__ import annotations

import email.utils
import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

FEEDS = (
    ("OpenAI", "https://status.openai.com/feed.rss"),
    ("Claude", "https://status.claude.com/history.rss"),
)
MAX_ITEMS = 12
CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    / "codexbar-waybar"
    / "incidents.json"
)


def text(node: ET.Element, *names: str) -> str:
    for name in names:
        child = node.find(name)
        if child is not None and child.text:
            return " ".join(child.text.split())
    return ""


def entry_link(node: ET.Element) -> str:
    link = text(node, "link")
    if link:
        return link
    atom_link = node.find("{http://www.w3.org/2005/Atom}link")
    return atom_link.attrib.get("href", "") if atom_link is not None else ""


def timestamp(value: str) -> float:
    if not value:
        return 0
    try:
        parsed = email.utils.parsedate_to_datetime(value)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.timestamp()
    except (TypeError, ValueError):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            return 0


def fetch_feed(source: str, url: str) -> list[dict[str, str | float]]:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "CodexBar-KDE/1.0 (+https://github.com/steipete/CodexBar)"},
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        root = ET.fromstring(response.read())

    nodes = root.findall(".//item")
    if not nodes:
        nodes = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    incidents = []
    for node in nodes:
        title = text(node, "title", "{http://www.w3.org/2005/Atom}title")
        published = text(
            node,
            "pubDate",
            "published",
            "updated",
            "{http://www.w3.org/2005/Atom}published",
            "{http://www.w3.org/2005/Atom}updated",
        )
        if not title:
            continue
        incidents.append(
            {
                "source": source,
                "title": title,
                "published": published,
                "link": entry_link(node),
                "sort": timestamp(published),
            }
        )
    return incidents


def load_cache() -> dict:
    try:
        return json.loads(CACHE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"items": [], "error": ""}


def main() -> int:
    incidents = []
    errors = []
    for source, url in FEEDS:
        try:
            incidents.extend(fetch_feed(source, url))
        except Exception as exc:  # Network/parser failures should preserve cached UI.
            errors.append(f"{source}: {exc}")

    if not incidents:
        cached = load_cache()
        cached["error"] = "; ".join(errors) or cached.get("error", "")
        print(json.dumps(cached, ensure_ascii=False))
        return 0

    incidents.sort(key=lambda item: float(item.get("sort", 0)), reverse=True)
    for incident in incidents:
        incident.pop("sort", None)

    payload = {
        "items": incidents[:MAX_ITEMS],
        "error": "; ".join(errors),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    }
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(payload, ensure_ascii=False))
    except OSError:
        pass

    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
