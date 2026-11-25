#!/usr/bin/env python3
"""Generate ios CannabisLeaf.swift from the Android app's leaf vector drawable.

Reads ~/workspace/checkpoint-app/app/src/main/res/drawable/ic_cannabis_leaf.xml
(24x24 viewport, 7 serrated leaflets + stem, green #43A047) and writes
~/workspace/checkpoint-app/ios/CheckpointAlerts/Views/CannabisLeaf.swift
as a SwiftUI Shape that draws the same paths, scaled to fit the view.
Run again after any change to the vector; do not hand-edit the Swift output.
"""
import re
import xml.etree.ElementTree as ET

XML = "/home/hatch/workspace/checkpoint-app/app/src/main/res/drawable/ic_cannabis_leaf.xml"
OUT = "/home/hatch/workspace/checkpoint-app/ios/CheckpointAlerts/Views/CannabisLeaf.swift"

NS = {"android": "http://schemas.android.com/apk/res/android"}
tree = ET.parse(XML)
paths = []
for p in tree.getroot().iter("path"):
    paths.append(p.get("{http://schemas.android.com/apk/res/android}pathData"))

assert len(paths) == 8, f"expected 8 paths, got {len(paths)}"

def fmt_num(n):
    if n == int(n):
        return str(int(n))
    return repr(n)

out = []
out.append("import SwiftUI")
out.append("")
out.append("/// The drawn cannabis fan leaf from the Android app: 7 serrated leaflets + stem,")
out.append("/// green #43A047. The Android vector (24x24 viewport) is reproduced here as")
out.append("/// SwiftUI paths, scaled to fit the view.")
out.append("/// Generated from ic_cannabis_leaf.xml by Scripts/generate-leaf.py.")
out.append("struct CannabisLeafShape: Shape {")
out.append("    func path(in rect: CGRect) -> Path {")
out.append("        var path = Path()")
out.append("        let scale = min(rect.width, rect.height) / 24")
out.append("        let dx = rect.minX + (rect.width - 24 * scale) / 2")
out.append("        let dy = rect.minY + (rect.height - 24 * scale) / 2")
out.append("        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {")
out.append("            CGPoint(x: dx + x * scale, y: dy + y * scale)")
out.append("        }")
for pi, d in enumerate(paths):
    out.append(f"        // leaflet {pi + 1}")
    tokens = re.findall(r"[MLZ]|-?\d+(?:\.\d+)?", d)
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "M":
            x, y = float(tokens[i + 1]), float(tokens[i + 2])
            out.append(f"        path.move(to: pt({fmt_num(x)}, {fmt_num(y)}))")
            i += 3
        elif t == "L":
            x, y = float(tokens[i + 1]), float(tokens[i + 2])
            out.append(f"        path.addLine(to: pt({fmt_num(x)}, {fmt_num(y)}))")
            i += 3
        elif t == "Z":
            out.append("        path.closeSubpath()")
            i += 1
        else:
            raise ValueError(f"unexpected token {t} in path {pi + 1}")
out.append("        return path")
out.append("    }")
out.append("}")
out.append("")
out.append("/// The leaf as a filled green view, the same 16-point size the Android")
out.append("/// footer uses.")
out.append("struct CannabisLeafView: View {")
out.append("    var body: some View {")
out.append("        CannabisLeafShape()")
out.append("            .fill(Color(red: 0x43 / 255, green: 0xA0 / 255, blue: 0x47 / 255))")
out.append("            .frame(width: 16, height: 16)")
out.append("    }")
out.append("}")
out.append("")

open(OUT, "w").write("\n".join(out))
print(f"wrote {OUT}: {len(paths)} paths")
