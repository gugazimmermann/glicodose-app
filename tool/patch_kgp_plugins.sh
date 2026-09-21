#!/usr/bin/env bash
# Comment out kotlin-android apply lines in resolved Flutter plugins so Flutter's
# KGP regex detector stops warning. Safe with android.builtInKotlin=true (AGP 9+).
# Re-run after `flutter pub get` / `flutter pub upgrade`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_CONFIG="$ROOT/.dart_tool/package_config.json"

if [[ ! -f "$PACKAGE_CONFIG" ]]; then
  echo "Missing $PACKAGE_CONFIG — run flutter pub get first." >&2
  exit 1
fi

# Plugins known to still contain apply plugin: kotlin-android in source text.
PLUGINS=(
  app_badge_plus
  firebase_core
  home_widget
  workmanager_android
)

python3 - "$PACKAGE_CONFIG" "${PLUGINS[@]}" <<'PY'
import json, re, sys
from pathlib import Path

config_path = Path(sys.argv[1])
wanted = set(sys.argv[2:])
data = json.loads(config_path.read_text())
packages = {p["name"]: p for p in data.get("packages", [])}

# Match imperative or plugins-block KGP applies (commented lines are left alone).
PATTERNS = [
    re.compile(r"^([ \t]*)(apply[ \t]+plugin[ \t]*:[ \t]*(['\"])(?:kotlin-android|org\.jetbrains\.kotlin\.android)\3)(.*)$"),
    re.compile(r"^([ \t]*)((?:id|alias)[ \t]*\([ \t]*(['\"])(?:kotlin-android|org\.jetbrains\.kotlin\.android)\3[ \t]*\))(.*)$"),
    re.compile(r"^([ \t]*)((?:id|alias)[ \t]+(['\"])(?:kotlin-android|org\.jetbrains\.kotlin\.android)\3)(.*)$"),
]

patched = 0
skipped = 0
for name in sorted(wanted):
    pkg = packages.get(name)
    if not pkg:
        print(f"skip  {name}: not in package_config")
        skipped += 1
        continue
    root = Path(pkg["rootUri"].replace("file://", "")) if pkg["rootUri"].startswith("file:") else (config_path.parent / pkg["rootUri"]).resolve()
    android_dir = root / "android"
    if not android_dir.is_dir():
        print(f"skip  {name}: no android/")
        skipped += 1
        continue
    files = list(android_dir.glob("build.gradle")) + list(android_dir.glob("build.gradle.kts"))
    if not files:
        print(f"skip  {name}: no build.gradle")
        skipped += 1
        continue
    for build_file in files:
        text = build_file.read_text()
        lines = text.splitlines(keepends=True)
        changed = False
        out = []
        for line in lines:
            stripped = line.lstrip()
            if stripped.startswith("//") or stripped.startswith("#"):
                out.append(line)
                continue
            replaced = False
            for pat in PATTERNS:
                m = pat.match(line.rstrip("\n\r"))
                if m:
                    indent, stmt, _q, rest = m.group(1), m.group(2), m.group(3), m.group(4)
                    newline = "\n" if line.endswith("\n") else ""
                    out.append(f"{indent}// {stmt}{rest}{newline}")
                    changed = True
                    replaced = True
                    break
            if not replaced:
                out.append(line)
        if changed:
            build_file.write_text("".join(out))
            print(f"patch {name}: {build_file}")
            patched += 1
        else:
            print(f"ok    {name}: no KGP apply line (or already commented)")
            skipped += 1

print(f"done: patched={patched} unchanged/skipped={skipped}")
PY
