#!/usr/bin/env python3
"""Generate ios TnCounties.swift from the Android app's TnCounties.kt.

Reads ~/workspace/checkpoint-app/app/src/main/java/com/checkpointalerts/app/data/TnCounties.kt
and writes ~/workspace/checkpoint-app/ios/CheckpointAlerts/Models/TnCounties.swift
with the same 95 counties and the same Census 2026 adjacency map.
Run again after any change to the Kotlin source; do not hand-edit the Swift output.
"""
import re
import sys

KT = "/home/hatch/workspace/checkpoint-app/app/src/main/java/com/checkpointalerts/app/data/TnCounties.kt"
OUT = "/home/hatch/workspace/checkpoint-app/ios/CheckpointAlerts/Models/TnCounties.swift"

src = open(KT).read()

m = re.search(r"val ALL: List<String> = listOf\((.*?)\)", src, re.S)
all_counties = re.findall(r'"([^"]+)"', m.group(1))

neighbors = {}
for name, members in re.findall(r'"([^"]+)" to setOf\((.*?)\)', src, re.S):
    neighbors[name] = re.findall(r'"([^"]+)"', members)

assert len(all_counties) == 95, f"expected 95 counties, got {len(all_counties)}"
assert len(neighbors) == 95, f"expected 95 neighbor entries, got {len(neighbors)}"
for c in all_counties:
    assert c in neighbors, f"missing neighbors for {c}"

def swift_str_list(items, indent="        "):
    lines = []
    for i in range(0, len(items), 6):
        chunk = items[i:i + 6]
        lines.append(indent + ", ".join(f'"{x}"' for x in chunk) + ",")
    return "\n".join(lines)

out = []
out.append("import Foundation")
out.append("")
out.append("/// Tennessee's 95 counties and their in-state neighbors, from the U.S. Census")
out.append("/// Bureau 2026 County Adjacency File (county_adjacency2026.txt).")
out.append("/// Out-of-state neighbors are not listed, they cannot have Tennessee")
out.append("/// checkpoints, so they are irrelevant to alert scope.")
out.append("/// Generated from the Android app's TnCounties.kt, same data, same source.")
out.append("/// Do not hand-edit: re-run Scripts/generate-counties.py after any change.")
out.append("enum TnCounties {")
out.append("")
out.append("    static let all: [String] = [")
out.append(swift_str_list(all_counties))
out.append("    ]")
out.append("")
out.append("    private static let neighbors: [String: Set<String>] = [")
for name in all_counties:
    members = sorted(neighbors[name])
    out.append(f'        "{name}": [{", ".join(chr(34) + x + chr(34) for x in members)}],')
out.append("    ]")
out.append("")
out.append("    /// The home county plus every county touching it, the")
out.append("    /// \"my county + nearby counties\" alert scope.")
out.append("    static func scopeCounties(homeCounty: String) -> Set<String> {")
out.append("        var result = neighbors[homeCounty] ?? []")
out.append("        result.insert(homeCounty)")
out.append("        return result")
out.append("    }")
out.append("}")
out.append("")

open(OUT, "w").write("\n".join(out))
print(f"wrote {OUT}: {len(all_counties)} counties, {len(neighbors)} neighbor entries")
