#!/usr/bin/env bash
# Checks this bundle can run without Windows. Real install/uninstall needs Windows and is not covered here.
#   tests/run-linux-tests.sh [dir with the official archives]
# With the archives dir, also re-extracts them and checks the tracked payload is byte-identical.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHIVES="${1:-}"
PWSH="${PWSH:-$(command -v pwsh || true)}"

echo "== SHA256SUMS (payload)"
sha256sum -c --quiet SHA256SUMS && echo "ok: $(wc -l < SHA256SUMS) files"

echo "== official manifests vs archive checksums"
python3 -I - windows-x86_64 <<'EOF'
import json, sys, os
d = sys.argv[1]
sums = dict(reversed(l.split()) for l in open(os.path.join(d, "official-archives.sha256")))
for kind, name in (("app", "herdr-app-windows-x86_64.tar.gz"), ("core", "herdr-core-windows-x86_64.zip")):
    t = json.load(open(os.path.join(d, f"{kind}-latest.json")))["targets"]["windows-x86_64"]
    assert t["url"].endswith("/" + name), t["url"]
    assert t["sha256"] == sums[name], (kind, t["sha256"], sums[name])
    print(f"ok: {kind} {t['sha256']}  {t['url']}")
EOF

echo "== no file over GitHub's 100 MiB limit"
big=$(find windows-x86_64 -type f -size +100M)
[ -z "$big" ] && echo "ok: largest $(find windows-x86_64 -type f -printf '%s %p\n' | sort -n | tail -1)" || { echo "too big: $big"; exit 1; }

if [ -n "$ARCHIVES" ]; then
  echo "== payload is byte-identical to the official archives in $ARCHIVES"
  (cd "$ARCHIVES" && sha256sum -c --quiet "$OLDPWD/windows-x86_64/official-archives.sha256") && echo "ok: archives match recorded sha256"
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/core"
  tar -xzf "$ARCHIVES/herdr-app-windows-x86_64.tar.gz" -C "$t" --no-same-owner
  unzip -q "$ARCHIVES/herdr-core-windows-x86_64.zip" -d "$t/core"
  diff -r "$t/herdr-app" windows-x86_64/herdr-app && diff -r "$t/core" windows-x86_64/herdr-core && echo "ok: identical trees"
fi

if [ -n "$PWSH" ]; then
  echo "== PowerShell parse / compatibility ($("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'))"
  "$PWSH" -NoProfile -NonInteractive -File tests/parse.ps1
  echo "== helper unit tests"
  "$PWSH" -NoProfile -NonInteractive -File tests/common.tests.ps1
else
  echo "== pwsh not found: PowerShell parse checks and unit tests SKIPPED"
fi
echo "all Linux checks passed"
