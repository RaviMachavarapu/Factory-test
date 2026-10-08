#!/usr/bin/env bash
# REQ-322 (ADR-002: severity is derived from a required CVSS v4.0 vector): cvss4.py scores a vector with FIRST's algorithm
# over the macro-vector lookup table, max-composed vectors and max-severity distances vendored once from a pinned commit of
# github.com/FIRSTdotorg/cvss-v4-calculator (BSD-2-Clause; URL, commit and each file's sha256 recorded), and agrees with
# FIRST's own JavaScript on every conformance vector (generated with node at authoring time; never fetched in a test).
# Covers: REQ-322
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/check.sh"
LIB="$ROOT/scripts/lib/specflow"; V="$ROOT/tests/governance/fixtures/cvss4/vectors.json"
for f in "$LIB/cvss4.py" "$LIB/cvss4_data.py" "$LIB/cvss4_LICENSE" "$V" "$ROOT/tests/governance/fixtures/cvss4/generate.mjs"; do
  ck "$(basename "$f") exists" test -f "$f"
done
ck "provenance: the FIRST repository, a 40-hex commit, a sha256 per fetched file, BSD-2-Clause, 270 lookup entries" \
  python3 - "$LIB" <<'PY'
import re, sys; sys.path.insert(0, sys.argv[1]); import cvss4_data as d
s = d.SOURCE
assert s["repository"] == "https://github.com/FIRSTdotorg/cvss-v4-calculator", s
assert re.fullmatch(r"[0-9a-f]{40}", s["commit"]) and s["license"] == "BSD-2-Clause", s
for f in ("cvss_lookup.js", "max_composed.js", "max_severity.js", "cvss_score.js", "LICENSE"):
    assert re.fullmatch(r"[0-9a-f]{64}", s["files"][f]), f
assert len(d.LOOKUP) == 270 and all(re.fullmatch(r"[0-9]{6}", k) for k in d.LOOKUP), len(d.LOOKUP)
PY
ck "cvss4.py's header names the source URL and the commit" \
  bash -c 'head -30 "$1" | grep -qF "FIRSTdotorg/cvss-v4-calculator" && head -30 "$1" | grep -qE "[0-9a-f]{40}"' _ "$LIB/cvss4.py"
ck "the BSD-2-Clause notice ships beside the data" grep -qF 'Redistribution and use in source and binary forms' "$LIB/cvss4_LICENSE"
ck "no network or file I/O in the scorer (pure: the kernel imports it)" \
  no grep -qE '^[[:space:]]*(import|from) (urllib|http|socket|subprocess)|open\(' "$LIB/cvss4.py" "$LIB/cvss4_data.py"
report=$(python3 - "$LIB" "$V" <<'PY'
import json, sys; sys.path.insert(0, sys.argv[1]); import cvss4
v = json.load(open(sys.argv[2])); bad = []
if "node" not in v["source"]["command"] or v["source"]["commit"] != __import__("cvss4_data").SOURCE["commit"]:
    bad.append("vectors.json: provenance does not match cvss4_data.SOURCE")
vs = v["vectors"]
if len(vs) < 60: bad.append(f"only {len(vs)} vectors (want >= 60)")
bands = {c["severity"] for c in vs}
if not {"none", "low", "medium", "high", "critical"} <= bands: bad.append(f"bands covered: {sorted(bands)}")
if sum("/E:" in c["vector"] for c in vs) < 5: bad.append("fewer than 5 Threat (E:) vectors")
if sum(any(f"/{m}:" in c["vector"] for m in ("CR", "IR", "AR", "MAV", "MVC", "MSI")) for c in vs) < 5:
    bad.append("fewer than 5 Environmental vectors")
for c in vs:
    try:
        got = cvss4.score(c["vector"]); sev = cvss4.severity(got)
    except Exception as e:
        bad.append(f'{c["vector"]}: raised {e!r}'); continue
    if got != c["score"] or sev != c["severity"] or cvss4.band(c["vector"]) != sev:
        bad.append(f'{c["vector"]}: {got} {sev} != FIRST {c["score"]} {c["severity"]}')
if len(v["malformed"]) < 10: bad.append("fewer than 10 malformed vectors")
for m in v["malformed"]:
    try:
        cvss4.parse(m); bad.append(f"malformed accepted: {m!r}")
    except cvss4.CvssError:
        pass
print("\n".join(bad))
PY
)
ck "cvss4 agrees with FIRST's calculator on every conformance vector and rejects every malformed one${report:+: $report}" [ -z "$report" ]
ck "RUBRIC.md's worked example (high) and counter-example (medium) carry vectors that FIRST scores in those bands" \
  python3 - "$LIB" "$ROOT/docs/security/RUBRIC.md" "$V" <<'PY'
import json, re, sys; sys.path.insert(0, sys.argv[1]); import cvss4
vec = re.findall(r"CVSS:4\.0/[A-Z]+:[A-Za-z]+(?:/[A-Z]+:[A-Za-z]+)*", open(sys.argv[2]).read())
assert len(vec) == 2, vec
assert [cvss4.band(x) for x in vec] == ["high", "medium"], [(x, cvss4.score(x)) for x in vec]
known = {c["vector"] for c in json.load(open(sys.argv[3]))["vectors"]}
assert set(vec) <= known, "the rubric vectors are conformance vectors"
PY
ck "finding_severity: a 0.0 vector (no impact) is an informational low (R20); every other band is itself" python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import cvss4
z = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"
assert cvss4.score(z) == 0.0 and cvss4.band(z) == "none" and cvss4.finding_severity(z) == "low"
h = "CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N"
assert cvss4.finding_severity(h) == cvss4.band(h) == "high"
PY
ck "a finding's vector is base metrics only: base_only and finding_severity reject every Threat, Environmental and Supplemental metric (even :X), naming it and the base score; score() still scores full vectors" \
  python3 - "$LIB" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import cvss4
from cvss4_data import METRIC_ORDER, METRIC_VALUES
b = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N"
assert cvss4.score(b) == 9.3 and cvss4.finding_severity(b) == "critical" and cvss4.base_only(b) == b
assert cvss4.score(b + "/MVC:N/MVI:N/MVA:N") == 0.0  # the scoring library still scores a full vector (FIRST conformance)
extras = ["/MVC:N/MVI:N/MVA:N", "/E:U", "/E:X", "/CR:L", "/S:N", "/U:Red"]
extras += [f"/{m}:{METRIC_VALUES[m][-1]}" for m in METRIC_ORDER[11:]]
for extra in extras:
    for f in (cvss4.base_only, cvss4.finding_severity):
        try:
            f(b + extra)
        except cvss4.CvssError as e:
            m = extra[1:].split(":")[0]
            assert repr(m) in str(e) and "base score" in str(e), (extra, str(e))
        else:
            raise AssertionError(f"{f.__name__} accepted {b + extra}")
PY
finish test_cvss4
