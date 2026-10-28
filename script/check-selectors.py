#!/usr/bin/env python3
"""Check the deployment manifest against the pinned compiler's method identifiers."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "config/selectors.json").read_text())
facets = {p.stem for p in (root / "src/facets").glob("*.sol")}
assert set(manifest) == facets, "manifest facet set differs from production facets"
seen = {}
for facet, names in manifest.items():
    artifact = json.loads((root / f"out/{facet}.sol/{facet}.json").read_text())
    methods = artifact["methodIdentifiers"]
    assert len(names) == len(set(names)), f"duplicate method name in {facet}"
    assert set(names) == {sig.split("(", 1)[0] for sig in methods}, f"missing or stale method in {facet}"
    for signature, selector in methods.items():
        assert selector not in seen, f"selector collision: {signature} and {seen[selector]}"
        seen[selector] = signature
print(f"Verified {len(facets)} facets and {len(seen)} unique selectors")
