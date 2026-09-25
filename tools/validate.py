#!/usr/bin/env python3
"""Credential-free bundle layout checks; Houston performs full policy validation."""
import json
import pathlib
import re
import struct

root = pathlib.Path(__file__).resolve().parents[1]
count = 0
for directory in sorted((root / "connectors").iterdir()):
    if not directory.is_dir():
        continue
    manifest = json.loads((directory / "houston.json").read_text())
    slug = manifest["id"]
    assert slug == directory.name and re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", slug), directory
    assert manifest["schema_version"] == 1, slug
    for field in ("name", "description", "module"):
        assert isinstance(manifest[field], str) and manifest[field].strip(), (slug, field)
    module = pathlib.PurePosixPath(manifest["module"])
    assert not module.is_absolute() and ".." not in module.parts, slug
    assert module.suffix in (".lua", ".luau"), slug
    source = directory.joinpath(*module.parts)
    assert source.is_file() and not source.is_symlink() and source.read_text().strip(), slug
    assert manifest["auth"]["type"] in ("secret", "oauth2"), slug
    assert manifest["proxy"]["protocol"] in ("http", "postgres", "mysql", "clickhouse"), slug
    assert manifest["access"] and all(mode["id"] in ("read-only", "read-write") for mode in manifest["access"]), slug
    if manifest["auth"]["type"] == "oauth2":
        assert manifest["publisher_id"] and manifest["auth"]["oauth"]["registration_id"], slug
    for forbidden in ("client_secret", "access_token", "refresh_token"):
        assert forbidden not in manifest["auth"], (slug, forbidden)
        assert forbidden not in manifest["auth"].get("oauth", {}), (slug, forbidden)
    tests = list((directory / "tests").iterdir())
    assert tests, slug
    for test in tests:
        assert test.suffix in (".lua", ".luau") and test.is_file() and not test.is_symlink(), test
        assert test.read_text().strip(), test
    if manifest.get("icon"):
        assert manifest["icon"] == "icon.png", slug
        image = (directory / "icon.png").read_bytes()
        assert image[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack(">II", image[16:24]) == (1024, 1024), slug
    count += 1
assert count, "empty connector catalog"
print(f"{count} connector bundle layouts validated")
