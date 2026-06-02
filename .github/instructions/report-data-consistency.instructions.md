---
applyTo: "Report_security/**/*.md"
description: "Enforce data consistency checks before rendering SOC-style security reports from source data."
---

# Report Data Consistency

Before rendering any security report from raw scan, log, or incident data, verify the numbers against the source and refuse to invent missing values.

## Required checks
- Identify the authoritative input fields and treat them as the only source of truth.
- Compute base totals first: total records, unique IPs or assets, unique ports, unique services, status breakdown, and time distribution when available.
- Derive every percentage from the same denominator used in the report and show the raw count beside the percentage.
- Cross-check that subtotals, top lists, and category breakdowns are internally consistent.
- If any value cannot be derived exactly, mark it as unavailable instead of estimating.
- If two fields conflict or the source data is ambiguous, stop and reconcile before writing the final report.

## Rendering rules
- Do not render the final report until the consistency checks pass.
- Do not state attack trends, campaign scope, or risk levels unless the data supports them.
- Keep factual counts, ratios, and timestamps consistent across tables, charts, and narrative sections.
- Prefer explicit denominators and short verification notes when the report includes percentages.

## Completion criteria
The report may be rendered only when:
- all reported numbers match the source data,
- all percentages are traceable to visible denominators,
- top-ranked items match the computed frequencies,
- and no unsupported claim remains in the draft.
