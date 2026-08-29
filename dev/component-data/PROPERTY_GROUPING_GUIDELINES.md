# Property Grouping Guidelines

This document defines the release-independent procedure for deriving reusable
property groups and category-order profiles from a completed component-property
audit. Apply it after the release ledger has passed the procedure in
`PROPERTY_AUDIT_GUIDELINES.md`.

The expanded concrete-variant ledger remains the authoritative audit record.
Grouping is a separate normalization and runtime-design layer: do not replace
per-variant facts with group references or rewrite documented category order to
match the product inspector.

## Design principles

1. Use an official documentation category as the primary sharing boundary.
2. Do not treat a category ID or display name alone as proof that two category
   surfaces are equivalent.
3. Share an exact category surface before extracting smaller cores or
   extensions.
4. Preserve legitimate variant, family, parent-context, and release
   differences instead of forcing them through overrides.
5. Standardize product inspector category order through reusable family order
   profiles, while retaining the documented per-variant order in the audit
   ledger.
6. Prefer shallow composition. A component should compose non-overlapping
   category groups rather than inherit through a deep or diamond-shaped group
   graph.
7. Treat component- or family-named documentation categories as family-scoped
   by default. Do not use their surface differences as candidates for broad
   cross-family sharing.
8. Prove that group expansion reconstructs every concrete variant without
   missing, duplicate, or altered property capabilities before promoting the
   design into the runtime catalog.

## Two distinct forms of order

The release ledger records the order used by the release-fixed MathWorks
property page. This is documentation evidence and must not be normalized.

The runtime catalog defines the order presented by yamada. That
order should be shared wherever practical:

- a category group owns the order of properties inside that category;
- a reusable category-order profile owns the normal order of categories for a
  component family; and
- a concrete variant records only justified additions, omissions, or local
  placement deltas from its family profile.

Do not copy a full category list into every component merely because the
runtime loader requires an expanded list today. Extend the schema or compile a
profile into that expanded representation instead.

Initial order-profile candidates include standard controls, selection controls,
numeric controls, containers, navigation and data controls, instrumentation,
axes, and menu/toolbar components. Derive the actual profiles from observed
category sequences rather than assuming one universal sequence. Common suffixes
such as callbacks, callback execution control, parent/child, and identifiers
should normally have a consistent relative order across profiles.

## Category surface identity

Normalize every category occurrence into an ordered category-surface signature.
The signature contains:

- the documented category ID and display name;
- the ordered property paths; and
- for each property, its `valueContract`, `affectsDisplay`, `previewPolicy`,
  `requiredEditor`, and `disposition`.

Documentation summaries, source URLs, and documented defaults remain audit
evidence and do not establish runtime capability identity. Runtime defaults
continue to come from the controlled default provider unless a separate design
explicitly requires static default metadata.

Two category occurrences are exact-sharing candidates only when their complete
normalized signatures match. The same category ID may therefore have several
stable surfaces, for example `interactivity.standard-control` and
`interactivity.toolbar`.

## Group kinds

Use the following kinds as design classifications rather than MATLAB class
inheritance:

1. **Exact category group** - a complete category surface shared unchanged by
   several concrete variants. This is the preferred reuse unit.
2. **Family category group** - a complete category surface shared inside one
   coherent family, even when another family uses the same documented category
   name differently.
3. **Category core and extension** - a deliberately extracted common subset and
   a small family-specific addition. Use this only when the semantic reason for
   the split is clear and repeated.
4. **Variant-local category** - a category surface that is unique, unstable, or
   clearer when kept with the concrete variant.

A one-property category group is acceptable when the official category itself
contains one property or when the definition is broadly reused and semantically
stable. Do not fragment categories into one-property mixins merely to maximize
deduplication.

## Category sharing scope

Classify every documented category in release-specific design data before
interpreting a same-name surface difference:

- `crossCutting` identifies only categories with a stable semantic role across
  unrelated component families, such as callback execution control and
  interactivity;
- `familyScoped` identifies a coherent component-family surface, such as
  Button, Gauge, Slider, Knob, axes-specific styling, or tree nodes. Exact
  matching definitions may be shared within that family, but a difference is
  normally a legitimate family or variant distinction rather than a Step 4
  cross-family conflict; and
- `variantLocal` identifies a category that currently belongs to one concrete
  variant and is not a sharing candidate.

The scope classification is a product design decision, not documentation fact.
It must be complete, version-controlled, and validated against the release
ledger. A generic-sounding heading is not automatically `crossCutting`: its
documented surface must have a stable semantic role across unrelated families.

## Acceptance criteria for a shared group

A proposed group must satisfy all of the following:

- its members share the same documented category meaning;
- its ordered property paths and capability signatures are identical, or an
  explicitly designed core/extension split accounts for every difference;
- every cross-property dependency resolves in the expanded effective surface;
- it introduces no duplicate property path when composed with other groups;
- it contains no property contributed only by a parent context;
- its name describes a stable semantic surface rather than an incidental list
  of current component IDs; and
- expansion parity can be checked mechanically against every affected concrete
  variant.

Reuse count is supporting evidence, not an absolute rule. Prefer a group used by
several variants, but retain a smaller family group when it establishes a stable
boundary that is likely to remain useful across releases.

## Parent-context boundary

Parent-contributed properties remain in parent-context rule data. In
particular, do not copy `Layout.Row` or `Layout.Column` into child category
groups. A category group may describe an intrinsic `Position` capability, while
the effective-property resolver suppresses it under a grid parent and
contributes the grid placement surface.

The grouping validator must compare both intrinsic expansion and effective
surfaces for each supported parent context.

## Derivation procedure

Perform the work in the following order:

1. Validate the expanded release ledger and freeze its input revision.
2. Generate a matrix of concrete variants, documented categories, ordered
   property paths, and normalized capability signatures. Validate a complete
   release-specific category sharing-scope classification alongside the matrix.
3. Cluster exact category-surface matches and report reuse counts, member
   variants, and observed documented positions.
4. Identify same-name `crossCutting` categories with different surfaces. Explain
   each split as a family distinction, variant distinction, parent-context issue,
   or unresolved audit discrepancy. Record `familyScoped` differences as
   family-local evidence, not as a broad-sharing review queue.
5. Accept complete exact clusters as the initial category groups.
6. Review near-matching `crossCutting` clusters. Extract a category core and extension only
   when the split is semantic, repeated, non-overlapping, and simpler than
   keeping complete family groups.
7. Analyze documented category sequences and propose a small set of reusable
   family category-order profiles. Record the frequency and exceptions for each
   proposed profile.
8. Assign each concrete variant to the closest order profile and record only
   justified category insertions, omissions, or relative-order deltas.
9. Define stable group and profile identifiers. Keep official category IDs and
   display names separately from project-specific surface/profile identifiers.
10. Expand groups, profiles, variant-local categories, and parent-context rules
    into every concrete effective surface.
11. Compare the expansion with the original ledger and reject missing paths,
    extra paths, duplicate paths, changed capability metadata, broken dependency
    targets, cycles, or unexplained order differences.
12. Review the generated report before changing the runtime component catalog.
13. Promote accepted groups and profiles family by family, with catalog-loader,
    registry, inspector, Preview, model/history, and source-generation tests.

## Required design artifacts

Before runtime promotion, retain the following reviewable artifacts:

- a generated exact-cluster and conflict report;
- a human-reviewed mapping from clusters to stable group IDs;
- proposed family category-order profiles and their documented exceptions;
- a mapping from every concrete variant to its groups, order profile, and local
  deltas; and
- a machine-verifiable expansion parity report.

Generated reports may be rebuilt from the release ledger. Human decisions,
naming rationale, and approved exceptions must remain in version-controlled
design data or documentation.

## Completion gate

Grouping design is complete for a release only when every audited property is
owned by exactly one expanded category surface, every concrete variant has a
deterministic inspector category order, every exception is explicit, and the
grouped representation reconstructs the audited intrinsic and parent-effective
surfaces without capability drift.

## Step 13 completion record (2026-08-15)

The reviewed R2024a grouping design was promoted to
`resources/component-catalog/R2024a` by
`PromoteGroupingToRuntimeCatalog.ps1`. The generated runtime catalog contains
48 concrete variants, 310 reusable property groups, and the five reviewed
category-order profiles. The v2 loader validates group ownership, concrete
variant selection, profile references and deltas, and direct-parent context
composition. `ComponentRegistryBaselineTest` compares every runtime variant's
ordered properties and capability metadata with the audited development ledger;
the generated grouping artifact separately records 48/48 intrinsic and 144/144
parent-effective expansion parity. Inspector, model/history, Safe Preview,
source parsing, and generation use the same variant-aware registry. The
licensed MATLAB R2024a full unit suite passed 83 tests with zero failures after
promotion.

This record completes Step 13 only. Phase 6.7 and 6.8 completion status remains
subject to the separate Phase 6 plan review.
