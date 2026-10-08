#!/usr/bin/env node
// tests/governance/fixtures/cvss4/generate.mjs — REQ-322 (R8): produces the conformance vectors that pin cvss4.py to
// FIRST's own JavaScript. Loads cvss_lookup.js, max_composed.js, max_severity.js and cvss_score.js (fetched once, at
// authoring time, from the pinned commit of github.com/FIRSTdotorg/cvss-v4-calculator) into one vm context, builds the
// calculator's cvssSelected (every metric "X" unless the vector sets it), and prints macroVector() -> cvss_score() per
// vector. Never run in a test; the test reads the vectors.json this produces.
//
// Usage: node tests/governance/fixtures/cvss4/generate.mjs <dir-with-FIRST-js-files> > vectors.json

import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const crypto = require("node:crypto");

const srcDir = process.argv[2];
if (!srcDir) {
  console.error("usage: generate.mjs <dir-with-FIRST-js-files>");
  process.exit(2);
}

const COMMIT = "c5b0d409ae9f57c44264c6ce5f27d89298e1d32a";
const FILES = ["cvss_lookup.js", "max_composed.js", "max_severity.js", "cvss_score.js"];

const ctx = createContext({});
for (const f of FILES) {
  const code = readFileSync(`${srcDir}/${f}`, "utf8");
  runInContext(code, ctx, { filename: f });
}

// The eleven base metrics, in the CVSS v4.0 specification's order; every other recognised metric defaults to "X".
const ALL_METRICS = [
  "AV", "AC", "AT", "PR", "UI", "VC", "VI", "VA", "SC", "SI", "SA",
  "E",
  "CR", "IR", "AR", "MAV", "MAC", "MAT", "MPR", "MUI", "MVC", "MVI", "MVA", "MSC", "MSI", "MSA",
  "S", "AU", "R", "V", "RE", "U",
];

function cvssSelectedFor(vector) {
  const selected = {};
  for (const metric of ALL_METRICS) selected[metric] = "X";
  const body = vector.replace(/^CVSS:4\.0\//, "");
  for (const part of body.split("/")) {
    if (!part) continue;
    const idx = part.indexOf(":");
    const key = part.slice(0, idx);
    const val = part.slice(idx + 1);
    selected[key] = val;
  }
  return selected;
}

function scoreVector(vector) {
  const selected = cvssSelectedFor(vector);
  const mv = ctx.macroVector(selected);
  const score = ctx.cvss_score(selected, ctx.cvssLookup_global, ctx.maxSeverity, mv);
  return score;
}

function severityOf(score) {
  if (score === 0.0) return "none";
  if (score <= 3.9) return "low";
  if (score <= 6.9) return "medium";
  if (score <= 8.9) return "high";
  return "critical";
}

// A deterministic LCG (seed 322) over the base metric value sets, to pad the sample past 60 vectors covering every band.
function* lcg(seed) {
  let state = seed >>> 0;
  while (true) {
    state = (state * 1664525 + 1013904223) >>> 0;
    yield state / 4294967296;
  }
}

const BASE_VALUES = {
  AV: ["N", "A", "L", "P"],
  AC: ["L", "H"],
  AT: ["N", "P"],
  PR: ["N", "L", "H"],
  UI: ["N", "P", "A"],
  VC: ["H", "L", "N"],
  VI: ["H", "L", "N"],
  VA: ["H", "L", "N"],
  SC: ["H", "L", "N"],
  SI: ["H", "L", "N"],
  SA: ["H", "L", "N"],
};
const BASE_ORDER = ["AV", "AC", "AT", "PR", "UI", "VC", "VI", "VA", "SC", "SI", "SA"];

function lcgVector(rand) {
  const parts = ["CVSS:4.0"];
  for (const m of BASE_ORDER) {
    const values = BASE_VALUES[m];
    const i = Math.floor(rand.next().value * values.length);
    parts.push(`${m}:${values[i]}`);
  }
  return parts.join("/");
}

const fixedVectors = [
  // RUBRIC.md worked example (high, the release-hook exfiltration finding)
  "CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:H/VI:H/VA:N/SC:N/SI:N/SA:N",
  // RUBRIC.md counter-example (medium, the dashboard-renderer variant: confidentiality lowered to None)
  "CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:N/VI:H/VA:N/SC:N/SI:N/SA:N",
  // tauri skeleton — SEC-002, SEC-003 (informational, no impact: all-N)
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
  // tauri skeleton — SEC-001-style low-impact local finding
  "CVSS:4.0/AV:L/AC:L/AT:N/PR:L/UI:N/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N",
  // an all-N impact vector (the same 0.0 case, spelled out again for clarity)
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
  // critical
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H",
  // low
  "CVSS:4.0/AV:P/AC:H/AT:P/PR:H/UI:A/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N",
  // >=5 Threat (E:) vectors
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:A",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:P",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:U",
  "CVSS:4.0/AV:A/AC:L/AT:N/PR:L/UI:N/VC:H/VI:L/VA:N/SC:N/SI:N/SA:N/E:A",
  "CVSS:4.0/AV:A/AC:L/AT:N/PR:L/UI:N/VC:H/VI:L/VA:N/SC:N/SI:N/SA:N/E:U",
  // >=5 environmental (CR/IR/AR/M*) vectors
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/CR:H/IR:H/AR:H",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/CR:L/IR:L/AR:L",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/MAV:A",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/MVC:L",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/MSI:S",
  // >=3 supplemental vectors
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/S:P",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/R:A",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/RE:H",
];

const seen = new Set(fixedVectors);
const vectors = [...fixedVectors];
const rand = lcg(322);
while (vectors.length < 65) {
  const v = lcgVector(rand);
  if (seen.has(v)) continue;
  seen.add(v);
  vectors.push(v);
}

const results = vectors.map((vector) => {
  const score = scoreVector(vector);
  return { vector, score, severity: severityOf(score) };
});

const malformed = [
  "",
  "AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
  "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N",
  "CVSS:4.0/",
  "CVSS:4.0/AV:N",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N",
  "CVSS:4.0/AV:X/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
  "CVSS:4.0/AC:L/AV:N/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N/",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N/ZZ:H",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N//E:A",
  "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N/AV:A",
];

const out = {
  source: {
    calculator: "https://github.com/FIRSTdotorg/cvss-v4-calculator",
    commit: COMMIT,
    node: process.version,
    command:
      'node tests/governance/fixtures/cvss4/generate.mjs "$TMPDIR/first-cvss4" > tests/governance/fixtures/cvss4/vectors.json',
  },
  vectors: results,
  malformed,
};

console.log(JSON.stringify(out, null, 2));
