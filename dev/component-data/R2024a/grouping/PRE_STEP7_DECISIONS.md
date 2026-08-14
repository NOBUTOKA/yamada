# R2024a pre-Step-7 grouping decisions

This record closes the product decisions needed before analyzing family
category-order profiles in Step 7. It is a design input, not a generated
artifact and not a runtime catalog definition. Stable group and profile IDs
are intentionally deferred to Steps 8 and 9.

## Scope decisions

`category-scope-classification.json` is the authoritative machine-readable
record of every category scope. The following decisions materially narrow the
sharing search:

- `Callbacks`, `Font`, `Font and Color`, `Identifiers`, `Parent/Child`, and
  `Position` are family-scoped. Their documented recurrence does not justify a
  broad cross-family surface.
- `Callback Execution Control` and `Interactivity` remain cross-cutting and
  may use core-and-extension composition after Step 7.
- Categories named for a component or coherent family remain family-scoped by
  default. Variant-only categories remain variant-local.

## Disposition decisions affecting grouping

- `Parent`, `Children`, `HandleVisibility`, and `Tag` remain in the audit
  ledger but are intentionally omitted from the inspector. No shared runtime
  surface is created for `Parent/Child` or `Identifiers`.
- `uifigure.Name`, `Icon`, `NumberTitle`, and `IntegerHandle` remain UIFigure
  local. `Number`, `Type`, and `UserData` remain omitted. `IntegerHandle` is
  editable as an `onOff` property and can affect the figure title together
  with `NumberTitle`.
- Parent-contributed `Layout.Row` and `Layout.Column` remain exclusively in
  `parent-context-rules.json`.

## Single-property sharing rule

A candidate with zero or one editable property remains family-local unless it
forms a deliberately approved semantic surface with more than one editable
property. This suppresses standalone shared definitions for `Position`,
`Color.BackgroundColor`, and `Figure-Based Apps Only.ShadowColor`.

The exception currently approved for later promotion is the Button-family
alignment surface. `HorizontalAlignment`, `VerticalAlignment`, and
`IconAlignment` are shared by push buttons, state buttons, and toggle buttons.
It is a Button-family shared surface, not an extension of a generic Position
core.

## Step 6 outcome

Step 6 may extract a core and extensions only for `Callback Execution Control`
and `Interactivity`. The concrete membership and stable identifiers remain
deferred until the order-profile analysis and variant assignment data exist;
the derivation must preserve every audited property capability and category
order.

## Deferred decisions after Steps 7–11

The following decisions do not affect the generated parity result and are
intentionally deferred until runtime promotion:

- The five generated profile orders are documentation-order compression data,
  not a proposal for the end-user inspector order. Inspector presentation order
  will be designed independently when the runtime catalog is promoted.
- Which concrete variants are eligible children of each parent context. The
  current parent-context ledger intentionally defines effects for an
  `eligibleDirectChild` but not a complete parent-child eligibility matrix.
  Parity therefore validates each context as a hypothetical eligible direct
  child surface. Runtime catalog promotion must supply and validate the actual
  eligibility matrix.
- Whether generated hash-suffixed exact-group IDs need curated product-facing
  aliases. The IDs are stable and sufficient for the development design layer;
  aliases can be added when a group becomes a runtime catalog API.
