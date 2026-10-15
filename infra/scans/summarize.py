#!/usr/bin/env python3
"""Turn saved scanner output (infra/scans/run.sh) into markdown tables.

Usage: summarize.py [SCAN_DIR]               scores of one scan (default: the latest)
       summarize.py --compare BEFORE AFTER   what changed between two scans

Every number is read from the scanner's own JSON. The only arithmetic is counting rows
and taking differences between two scans; nothing is estimated or typed in by hand.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

BASE = Path.home() / ".local/share/kubeguard/scans"


def load_kube_bench(path):
    text = path.read_text()
    start = text.find('{"Controls"')
    if start < 0:
        sys.exit(f"{path}: no kube-bench JSON found")
    data = json.JSONDecoder().raw_decode(text[start:])[0]
    checks = {}
    for section in data["Controls"]:
        for group in section["tests"]:
            for r in group["results"]:
                m = re.search(r"\((Automated|Manual)\)\s*$", r["test_desc"])
                checks[r["test_number"]] = {
                    "status": r["status"],
                    "kind": m.group(1) if m else "",
                    "desc": re.sub(r"\s*\((Automated|Manual)\)\s*$", "", r["test_desc"]),
                    "actual": str(r.get("actual_value", "")),
                }
    return {"totals": data["Totals"], "sections": data["Controls"], "checks": checks}


def kube_bench_nodes(scan):
    files = sorted(scan.glob("kube-bench-*.log"), key=lambda p: ("control" not in p.name, p.name))
    return {p.name[len("kube-bench-"):-len(".log")]: load_kube_bench(p) for p in files}


def load_kubescape(scan):
    path = scan / "kubescape.json"
    if not path.exists():
        return None
    sd = json.loads(path.read_text())["summaryDetails"]
    return sd


def sort_id(test_number):
    return [int(x) for x in re.findall(r"\d+", test_number)]


def cell(text, width=110):
    text = text.replace("|", "\\|").replace("\n", " ")
    return text if len(text) <= width else text[: width - 3] + "..."


def summary(scan):
    out = []
    ctx = scan / "context.txt"
    out.append(f"# Scan `{scan.name}`\n")
    if ctx.exists():
        out.append("```\n" + ctx.read_text().rstrip() + "\n```\n")

    nodes = kube_bench_nodes(scan)
    if nodes:
        out.append("## kube-bench\n")
        out.append("| Node | PASS | FAIL | WARN | INFO |\n|---|---:|---:|---:|---:|")
        for node, kb in nodes.items():
            t = kb["totals"]
            out.append(f"| {node} | {t['total_pass']} | {t['total_fail']} | {t['total_warn']} | {t['total_info']} |")
        out.append("")
        first = next(iter(nodes.values()))
        out.append("Sections on the control-plane node:\n")
        out.append("| Section | PASS | FAIL | WARN | INFO |\n|---|---:|---:|---:|---:|")
        for s in first["sections"]:
            out.append(f"| {s['id']} {s['text']} | {s['total_pass']} | {s['total_fail']} | {s['total_warn']} | {s['total_info']} |")
        out.append("")
        for node, kb in nodes.items():
            fails = sorted((k, v) for k, v in kb["checks"].items() if v["status"] == "FAIL")
            out.append(f"### FAIL on {node} ({len(fails)})\n")
            if fails:
                out.append("| Check | Type | Description |\n|---|---|---|")
                for k, v in sorted(fails, key=lambda kv: sort_id(kv[0])):
                    out.append(f"| {k} | {v['kind']} | {cell(v['desc'])} |")
            else:
                out.append("None.")
            out.append("")
        for node, kb in nodes.items():
            warns = sorted((k for k, v in kb["checks"].items() if v["status"] == "WARN"), key=sort_id)
            kinds = Counter(kb["checks"][k]["kind"] for k in warns)
            out.append(f"WARN on {node} ({len(warns)}; {dict(kinds)}): " + ", ".join(warns) + "\n")

    sd = load_kubescape(scan)
    if sd:
        out.append("## kubescape\n")
        out.append("| Framework | Compliance score | Controls passed | failed | skipped | Resources passed | failed |\n|---|---:|---:|---:|---:|---:|---:|")
        for f in sd["frameworks"]:
            c = Counter(v["status"] for v in f["controls"].values())
            rc = f["ResourceCounters"]
            out.append(f"| {f['name']} | {f['complianceScore']:.2f} | {c.get('passed', 0)} | {c.get('failed', 0)} | {c.get('skipped', 0)} | {rc['passedResources']} | {rc['failedResources']} |")
        union = Counter(v["status"] for v in sd["controls"].values())
        sub = Counter(v.get("statusInfo", {}).get("subStatus") for v in sd["controls"].values() if v["status"] == "skipped")
        out.append(f"\nOverall compliance score {sd['complianceScore']:.2f}. Controls over all frameworks ({len(sd['controls'])}): "
                   f"{union.get('passed', 0)} passed, {union.get('failed', 0)} failed, {union.get('skipped', 0)} skipped "
                   f"({', '.join(f'{n} {k}' for k, n in sub.items())}). "
                   f"Failed controls by severity: {sd['controlsSeverityCounters']}.\n")
        failed = [v for v in sd["controls"].values() if v["status"] == "failed" and v.get("severity") in ("High", "Critical")]
        out.append(f"### Failed controls of High or Critical severity ({len(failed)})\n")
        out.append("| Control | Name | Severity | Resources failed | passed |\n|---|---|---|---:|---:|")
        for v in sorted(failed, key=lambda v: v["controlID"]):
            rc = v["ResourceCounters"]
            out.append(f"| {v['controlID']} | {cell(v['name'], 80)} | {v['severity']} | {rc['failedResources']} | {rc['passedResources']} |")
        out.append("")
    return "\n".join(out)


def compare(before, after):
    out = [f"# Scan comparison\n\nBefore: `{before.name}`  \nAfter: `{after.name}`\n"]
    nb, na = kube_bench_nodes(before), kube_bench_nodes(after)
    if nb and na:
        out.append("## kube-bench totals\n")
        out.append("| Node | PASS | FAIL | WARN | INFO |\n|---|---:|---:|---:|---:|")
        for node in nb:
            if node not in na:
                continue
            b, a = nb[node]["totals"], na[node]["totals"]
            row = " | ".join(f"{b[k]} -> {a[k]}" for k in ("total_pass", "total_fail", "total_warn", "total_info"))
            out.append(f"| {node} | {row} |")
        out.append("\n## kube-bench checks whose status changed\n")
        out.append("| Node | Check | Before | After | Description |\n|---|---|---|---|---|")
        changed = 0
        for node in nb:
            if node not in na:
                continue
            for k in sorted(set(nb[node]["checks"]) | set(na[node]["checks"]), key=sort_id):
                b = nb[node]["checks"].get(k, {}).get("status", "absent")
                a = na[node]["checks"].get(k, {}).get("status", "absent")
                if b != a:
                    changed += 1
                    desc = (na[node]["checks"].get(k) or nb[node]["checks"].get(k))["desc"]
                    out.append(f"| {node} | {k} | {b} | {a} | {cell(desc, 90)} |")
        if not changed:
            out.append("| (none) | | | | |")
        out.append("")
    sb, sa = load_kubescape(before), load_kubescape(after)
    if sb and sa:
        out.append("## kubescape compliance score per framework\n")
        out.append("| Framework | Before | After |\n|---|---:|---:|")
        fa = {f["name"]: f for f in sa["frameworks"]}
        for f in sb["frameworks"]:
            if f["name"] in fa:
                out.append(f"| {f['name']} | {f['complianceScore']:.2f} | {fa[f['name']]['complianceScore']:.2f} |")
        out.append(f"| overall | {sb['complianceScore']:.2f} | {sa['complianceScore']:.2f} |\n")
        out.append("## kubescape controls that changed (status or failed resources)\n")
        out.append("| Control | Name | Status before -> after | Failed resources before -> after |\n|---|---|---|---|")
        changed = 0
        for cid in sorted(set(sb["controls"]) | set(sa["controls"])):
            b, a = sb["controls"].get(cid), sa["controls"].get(cid)
            bs, as_ = (b or {}).get("status", "absent"), (a or {}).get("status", "absent")
            bf = (b or {}).get("ResourceCounters", {}).get("failedResources", 0)
            af = (a or {}).get("ResourceCounters", {}).get("failedResources", 0)
            if bs != as_ or bf != af:
                changed += 1
                out.append(f"| {cid} | {cell((a or b)['name'], 70)} | {bs} -> {as_} | {bf} -> {af} |")
        if not changed:
            out.append("| (none) | | | |")
        out.append("")
    return "\n".join(out)


def resolve(arg):
    p = Path(arg).expanduser() if arg else BASE / "latest"
    if not p.is_dir():
        p = BASE / arg if arg and (BASE / arg).is_dir() else p
    if not p.is_dir():
        sys.exit(f"scan directory not found: {arg or BASE / 'latest'}")
    return p.resolve()


def main(argv):
    if argv[:1] == ["--compare"] and len(argv) == 3:
        print(compare(resolve(argv[1]), resolve(argv[2])))
    elif argv[:1] == ["--compare"] or len(argv) > 1:
        sys.exit(__doc__)
    else:
        print(summary(resolve(argv[0] if argv else None)))


if __name__ == "__main__":
    main(sys.argv[1:])
