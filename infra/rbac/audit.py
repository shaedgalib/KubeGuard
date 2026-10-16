#!/usr/bin/env python3
"""P2-U3: read-only RBAC audit of the cluster, printed as markdown.

Usage: audit.py          (uses the project kubeconfig; nothing in the cluster is changed)

What it reports, in the order of the CIS Kubernetes benchmark 5.1 checks:
  - roles with wildcards that are not built into Kubernetes
  - who holds sensitive capabilities: reading Secrets, creating pods, exec into pods, escalate/bind/impersonate,
    nodes/proxy, approving certificate requests, editing webhook configurations, creating service account tokens,
    creating persistent volumes
  - who is bound to cluster-admin
  - the default service account and token mounting of every namespace

Every count and name is read from the API; nothing is typed by hand. "Built-in" means a role that carries the
label kubernetes.io/bootstrapping=rbac-defaults or whose name starts with system: or kubeadm:.
"""
import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

KC = os.environ.get("PROJECT_KUBECONFIG", str(Path.home() / ".kube/kubeguard.kubeconfig"))
SYSTEM_NS = {"kube-system", "kube-public", "kube-node-lease"}
ENV = {k: v for k, v in os.environ.items() if k != "KUBECONFIG"}


def kget(*args):
    out = subprocess.run(["kubectl", "--kubeconfig", KC, "get", *args, "-o", "json"],
                         check=True, capture_output=True, text=True, env=ENV).stdout
    return json.loads(out)["items"]


def has(rule, groups, resources, verbs):
    g, r, v = (rule.get(k) or [] for k in ("apiGroups", "resources", "verbs"))
    return (("*" in g) or any(x in g for x in groups)) and \
           (("*" in r) or any(x in r for x in resources)) and \
           (("*" in v) or any(x in v for x in verbs))


CAPS = {
    "wildcard": lambda r: any("*" in (r.get(k) or []) for k in ("apiGroups", "resources", "verbs")),
    "read Secrets": lambda r: has(r, [""], ["secrets"], ["get", "list", "watch"]),
    "create pods": lambda r: has(r, [""], ["pods"], ["create"]),
    "exec into pods": lambda r: has(r, [""], ["pods/exec", "pods/attach"], ["create", "get"]),
    "escalate/bind/impersonate": lambda r: any(v in (r.get("verbs") or []) for v in ("escalate", "bind", "impersonate", "*")),
    "nodes/proxy": lambda r: has(r, [""], ["nodes/proxy"], ["get", "create"]),
    "approve CSRs": lambda r: has(r, ["certificates.k8s.io"], ["certificatesigningrequests/approval", "signers"], ["update", "approve"]),
    "edit webhooks": lambda r: has(r, ["admissionregistration.k8s.io"], ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"], ["create", "update", "patch", "delete"]),
    "create SA tokens": lambda r: has(r, [""], ["serviceaccounts/token"], ["create"]),
    "create PVs": lambda r: has(r, [""], ["persistentvolumes"], ["create"]),
}


def builtin(item):
    name = item["metadata"]["name"]
    labels = item["metadata"].get("labels") or {}
    return labels.get("kubernetes.io/bootstrapping") == "rbac-defaults" or name.startswith(("system:", "kubeadm:"))


def caps_of(role):
    found = set()
    for rule in role.get("rules") or []:
        for name, test in CAPS.items():
            if test(rule):
                found.add(name)
    return found


def cell(text):
    return str(text).replace("|", "\\|")


def main():
    cr = {i["metadata"]["name"]: i for i in kget("clusterroles")}
    nr = {(i["metadata"]["namespace"], i["metadata"]["name"]): i for i in kget("roles", "-A")}
    crb = kget("clusterrolebindings")
    rb = kget("rolebindings", "-A")
    sas = kget("serviceaccounts", "-A")
    pods = kget("pods", "-A")
    version = json.loads(subprocess.run(["kubectl", "--kubeconfig", KC, "version", "-o", "json"], check=True,
                                        capture_output=True, text=True, env=ENV).stdout)["serverVersion"]["gitVersion"]

    out = ["# RBAC audit\n", f"Kubernetes server {version}. ClusterRoles: {len(cr)}, Roles: {len(nr)}, "
           f"ClusterRoleBindings: {len(crb)}, RoleBindings: {len(rb)}, ServiceAccounts: {len(sas)}.\n"]

    # 1. wildcard roles that are not built in
    out.append("## Roles with wildcards (CIS 5.1.3)\n")
    wild_builtin = sum(1 for r in list(cr.values()) + list(nr.values()) if builtin(r) and "wildcard" in caps_of(r))
    wild_other = [("ClusterRole" if "namespace" not in r["metadata"] else "Role", r["metadata"].get("namespace", "-"), r["metadata"]["name"])
                  for r in list(cr.values()) + list(nr.values()) if not builtin(r) and "wildcard" in caps_of(r)]
    out.append(f"Built-in roles with a wildcard (cluster-admin and the system:* controllers): {wild_builtin}.\n")
    if wild_other:
        out.append("| Kind | Namespace | Name |\n|---|---|---|")
        out += [f"| {k} | {ns} | {n} |" for k, ns, n in sorted(wild_other)]
    else:
        out.append("Roles with a wildcard that are not built in: none.")
    out.append("")

    # 2. subject -> capabilities
    subj = defaultdict(lambda: {"roles": set(), "caps": defaultdict(set)})

    def grant(subject, role, role_label, scope):
        kind, name = subject["kind"], subject["name"]
        sns = subject.get("namespace", "") if kind == "ServiceAccount" else ""
        entry = subj[(kind, sns, name)]
        entry["roles"].add(f"{role_label} ({scope})")
        for cap in caps_of(role):
            entry["caps"][cap].add(scope)

    for b in crb:
        role = cr.get(b["roleRef"]["name"])
        if role is None:
            continue
        for s in b.get("subjects") or []:
            grant(s, role, f'ClusterRole/{b["roleRef"]["name"]}', "cluster")
    for b in rb:
        ns = b["metadata"]["namespace"]
        ref = b["roleRef"]
        role = cr.get(ref["name"]) if ref["kind"] == "ClusterRole" else nr.get((ns, ref["name"]))
        if role is None:
            continue
        for s in b.get("subjects") or []:
            grant(s, role, f'{ref["kind"]}/{ref["name"]}', f"namespace {ns}")

    def is_system_subject(key):
        kind, ns, name = key
        if kind == "ServiceAccount":
            return ns in SYSTEM_NS
        return name.startswith("system:") and name != "system:masters"

    def caps_text(caps):
        parts = []
        for cap in sorted(caps):
            scopes = caps[cap]
            where = "cluster" if "cluster" in scopes else ", ".join(sorted(x.replace("namespace ", "ns ") for x in scopes))
            parts.append(f"{cap} ({where})")
        return ", ".join(parts)

    sens = {k: v for k, v in subj.items() if v["caps"]}
    lab = {k: v for k, v in sens.items() if not is_system_subject(k)}
    sysm = {k: v for k, v in sens.items() if is_system_subject(k)}

    out.append("## Subjects outside kube-system that hold sensitive capabilities (CIS 5.1.1 to 5.1.13)\n")
    out.append("Includes users and groups other than the system:* groups, and ServiceAccounts of every namespace except kube-system, kube-public and kube-node-lease. The scope of each capability is given in brackets: cluster, or the namespace it is limited to.\n")
    out.append("| Subject | Roles (scope) | Capabilities |\n|---|---|---|")
    for (kind, ns, name), v in sorted(lab.items()):
        label = f"{kind}:{ns}/{name}" if ns else f"{kind}:{name}"
        out.append(f"| {cell(label)} | {cell('; '.join(sorted(v['roles'])))} | {cell(caps_text(v['caps']))} |")
    out.append("")

    out.append("## Subjects in kube-system and the built-in system groups\n")
    out.append("These are the control-plane components, controllers and add-ons. Their rights are set by Kubernetes, kubeadm and the Helm charts.\n")
    out.append("| Subject | Capabilities |\n|---|---|")
    for (kind, ns, name), v in sorted(sysm.items()):
        label = f"{kind}:{ns}/{name}" if ns else f"{kind}:{name}"
        out.append(f"| {cell(label)} | {cell(caps_text(v['caps']))} |")
    out.append("")

    # 3. cluster-admin
    out.append("## Bindings to cluster-admin (CIS 5.1.1, 5.1.7)\n")
    out.append("| Kind | Binding | Namespace | Subjects |\n|---|---|---|---|")
    for b in crb + rb:
        if b["roleRef"]["name"] == "cluster-admin":
            subs = ", ".join(f'{s["kind"]}:{s.get("namespace", "")}/{s["name"]}'.replace(":/", ":") for s in b.get("subjects") or [])
            out.append(f'| {b["kind"]} | {b["metadata"]["name"]} | {b["metadata"].get("namespace", "-")} | {cell(subs)} |')
    out.append("")

    # 4. default service accounts and token mounting
    out.append("## Default service accounts and token mounting (CIS 5.1.5, 5.1.6)\n")
    out.append("| Namespace | default SA automountServiceAccountToken | Pods using the default SA | Pods with a mounted API token |\n|---|---|---|---|")
    by_ns = defaultdict(list)
    for p in pods:
        by_ns[p["metadata"]["namespace"]].append(p)
    default_sa = {s["metadata"]["namespace"]: s for s in sas if s["metadata"]["name"] == "default"}

    def mounts_token(p):
        for v in (p["spec"].get("volumes") or []):
            if any("serviceAccountToken" in s for s in (v.get("projected") or {}).get("sources", [])):
                return True
        return False

    for ns in sorted(default_sa):
        auto = default_sa[ns].get("automountServiceAccountToken")
        auto_text = "unset (token mounted)" if auto is None else str(auto).lower()
        ps = by_ns.get(ns, [])
        using = [p["metadata"]["name"] for p in ps if (p["spec"].get("serviceAccountName") or "default") == "default"]
        mounted = [p for p in ps if mounts_token(p)]
        if ns in SYSTEM_NS:
            out.append(f"| {ns} | {auto_text} | {len(using)} | {len(mounted)} of {len(ps)} |")
        else:
            out.append(f"| {ns} | {auto_text} | {cell(', '.join(using) or 'none')} | {len(mounted)} of {len(ps)} |")
    out.append("")
    print("\n".join(out))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"kubectl failed: {e.stderr.strip()}")
