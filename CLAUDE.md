# KubeGuard: conventions for the AI assistant

Research project: Kubernetes security lab, dataset, detection, eBPF, LLM triage. Plan: [docs/AIDLC_Master_Plan.md](docs/AIDLC_Master_Plan.md). Source plan: [KubeGuard_Research_Plan.md](KubeGuard_Research_Plan.md).

## Method (AI-DLC)

- Work is organised as phases (P0 to P6), units (`P<n>-U<m>`) and bolts. Inception writes a spec in `docs/specs/`, Construction builds units, Operations checks reproducibility.
- Start a session by reading the current phase spec and its unit table. Work on one unit at a time and stop at its acceptance check.
- Major choices get an ADR in `docs/adr/` (template: `docs/adr/_template.md`).
- Experiments are logged in `experiments/log.md`.

## Lab rules (non-negotiable)

- Attacks run only inside the isolated libvirt network. Snapshot VMs before every attack run and every hardening change.
- Use the dedicated kubeconfig for this project. Never use work AWS, client credentials or kubeconfigs on this machine.
- No secrets in the repo.
- Raw pcaps and bulky data stay out of git (external drive). Keep only features and manifests.

## Division of work

- The user writes core parts first: cluster setup, network policies, detection logic.
- The assistant helps with Ansible, scripts, tests, pipeline code and docs.
- The assistant never produces experimental numbers. It may propose reference leads (title and link) found by web search, always marked unverified. The user opens and verifies every reference before it is cited or enters `paper/refs.bib`.

## Layout

| Path | Purpose |
|---|---|
| docs/specs/ | One spec per phase |
| docs/adr/ | Architecture decision records |
| docs/reports/ | Benchmark and hardening reports |
| docs/naming.md | Naming conventions for lab objects |
| docs/runbooks/ | Step-by-step procedures: lab operations (networks, VMs, Ansible, cluster), later etcd restore and node drills |
| docs/literature/ | Literature protocol, matrix and gap checklist (P0) |
| docs/dataset-card.md | Dataset documentation (P3) |
| infra/ | Ansible, libvirt/cloud-init definitions |
| k8s/ | Manifests, Helm values, Cilium and Kyverno policies |
| attacks/ | Attack scenarios and manifest generator |
| collect/ | Collection and Parquet export |
| ml/ | Features, models, evaluation |
| experiments/ | Experiment log and configs |
| paper/ | LaTeX sources |

## Commands

`make help` lists targets. Available: `isolated-network-*`, `internet-network-*` and `template-vm-*` (lab network and template VM, P0). More are added as phases land (`up`, `down`, `reset`, `cluster` in P1). Names of lab objects follow [docs/naming.md](docs/naming.md).

## Git workflow

- Two long-lived branches: `main` (production, verified work only) and `dev` (integration and testing).
- Every change starts on a feature branch cut from `main`, named `<type>/<unit>-<short-name>`, e.g. `feat/p0-u4-libvirt`, `docs/p0-literature`, `fix/p1-cilium-values`.
- Flow: cut the feature branch from `main`, push it to `origin` right away, commit there, merge the feature branch into `dev` (`--no-ff`) and check the unit's acceptance check on `dev`. Only if it works, merge the same feature branch into `main` (`--no-ff`). Never merge `dev` into `main`, because `dev` may hold unverified features.
- If a feature fails on `dev`, fix it on the feature branch and merge into `dev` again. `dev` may be reset to `main` to drop failed work.
- Tag phase and gate milestones on `main` (`p0-done`, `g0`, ...) and experiments as `exp/<phase>-<id>`.
- The assistant asks before running commands, before every `git push` and before every merge, and never merges into `main` without explicit permission.
- Never commit directly to `main` or `dev`. Do not delete feature branches, local or remote; they stay as history.
- Commit messages and PR descriptions carry no AI attribution: no `Co-Authored-By: Claude` trailer, no "Generated with Claude Code" line. Commits are authored by the user only.
- Git identity for this repo: user `shaedgalib`, email `bsse1206@iit.du.ac.bd` (local config). The remote uses SSH; make sure the key in use belongs to `shaedgalib`, not another account.

## Notes

- Remote: https://github.com/shaedgalib/KubeGuard. This folder is its own git repo.
- Host: Ubuntu 24.04, 32 GB RAM. VMs: control plane 4 GB, two workers 8 GB each.
