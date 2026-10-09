# ADR-G0: Literature gap decision (gate G0)

Date: 2026-10-09
Status: accepted
Accepted by / date: shaedgalib (researcher), 2026-10-09

## Context

Gate G0 asks whether the literature shows a genuine gap before the cluster is built. The research questions and the gap analysis are in [docs/specs/research-questions.md](../specs/research-questions.md). The evidence is in [docs/literature/matrix.md](../literature/matrix.md) (36 entries, 27 verified at metadata level) and [docs/reports/P0-U7-verification.md](../reports/P0-U7-verification.md).

Proposed pass rule (from the research-questions draft): G1 holds after the closest sources are read in full, and at least one of G3, G4 or G5 also holds.

Evidence for each gap, as of 2026-10-09:

| Gap | Result | Strength | Main sources |
|---|---|---|---|
| G1: no dataset with flow, runtime and audit signals from the same Kubernetes attack runs, with benign operational changes | Holds. Nothing read uses three signal types or treats rollouts or autoscaling as benign change | Moderate to strong | L01, L03, L24, L30, L32 read in full; L04 page read |
| G2: ML detectors rarely compared with rule baselines on identical splits | Holds for the sources read | Moderate | L24, L03, L30, L13 |
| G3: eBPF collection cost versus packet capture or sidecars | eBPF versus perf is covered (L32). Packet capture and sidecars are not | Weak to moderate | L32, L25, L29, L13 |
| G4: LLM triage under attacker-controlled logs, Kubernetes | Holds. Injection through logs is studied outside Kubernetes (L20 to L22); triage is studied outside Kubernetes (L16 to L18) | Moderate | L16 to L22 |
| G5: policy synthesis from observed flows, scored by attack replay | Holds for the sources read. L19 starts from text intent on Kind | Weak to moderate | L19, L27, L28, L34 |
| G6: "bare-metal" as a gap | Dropped. This lab is VM-based, as are L24 and L03 | n/a | L24, L03, L30 |

Under the proposed rule, G1 and G4 hold, so the pass condition is met.

Limits of the evidence: abstract-level reading for many sources; data files of L01 and L04 not inspected; four leads unchecked (L05, L15, L35, L36); several sources are unreviewed arXiv preprints; the search was in English through one search tool. "Not stated" in a source means the pages read did not say, not that the work does not exist.

## Options considered

1. **Proceed as planned.** Build the cluster, keep RQ1 to RQ3 as drafted, with G6 dropped and "bare-metal" reworded to "self-hosted lab cluster".
2. **Proceed with a reduced scope.** Keep RQ1 and RQ3, and reduce RQ2 to the eBPF-versus-packet-capture comparison only if time allows. Appropriate if G3 is judged too weak.
3. **Pivot the angle.** Focus on false positives under benign operational changes (the fallback in the programme plan). Appropriate if G1 were refuted.
4. **Stop and refine the research questions** before building. Appropriate if close prior work were found.

## Decision

Accepted: **Option 1**, with these conditions:
- Treat G1 as the main contribution, and G4 as the second.
- Keep G2, G3 and G5 as secondary claims with their current strength labels. State G3 narrowly: against packet capture and sidecars, since eBPF versus perf is covered by L32.
- Drop the "bare-metal" claim everywhere.
- Re-check G1 when the L01 data files are available (expected after about 11 October 2026) and before any paper submission, with a fresh search.

Accepted by the researcher on 2026-10-09. Gate G0 is passed.

## Consequences

- If accepted, Phase 0 can close after P0-U9 (Phase 1 spec) and P0-U10, and the cluster build starts in Phase 1.
- The dataset design in Phase 3 must include: three signal types (flow, runtime, audit), several attack classes, and labelled benign operational changes (rollouts, autoscaling, node maintenance). These are the properties that make G1 a gap.
- The related-work section of Paper 1 must position the work against L01, L03, L24, L30 and L32, and state that the dataset is VM-based.
- Risk: a source not found by this search could weaken G1. Mitigation: repeat the search before submission, and keep the false-positives-under-benign-changes angle as the fallback.
