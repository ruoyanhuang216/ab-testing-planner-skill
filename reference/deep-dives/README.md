# A/B testing deep dives

Detailed expansions of sections in [`../ab-testing-playbook.md`](../ab-testing-playbook.md). The playbook stays high-level (the map); these files hold the math, worked examples, and code (the territory). Each deep-dive links back to its playbook section.

| Deep dive | Expands | Covers |
|---|---|---|
| [Unit-of-analysis trap](unit-of-analysis.md) | [§3](../ab-testing-playbook.md#3-randomization-unit--unit-of-analysis) | ICC / DEFF, why naive t-tests over-reject, the four fixes with CRSE & cluster-bootstrap worked examples |
| [Test statistics & sample size](test-statistics-and-sample-size.md) | [§4](../ab-testing-playbook.md#4-sample-size--mde--the-math-behind-the-number), [§8.6](../ab-testing-playbook.md#86-the-test-toolbox--which-test-for-which-statistic) | Test statistics + assumptions, when to go non-parametric, per-test sample-size derivations, regression & advanced estimators, resampling toolbox (bootstrap / permutation / jackknife) |
| [Geo randomization (Uber)](geo-randomization.md) | [§7](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets), [§16.1](../ab-testing-playbook.md#161-switchback-designs-at-scale--lyft--doordash--uber) | Marketplace interference, why effective n collapses to ~#cities, switchback, and analysis (DiD + CUPED + randomization inference, synthetic control) |
| [Network / social-graph randomization](network-randomization.md) | [§7](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets), [§16.2](../ab-testing-playbook.md#162-network-interference-detection-at-scale--ego-clusters) | Edge spillover, direct/spillover/GATE estimands + exposure mapping, graph-cluster (Louvain/METIS) & saturation designs, edge-cut bias–variance, cluster-level inference |
| [Triggered analysis (Robinhood + YouTube)](triggered-analysis.md) | [§5.1](../ab-testing-playbook.md#51-filtering--triggering--only-count-exposed-users) | Two worked examples (Robinhood credit gate; step-by-step YouTube "Up Next"): three nested triggers (exposure → decision-divergence → outcome-eligibility), ~1/trigger-rate power gain, counterfactual logging, and the exogenous-vs-endogenous narrowing rule (collider bias) |
| [Variance reduction — worked examples](variance-reduction-examples.md) | [§5](../ab-testing-playbook.md#5-variance-reduction--the-staff-level-differentiator) | A numeric example per method (triggering, transformations, stratification, CUPED, paired/interleaving): the size of each win, what it costs, and how they compose multiplicatively |

## Adding a new deep dive

1. Create `deep-dives/<topic>.md`. Open with a blockquote linking back to the playbook section; close with a back-link footer.
2. In `ab-testing-playbook.md`, drop a one-line `> 📎 **Deep dive:** [title](deep-dives/<topic>.md) — one-line hook.` under the relevant prose. Don't rewrite the original text.
3. Add a row to the table above.
