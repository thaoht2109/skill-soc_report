---
name: soc-report-analysis
description: "Use when creating a SOC-style security report in Vietnamese from raw scan or incident data, especially when the report must show attack trends, percentage-based metrics, and strict consistency with the source numbers. Triggers include: report an an toan thong tin, SOC report, phan tich su co SOC, xu the tan cong, ty le phan tram, thong ke tu so lieu dau vao, khong duoc sai so lieu."
argument-hint: "What data source should be analyzed, and what report format is needed?"
---

# SOC Report Analysis

## Purpose
Turn raw security data into a SOC-style report that is logically consistent, statistically grounded, and presentation-ready.
Bias the narrative toward edge-device exposure, remote-control footholds, and proxy/relay infrastructure when the source data supports those patterns.
Make the Overview read like an expert security analyst judgment: campaign shape first, then exact figures, then evidence-backed interpretation.

## Inputs
- Raw scan, log, incident, or inventory data.
- Any required report format, such as Markdown, HTML, or slide-friendly sections.
- Any requested framing, such as executive summary, trend analysis, or risk assessment.

## Workflow
1. Inspect the input schema and identify the authoritative fields.
2. Compute the core counts first: total records, unique assets, unique ports or services, status breakdown, and time distribution if present.
3. Derive percentages from the same totals and keep the denominator explicit.
4. Identify top items by frequency, such as IPs, ports, services, banners, or indicators.
5. Look for trend signals across time, host concentration, service concentration, and repeated fingerprints.
6. Separate facts from interpretation. Only infer attack trends that are supported by the numbers.
7. Draft the report in SOC language: concise, analytical, and evidence-based.
8. Generate Markdown (`.md`) report first. Then generate HTML (`.html`) from same content — identical numbers, same section order, enhanced presentation.
9. If the user requests a presentation form, restructure the same findings into dashboards, tables, and section blocks without changing the underlying numbers.
10. If SSH, OpenSSH, SOCKS5, or MikroTik appear prominently, frame them as remote-control foothold or relay infrastructure only when the counts and banners support that reading.
11. In the Overview, lead with the dominant campaign pattern and analyst judgment, then support it with the most important counts and ratios.
12. In Trend Analysis, prioritize service-driven campaign structure over raw time density unless timing is the dominant signal in the CSV.
13. In Conclusion, summarize the technical assessment from a security analyst perspective and, if supported by the data, reconstruct the attack flow from the trends into a short operational sequence.

## Decision Rules
- If a number cannot be derived from the source, do not guess it.
- If two fields conflict, stop and reconcile the conflict before writing the report.
- If the data is too sparse for a conclusion, state the limitation clearly.
- If a percentage is shown, include the raw count beside it.
- If multiple interpretations are possible, choose the one best supported by the observed distribution.

## Quality Checks
- Every reported total matches the input data.
- Every percentage uses a visible denominator and sums sensibly within its category.
- Top lists are sorted consistently and reflect the source data.
- Trend statements are tied to observed clusters, spikes, or concentration patterns.
- No unsupported threat claim appears in the report.

## Output Style
- Use a professional SOC analyst tone.
- Write all user-facing report content in Vietnamese unless the user explicitly requests another language.
- For the overview, start with the campaign shape first: edge devices, remote access, proxy/relay, then exact counts, then a brief expert assessment.
- For Trend Analysis, aggregate and restate the key figures from Campaign Metrics into campaign behavior, dominant services, and infrastructure pattern. Do not lead with time density unless time is the key finding.
- For Conclusion, provide expert judgment on device class, main exposed services such as SSH, HTTP admin, and API, likely use cases such as foothold, relay, or proxying, and a concise attack flow if the data supports one.
- Always use this section order unless the user explicitly asks otherwise:
	1. Overview
	2. Campaign Metrics
	3. Trend Analysis
	4. Risk Assessment
	5. Conclusion
- Keep the language precise, calm, and evidence-first.
- When asked, produce tables or charts that mirror the same computed values.

## HTML Output Structure
When generating HTML, use this template:
- **Header:** Gradient banner (`#0f3460` → `#16213e`), white text, badge for report type.
- **Metrics grid:** 4-5 cards row (`metric-card`) showing key counts with `.value` + `.label`.
- **Tables:** Striped, hover highlight, `th` dark background.
- **Risk badges:** `risk-high` (red), `risk-med` (orange) inline spans.
- **Quotes:** Light blue left-border block for expert judgments.
- **Mermaid:** `mermaid-box` container, load via CDN (`mermaid.min.js`), `theme:neutral`.
- **Responsive:** `@media(max-width:640px)` grid 2-col, narrower padding.
- **Footer:** Disclaimer text, italic, muted color.
- All numbers must match the `.md` version exactly — same counts, same percentages, same order.

## Completion Criteria
The report is complete when:
- the numbers match the source,
- the trends are explained,
- the percentages are consistent,
- the overview highlights the dominant campaign pattern without overstating unsupported claims,
- the Overview reads like expert analyst judgment grounded in the CSV,
- Trend Analysis is synthesized from Campaign Metrics and not a duplicate of time-only commentary,
- Conclusion includes security-analyst assessment of device type, main services, and supported attack flow,
- and the final narrative reads like an expert SOC assessment rather than a generic summary.
- When HTML is requested: a `.html` file is created alongside the `.md` with identical content, CSS-styled presentation, Mermaid attack flow, and responsive layout.
