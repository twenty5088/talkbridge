#!/usr/bin/env bash
# 在 runner 上挑「最新 iOS runtime」裡第一台實際存在的 iPhone 模擬器，輸出 xcodebuild -destination 字串。
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            if best is None or ver > best[0]:
                best = (ver, d["udid"], d["name"])
            break
if not best:
    sys.exit("沒有可用的 iPhone 模擬器")
print(f"platform=iOS Simulator,id={best[1]}")
print(f"picked {best[2]} iOS {best[0][0]}.{best[0][1]}", file=sys.stderr)
'
