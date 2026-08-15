# R2024a component documentation transcript

This directory is a development-only transcript of public MATLAB component
properties. It is deliberately separate from `resources/component-catalog/v1`:
the latter controls supported editor behavior, while these files record source
documentation before a property is audited.

The transcript is not a runtime dependency and must not be loaded by
`ComponentCatalogLoader`. A listed property is not implicitly editable, safe for
Preview, serializable, or supported by source generation.

## Schema v3 design

`schema.json` version 3 defines one concrete component variant per file. A
variant has its own stable `id`, documented factory arguments, declared type,
categories, and complete property surface. For example, `uibutton-push` and
`uibutton-state` are separate records even though both use `uibutton` as
their factory. The runtime catalog does not yet support duplicate factories;
that later implementation work is intentionally outside this documentation-data
change.

Properties remain a flat list. Each property carries `categoryId` and an order
within that category, while `documentationCategories` records the source-page
category heading and order. This avoids nesting that would make future shared
property groups and parent-dependent surface composition awkward, without
discarding the original documentation grouping. The source-page default is kept
in `documentedDefault`, separately from the remaining accepted-value text in
`documentedAcceptedValues`.

The 48 component files in [`components`](components) are the complete version 3
transcript. They were regenerated from their linked R2024a reference pages and
carry an initial product audit for every property: normalized value contract,
display effect, Safe Preview policy, required editor kind, and disposition.
Variant applicability is implicit in the containing file. Parent-dependent
geometry is recorded separately in
[`parent-context-rules.json`](parent-context-rules.json), so `Layout.Row` and
`Layout.Column` are not duplicated into each child variant.

## Source and verification rules

- Transcribe public properties only from the linked, release-fixed MathWorks
  reference page for the target release. MathWorks archive paths use lowercase
  release identifiers, for example `/help/releases/r2024a/`; do not substitute
  an unversioned current-release page or an uppercase archive path.
- Record a property even when it is read-only, callback-based, handle-valued, or
  unsuitable for Safe Preview.
- Use `documentedReadOnly` only when the reference explicitly marks the property
  read-only.
- Do not include hidden, private, or implementation properties returned by
  MATLAB class metadata.
- Use the target R2024a MATLAB runtime only as a completeness cross-check; it is
  not the documentation source.

## Progress

| Factory | Documented types/styles | Transcript status | Property count |
| --- | --- | --- | ---: |
| `axes` | `default` | complete | 155 |
| `geoaxes` | `default` | complete | 85 |
| `polaraxes` | `default` | complete | 110 |
| `uiaxes` | `default` | complete | 157 |
| `uibutton` | `push`, `state` | complete | 33 |
| `uibuttongroup` | `default` | complete | 41 |
| `uicheckbox` | `default` | complete | 27 |
| `uicolorpicker` | `default` | complete | 22 |
| `uicontextmenu` | `default` | complete | 12 |
| `uidatepicker` | `default` | complete | 32 |
| `uidropdown` | `default` | complete | 34 |
| `uieditfield` | `text`, `numeric` | complete | 38 |
| `uifigure` | `default` | complete | 48 |
| `uigauge` | `circular`, `linear`, `ninetydegree`, `semicircular` | complete | 36 |
| `uigridlayout` | `default` | complete | 24 |
| `uihtml` | `default` | complete | 21 |
| `uihyperlink` | `default` | complete | 31 |
| `uiimage` | `default` | complete | 26 |
| `uiknob` | `continuous`, `discrete` | complete | 36 |
| `uilabel` | `default` | complete | 29 |
| `uilamp` | `default` | complete | 19 |
| `uilistbox` | `default` | complete | 33 |
| `uimenu` | `default` | complete | 21 |
| `uipanel` | `default` | complete | 38 |
| `uipushtool` | `default` | complete | 20 |
| `uiradiobutton` | `default` | complete | 26 |
| `uislider` | `slider`, `range` | complete | 36 |
| `uispinner` | `default` | complete | 37 |
| `uiswitch` | `slider`, `rocker`, `toggle` | complete | 29 |
| `uitab` | `default` | complete | 24 |
| `uitabgroup` | `default` | complete | 25 |
| `uitable` | `default` | complete | 53 |
| `uitextarea` | `default` | complete | 31 |
| `uitogglebutton` | `default` | complete | 30 |
| `uitoggletool` | `default` | complete | 23 |
| `uitoolbar` | `default` | complete | 15 |
| `uitree` | `default`, `checkbox` | complete | 37 |
| `uitreenode` | `default` | complete | 15 |

All 38 catalog factories are transcribed as 48 concrete variants. The transcript
contains 1,825 style-specific public-property entries across 86 verified R2024a
archive pages. Each property records its source-page category and, where the
reference supplies them, its default and accepted-value text separately.
The property sections were also re-read for the R2024a prose `This property is
read-only.`; 162 entries explicitly record `documentedReadOnly: true`.
The read-only documentation remains authoritative; R2024a `meta.property`
observations are recorded separately as 1,565 `public`, 157 `restricted`, and
103 `unresolved` `runtimeSetAccess` values.

The component-file contract is defined in [`schema.json`](schema.json).
Parent-dependent effective-surface rules are defined in
[`parent-context-rules.json`](parent-context-rules.json). The release-independent
audit procedure is
[`../PROPERTY_AUDIT_GUIDELINES.md`](../PROPERTY_AUDIT_GUIDELINES.md).

## Ellipsis-enum audit

[`ENUM_AUDIT.json`](ENUM_AUDIT.json) is the complete R2024a audit of all 415
properties whose normalized contract kind is `enum`, including editable,
omitted, and read-only dispositions. [`ENUM_REVIEW_UNITS.json`](ENUM_REVIEW_UNITS.json)
groups those entries by `groupId + path` while retaining every derived
component and source URL. All 415 release-fixed HTML property sections were
retrieved successfully; four review units contained an ellipsis in the value
line. Their representative body/value-table decisions are recorded in
[`ENUM_REVIEW_DECISIONS.json`](ENUM_REVIEW_DECISIONS.json), and the two scripts
[`AuditEllipsisEnums.ps1`](AuditEllipsisEnums.ps1) and
[`ApplyEnumReviewDecisions.ps1`](ApplyEnumReviewDecisions.ps1) reproduce the
audit and ledger update without editing the runtime catalog directly.

## Grouping derivation artifacts

The category-oriented grouping procedure is defined in
[`../PROPERTY_GROUPING_GUIDELINES.md`](../PROPERTY_GROUPING_GUIDELINES.md). Run
[`../GenerateGroupingArtifacts.ps1`](../GenerateGroupingArtifacts.ps1) with this
directory as `-ReleaseDirectory` to validate the grouping-relevant ledger and
regenerate [`grouping`](grouping).

[`category-scope-classification.json`](category-scope-classification.json)
records the product decision that separates cross-cutting categories from
family-scoped and variant-local categories. It does not alter official
documentation categories. The generator limits the Step 4 and Step 6 review
queues to the cross-cutting scope while retaining family-local differences as
reference evidence.

The frozen baseline, category-surface matrix, exact clusters, and initial
complete shared-group candidates are JSON artifacts in that directory. The
human review queue is [`grouping/JUDGMENT_CANDIDATES.md`](grouping/JUDGMENT_CANDIDATES.md):
it separates same-name category conflicts requiring Step 4 classification from
ordered strict core/extension candidates requiring Step 6 judgment. These
derived artifacts do not change the transcript or promote any property group to
the runtime catalog.

Steps 7 through 11 use the human-reviewed
[`grouping-design-input.json`](grouping-design-input.json) and its
[`schema`](grouping-design-input.schema.json). Run
[`../GenerateGroupingDesign.ps1`](../GenerateGroupingDesign.ps1) after the
baseline generator. It writes the proposed reusable category-order profiles,
every variant's group ownership and order delta, and intrinsic plus
parent-context expansion-parity reports to [`grouping`](grouping). These remain
development design artifacts until a later family-by-family runtime promotion.
