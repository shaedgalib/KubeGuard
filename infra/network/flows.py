#!/usr/bin/env python3
"""P2-U5: turn Hubble flows into a table of who talks to whom, as the input for network policy allows.

Usage: flows.py [--since 5m] [--namespace NS] [--verdict VERDICT[,VERDICT]] [--include-replies] [--tsv]
       --since       how far back to read in each Cilium agent (default 5m; the agent keeps a limited buffer)
       --namespace   keep only edges where the source or the destination is in this namespace
       --verdict     keep only edges with one of these verdicts, for example AUDIT or DROPPED
                     (with Cilium policy audit mode on, AUDIT means "would be dropped")
       --tsv         tab-separated lines (destination, source, protocol/port, verdicts, flows) instead of markdown,
                     for scripts

It reads the flows of every Cilium agent through kubectl exec (project kubeconfig only), drops the reply
direction of a connection, merges the same connection seen on two nodes, and prints markdown. Nothing is
changed in the cluster. The counts are flows seen in the window, not bytes or connections.
"""
import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

KC = os.environ.get("PROJECT_KUBECONFIG", str(Path.home() / ".kube/kubeguard.kubeconfig"))
ENV = {k: v for k, v in os.environ.items() if k != "KUBECONFIG"}
ENTITIES = {"reserved:host": "host", "reserved:remote-node": "remote-node", "reserved:kube-apiserver": "kube-apiserver",
            "reserved:world": "world", "reserved:ingress": "ingress", "reserved:health": "health",
            "reserved:unmanaged": "unmanaged", "reserved:init": "init"}
APP_KEYS = ("k8s:app", "k8s:app.kubernetes.io/name", "k8s:k8s-app", "k8s:app.kubernetes.io/component")


def kubectl(*args):
    return subprocess.run(["kubectl", "--kubeconfig", KC, *args], capture_output=True, text=True, env=ENV)


def agents():
    out = kubectl("-n", "kube-system", "get", "pods", "-l", "k8s-app=cilium", "-o", "name")
    if out.returncode:
        sys.exit(f"cannot list the Cilium agents: {out.stderr.strip()}")
    return out.stdout.split()


def describe(ep):
    """A short name for one side of a flow: ns/app for pods, an entity name for the rest."""
    ns, labels = ep.get("namespace"), ep.get("labels") or []
    if ns:
        lab = {x.split("=", 1)[0]: x.split("=", 1)[1] for x in labels if "=" in x}
        for key in APP_KEYS:
            if key in lab:
                return f"{ns}/{lab[key]}"
        return f"{ns}/{(ep.get('pod_name') or '?').rsplit('-', 2)[0]}"
    names = [ENTITIES[x] for x in labels if x in ENTITIES]
    if names:
        # An identity can carry several entity labels: the control-plane node is "remote-node+kube-apiserver" seen
        # from a worker and "host+kube-apiserver" seen from itself. Policies match on any one of them.
        return "+".join(names)
    for x in labels:
        if x.startswith("cidr:"):
            return x
    return "unknown"


def l4(flow):
    layer = flow.get("l4") or {}
    for proto in ("TCP", "UDP", "SCTP"):
        if proto in layer:
            return proto.lower(), str(layer[proto].get("destination_port", "?"))
    for proto in ("ICMPv4", "ICMPv6"):
        if proto in layer:
            return proto.lower(), "-"
    return "other", "-"


def read(since, include_replies):
    edges = defaultdict(lambda: {"flows": 0, "verdicts": set(), "nodes": set()})
    for agent in agents():
        res = kubectl("-n", "kube-system", "exec", agent, "-c", "cilium-agent", "--",
                      "hubble", "observe", "--since", since, "--last", "100000", "-o", "json")
        if res.returncode and not res.stdout:
            print(f"warning: {agent}: {res.stderr.strip()[:200]}", file=sys.stderr)
            continue
        for line in res.stdout.splitlines():
            try:
                flow = json.loads(line)["flow"]
            except (ValueError, KeyError):
                continue
            if flow.get("is_reply") and not include_replies:
                continue
            proto, port = l4(flow)
            key = (describe(flow.get("source") or {}), describe(flow.get("destination") or {}), proto, port)
            e = edges[key]
            e["flows"] += 1
            e["verdicts"].add(flow.get("verdict", "?"))
            e["nodes"].add(agent.split("/")[-1])
    return edges


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", default="5m")
    ap.add_argument("--namespace")
    ap.add_argument("--verdict")
    ap.add_argument("--include-replies", action="store_true")
    ap.add_argument("--tsv", action="store_true")
    a = ap.parse_args()
    want = set(a.verdict.upper().split(",")) if a.verdict else None

    edges = read(a.since, a.include_replies)
    rows = []
    for (src, dst, proto, port), e in edges.items():
        if a.namespace and not (src.startswith(a.namespace + "/") or dst.startswith(a.namespace + "/")):
            continue
        if want and not (e["verdicts"] & want):
            continue
        rows.append((dst.split("/")[0] if "/" in dst else "(" + dst + ")", dst, src, proto, port, e))
    rows.sort(key=lambda r: (r[0], r[1], r[2], r[3], r[4]))

    if a.tsv:
        for _, dst, src, proto, port, e in rows:
            print("\t".join([dst, src, f"{proto}/{port}", ",".join(sorted(e["verdicts"])), str(e["flows"])]))
        return
    print(f"# Network flows seen in the last {a.since}\n")
    print(f"Namespace filter: {a.namespace or 'none'}. Verdict filter: {a.verdict or 'none'}. "
          f"Replies are {'included' if a.include_replies else 'left out'}. Edges: {len(rows)}.\n")
    print("| Destination | Source | Protocol / port | Verdicts | Flows | Seen on |\n|---|---|---|---|---:|---|")
    for _, dst, src, proto, port, e in rows:
        print(f"| {dst} | {src} | {proto}/{port} | {', '.join(sorted(e['verdicts']))} | {e['flows']} | {', '.join(sorted(e['nodes']))} |")


if __name__ == "__main__":
    main()
