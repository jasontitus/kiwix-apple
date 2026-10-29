#!/usr/bin/env python3
# This file is part of Kiwix for iOS & macOS.
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the small offline UI/import fixture with stock python-libzim.

Install python-libzim (`python -m pip install libzim`) and run this script.
The generated archive UUID may change; tests read it from the real metadata.
The fixture contains only original test content and requires no network assets.
"""

import json
from pathlib import Path

from libzim.writer import Compression, Creator, Hint, Item, StringProvider


class Page(Item):
    def __init__(self, path, title, content):
        super().__init__()
        self.path = path
        self.title = title
        self.content = content

    def get_path(self):
        return self.path

    def get_title(self):
        return self.title

    def get_mimetype(self):
        return "text/html"

    def get_contentprovider(self):
        return StringProvider(self.content)

    def get_hints(self):
        return {Hint.FRONT_ARTICLE: True}


def main():
    output = Path(__file__).with_name("streetzim-demo.zim")
    metadata = {
        "Name": "osm_en_testland",
        "Title": "StreetZim Demo",
        "Description": "Small offline map fixture for Kiwix integration tests",
        "Language": "eng",
        "Creator": "Kiwix test suite",
        "Publisher": "Kiwix test suite",
        "Date": "2026-01-01",
        "License": "GPL-3.0-or-later",
        "Tags": "maps;osm;offline",
        "Category": "other",
    }
    with Creator(output).config_compression(Compression.zstd).config_indexing(False, "eng") as creator:
        for name, value in metadata.items():
            creator.add_metadata(name, value)
        creator.add_item(Page("index.html", "StreetZim test map", """<!doctype html>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>StreetZim test map</title><h1>StreetZim test map</h1>
<p>This map is stored entirely in the local ZIM archive.</p>
<svg viewBox="0 0 320 160" role="img" aria-label="Testland map">
<path d="M20 130L45 30L160 15L290 55L265 145Z" fill="#ddebd2" stroke="#48683a"/>
<path d="M45 100L140 75L265 100M140 75L170 20" fill="none" stroke="#d98439" stroke-width="5"/>
<text x="120" y="120">Testland</text></svg>
<p><a href="detail.html">Fixture detail</a></p>
"""))
        creator.add_item(Page("detail.html", "StreetZim fixture detail", """<!doctype html>
<meta charset="utf-8"><title>StreetZim fixture detail</title>
<h1>StreetZim fixture detail</h1><p>Navigation inside the saved map works offline.</p>
<a href="index.html">Back to map</a>
"""))
        creator.set_mainpath("index.html")
    write_catalog(output)


def write_catalog(output):
    with output.open("rb") as archive:
        archive.seek(-16, 2)
        checksum = archive.read(16).hex()
    size = output.stat().st_size
    catalog = {
        "format": "streetzim-build-index/1",
        "regions": [{
            "id": identifier, "title": title,
            "base": {
                "file": output.name, "size": size,
                "download": "https://streetzim-test.invalid/base.zim",
            },
            "menu": [{
                "lang": code, "label": label, "name": "osm_" + code + "_" + identifier,
                "recipe": "recipes/" + identifier + "/" + code + ".json",
                "size": size, "download_bytes": 0, "md5": checksum,
            } for code, label in [("en", "English"), ("fr", "Français")]],
        } for identifier, title in [
            ("testland", "Testland"),
            ("washington-dc", "Washington, D.C."),
            ("iceland", "Iceland"),
            ("baltics", "Baltics"),
        ]],
    }
    output.with_name("streetzim-demo-index.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(output)


if __name__ == "__main__":
    main()
