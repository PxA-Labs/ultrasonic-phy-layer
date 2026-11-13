#!/usr/bin/env python3
"""Coverage gate and quality dashboard for CI (issue #36).

Report mode (one component):
    coverage_report.py report --name "Native DSP core" --lcov coverage.lcov \
        [--include REGEX] [--min-line PCT] [--min-branch PCT] \
        [--junit results.xml | --flutter-json results.json] \
        [--json-out summary.json] [--worst N]

  Parses an LCOV tracefile (line DA records, branch BRDA records), merges
  duplicate records, appends a Markdown summary to $GITHUB_STEP_SUMMARY and
  exits 1 if line or branch coverage is below the given minimum.

Dashboard mode (all components):
    coverage_report.py dashboard summary1.json summary2.json ...

  Appends one combined table (coverage, thresholds, test counts) to
  $GITHUB_STEP_SUMMARY. Missing files are reported, not ignored.

Standard library only, so it runs on any runner without installs.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


def parse_lcov(path, include=None):
    """Returns {file: {"lines": {line: hits}, "branches": {key: taken}}}."""
    files = defaultdict(lambda: {"lines": {}, "branches": {}})
    current = None
    include_re = re.compile(include) if include else None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("SF:"):
                name = line[3:].replace("\\", "/")
                current = None if include_re and not include_re.search(name) else name
            elif line == "end_of_record":
                current = None
            elif current is None:
                continue
            elif line.startswith("DA:"):
                parts = line[3:].split(",")
                lineno, hits = int(parts[0]), int(float(parts[1]))
                rec = files[current]["lines"]
                rec[lineno] = max(rec.get(lineno, 0), hits)
            elif line.startswith("BRDA:"):
                lineno, block, branch, taken = line[5:].split(",", 3)
                hits = 0 if taken == "-" else int(float(taken))
                key = (int(lineno), block, branch)
                rec = files[current]["branches"]
                rec[key] = max(rec.get(key, 0), hits)
    return files


def pct(hit, total):
    return 100.0 * hit / total if total else None


def fmt(value):
    return "n/a" if value is None else f"{value:.2f}%"


def count_junit(path):
    root = ET.parse(path).getroot()
    total = failed = skipped = 0
    for case in root.iter("testcase"):
        total += 1
        status = case.get("status", "")
        if case.find("failure") is not None or case.find("error") is not None:
            failed += 1
        elif case.find("skipped") is not None or status in ("notrun", "disabled"):
            skipped += 1
    return {"total": total, "passed": total - failed - skipped,
            "failed": failed, "skipped": skipped}


def count_flutter_json(path):
    """Counts visible tests in a `flutter test --file-reporter json:` log."""
    total = failed = skipped = 0
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw.startswith("{"):
                continue
            try:
                event = json.loads(raw)
            except ValueError:
                continue
            if event.get("type") != "testDone" or event.get("hidden"):
                continue
            total += 1
            if event.get("skipped"):
                skipped += 1
            elif event.get("result") != "success":
                failed += 1
    return {"total": total, "passed": total - failed - skipped,
            "failed": failed, "skipped": skipped}


def write_summary(text):
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(text + "\n")
    print(text)


def short_name(path):
    for marker in ("/native/", "/soundwave_app/"):
        if marker in path:
            return path.split(marker, 1)[1]
    return path


def cmd_report(args):
    files = parse_lcov(args.lcov, args.include)
    if not files:
        print(f"::error::{args.name}: no coverage records in {args.lcov}")
        return 1

    rows = []
    lf = lh = bf = bh = 0
    for name, rec in files.items():
        f_lf = len(rec["lines"])
        f_lh = sum(1 for h in rec["lines"].values() if h > 0)
        f_bf = len(rec["branches"])
        f_bh = sum(1 for h in rec["branches"].values() if h > 0)
        lf, lh, bf, bh = lf + f_lf, lh + f_lh, bf + f_bf, bh + f_bh
        rows.append((pct(f_lh, f_lf) or 0.0, short_name(name), f_lh, f_lf, f_bh, f_bf))

    line_pct, branch_pct = pct(lh, lf), pct(bh, bf)
    tests = None
    if args.junit and os.path.exists(args.junit):
        tests = count_junit(args.junit)
    elif args.flutter_json and os.path.exists(args.flutter_json):
        tests = count_flutter_json(args.flutter_json)

    failures = []
    if args.min_line is not None and (line_pct or 0.0) < args.min_line:
        failures.append(f"line coverage {fmt(line_pct)} < minimum {args.min_line:.2f}%")
    if args.min_branch is not None and bf and (branch_pct or 0.0) < args.min_branch:
        failures.append(f"branch coverage {fmt(branch_pct)} < minimum {args.min_branch:.2f}%")

    status = "FAIL" if failures else "PASS"
    out = [f"### {args.name} coverage: {status}", "",
           "| Metric | Covered | Total | Coverage | Minimum |",
           "|---|---:|---:|---:|---:|",
           f"| Lines | {lh} | {lf} | {fmt(line_pct)} | {fmt(args.min_line)} |"]
    if bf:
        out.append(f"| Branches | {bh} | {bf} | {fmt(branch_pct)} | {fmt(args.min_branch)} |")
    if tests:
        out += ["", f"Tests: **{tests['passed']} passed**, {tests['failed']} failed, "
                    f"{tests['skipped']} skipped ({tests['total']} total)"]
    rows.sort()
    if args.worst and rows:
        out += ["", f"<details><summary>{min(args.worst, len(rows))} least-covered files "
                    f"(of {len(rows)})</summary>", "",
                "| File | Lines | Branches |", "|---|---:|---:|"]
        for p, name, f_lh, f_lf, f_bh, f_bf in rows[:args.worst]:
            br = f"{fmt(pct(f_bh, f_bf))} ({f_bh}/{f_bf})" if f_bf else "n/a"
            out.append(f"| `{name}` | {p:.1f}% ({f_lh}/{f_lf}) | {br} |")
        out += ["", "</details>"]
    for failure in failures:
        out.append(f"\n**Coverage gate failed:** {failure}")
    write_summary("\n".join(out))

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump({"name": args.name, "lines": {"hit": lh, "total": lf, "pct": line_pct},
                       "branches": {"hit": bh, "total": bf, "pct": branch_pct},
                       "min_line": args.min_line, "min_branch": args.min_branch,
                       "files": len(rows), "tests": tests, "status": status}, fh, indent=2)

    # Annotation: the headline numbers also show on the run page and via the
    # checks API (step summaries are not exposed there).
    notice = [f"lines {fmt(line_pct)} ({lh}/{lf})"]
    if bf:
        notice.append(f"branches {fmt(branch_pct)} ({bh}/{bf})")
    if tests:
        notice.append(f"tests {tests['passed']}/{tests['total']} passed")
    print(f"::notice title={args.name} coverage::" + ", ".join(notice))
    if args.worst and rows:
        worst = [f"{p:.1f}% {name} ({f_lh}/{f_lf} lines, {f_bh}/{f_bf} branches)"
                 for p, name, f_lh, f_lf, f_bh, f_bf in rows[:args.worst]]
        print(f"::notice title={args.name} least-covered files::" + "%0A".join(worst))

    for failure in failures:
        print(f"::error::{args.name}: {failure}")
    return 1 if failures else 0


def cmd_dashboard(args):
    out = ["## Quality dashboard", "",
           "| Component | Line coverage | Branch coverage | Gate (line / branch) | Tests | Status |",
           "|---|---:|---:|---|---|---|"]
    missing = []
    for path in args.summaries:
        if not os.path.exists(path):
            missing.append(path)
            continue
        with open(path, encoding="utf-8") as fh:
            s = json.load(fh)
        t = s.get("tests")
        tests = (f"{t['passed']}/{t['total']} passed"
                 + (f", {t['failed']} failed" if t["failed"] else "")
                 + (f", {t['skipped']} skipped" if t["skipped"] else "")) if t else "n/a"
        branch = fmt(s["branches"]["pct"]) if s["branches"]["total"] else "n/a"
        gate = f"{fmt(s['min_line'])} / {fmt(s['min_branch']) if s['branches']['total'] else 'n/a'}"
        out.append(f"| {s['name']} | {fmt(s['lines']['pct'])} | {branch} | {gate} | {tests} | "
                   f"{s['status']} |")
    for path in missing:
        out.append(f"| `{path}` | missing (job failed or skipped) | | | | FAIL |")
    write_summary("\n".join(out))
    return 1 if missing else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    rep = sub.add_parser("report")
    rep.add_argument("--name", required=True)
    rep.add_argument("--lcov", required=True)
    rep.add_argument("--include", help="regex a source path must match")
    rep.add_argument("--min-line", type=float)
    rep.add_argument("--min-branch", type=float)
    rep.add_argument("--junit")
    rep.add_argument("--flutter-json")
    rep.add_argument("--json-out")
    rep.add_argument("--worst", type=int, default=10)
    dash = sub.add_parser("dashboard")
    dash.add_argument("summaries", nargs="+")
    args = parser.parse_args()
    return cmd_report(args) if args.cmd == "report" else cmd_dashboard(args)


if __name__ == "__main__":
    sys.exit(main())
