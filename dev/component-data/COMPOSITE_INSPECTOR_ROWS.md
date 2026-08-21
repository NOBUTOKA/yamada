# Composite Inspector Row Design

## Purpose

This document defines how one Inspector row can present and edit multiple
MATLAB properties without merging their underlying property contracts. It is a
Phase 6.9 design artifact and is intended to remain applicable when another
MATLAB release catalog is generated.

## Selection rule

A composite row is justified only when the property set has one natural,
user-facing name. At least one of the following must also be true:

1. The properties are validated or committed as one candidate state.
2. One existing dialog already edits the properties together.
3. The properties form one compact control, such as paired state buttons.
4. One property determines the valid shape or interpretation of another.

Sharing a documentation category, an editor kind, or a visual effect is not
sufficient by itself. If no precise row name exists, keep separate Inspector
rows even when the implementation shares validation or transaction logic.

## Recommended names and candidate inventory

### Initial Phase 6.9 slices

| Row name | Member properties | Applies to | Intended presentation | Reason |
| --- | --- | --- | --- | --- |
| `Data & Names` | `Data`, `ColumnName`, `RowName` | `uitable` | One `Edit...` button opening the existing table-data dialog | One dialog already edits all three atomically. `Table Schema` is less precise because this group includes row data and row names. |
| `Columns` | `ColumnWidth`, `ColumnEditable`, `ColumnRearrangeable`, `ColumnSortable`, `ColumnFormat` | `uitable` | One button opening the column-settings dialog | All values describe column behavior. Per-column values are reconciled against the effective Data width; rearrangeability remains a table-wide control in the same dialog. |
| `Items` | `Items`, `ItemsData` | dropdown, list box, discrete knob, and switch variants | One button opening a paired Items/ItemsData dialog | `ItemsData` is interpreted against `Items`; both should be staged and applied together. |
| `Font Style` | `FontWeight`, `FontAngle` | all components that expose both properties | Inline bold `B` and italic `I` state buttons | Both values are binary typographic style switches and fit naturally in one compact row. |

`FontSize` is not included in the initial `Font Style` row. A later `Font` row
could combine `FontName`, `FontSize`, `FontWeight`, and `FontAngle`, but it would
need either a two-line row or a dialog in the current narrow Inspector. The
first slice should establish the multi-property contract without deciding that
larger layout yet.

### High-confidence follow-up candidates

| Row name | Member properties | Applies to | Notes |
| --- | --- | --- | --- |
| `Alignment` | `HorizontalAlignment`, `VerticalAlignment` | controls that expose both | Use compact alignment controls. Keep `IconAlignment` separate because it describes icon-to-text placement. |
| `Limit Inclusivity` | `LowerLimitInclusive`, `UpperLimitInclusive` | numeric edit field and spinner | Two independently enabled check boxes labeled Lower and Upper. Keep `Limits` separate. |
| `Callback Execution` | `Interruptible`, `BusyAction` | components exposing the callback execution core | A check box and a compact drop-down fit one row and share one documented concept. |
| `Date Restrictions` | `Limits`, `DisabledDates`, `DisabledDaysOfWeek` | date picker | One dialog can edit the complete restriction candidate while `Value` remains a separate frequent field. |
| `Grid Position` | `Layout.Row`, `Layout.Column` | direct children of `uigridlayout` | Parent-contributed composite row; absolute `Position` remains unaffected. |
| `Tracks` | `ColumnWidth`, `RowHeight` | `uigridlayout` | One grid-track dialog with separate column and row collections. |
| `Spacing` | `ColumnSpacing`, `RowSpacing`, `Padding` | `uigridlayout` | Compact paired spacing fields plus padding; one natural layout concept. |
| `Ticks` | major tick values, labels, modes, minor tick values, and modes | sliders, continuous knob, and gauges | A dedicated dialog is more natural than six independent literal/enum rows. |
| `Scale Colors` | `ScaleColors`, `ScaleColorLimits` | gauges | The arrays are interpreted together and should be edited as paired color intervals. |

### Valid but larger component-family candidates

These pass the naming rule but require substantial family-specific UI. They
should use the same infrastructure after the initial slices rather than expand
the first implementation package.

| Row name | Representative members | Family |
| --- | --- | --- |
| `Axis Limits` | X/Y/Z limits, modes, and limit methods | Cartesian axes |
| `Axis Scales` | `XScale`, `YScale`, `ZScale` | Cartesian axes |
| `Grid Lines` | major/minor grid toggles and shared grid styling | Cartesian and polar axes |
| `Ticks` | axis-specific tick values, labels, modes, and rotations | Cartesian and polar axes |
| `Map View` | map center, zoom level, and their modes | geographic axes |
| `Polar Limits` | radial/angular limits and modes | polar axes |
| `Camera` | camera position, target, up vector, view angle, and modes | Cartesian axes |
| `Title Bar` | `Name`, `Icon`, `NumberTitle`, `IntegerHandle` | `uifigure` |

### Combinations intentionally not selected now

- Keep `Visible` and `Enable` separate. `State` is too abstract, and each field
  is frequently edited independently.
- Keep `Value` separate from `Limits`. The current value and its admissible
  range are different user tasks even when validation relates them.
- Keep text content, tooltip, icon, and alignment separate. `Content` would hide
  several unrelated editors behind an imprecise label.
- Keep font and background colors separate initially. `Colors` is a possible
  space-saving presentation but provides no dependency or atomic-edit benefit.
- Keep `Position`, `Units`, resizing, and child auto-resize separate. `Geometry`
  would be broad rather than a single editing task.

## Catalog boundary

Property definitions remain atomic. Each MATLAB property keeps its own path,
value contract, disposition, Preview policy, default, and fallback editor. A
composite row is a presentation overlay and must not replace, duplicate, or
weaken those contracts.

Add a versioned development artifact at
`dev/component-data/R2024a/inspector-rows.json` and generate a runtime artifact
at `resources/component-catalog/v2/inspector-rows.json`. Add the latter to the
runtime manifest through an `inspectorRowFiles` list. Keeping this artifact
separate from property grouping prevents a change in Inspector presentation
from splitting semantic property groups or changing property parity hashes.

Each composite-row record has this declarative shape:

```json
{
  "id": "tableDataAndNames",
  "displayName": "Data & Names",
  "editor": "tableData",
  "members": [
    { "path": "Data", "role": "data" },
    { "path": "ColumnName", "role": "columnNames" },
    { "path": "RowName", "role": "rowNames" }
  ],
  "categoryId": "table",
  "orderAnchor": "Data",
  "match": {
    "componentIds": ["uitable"],
    "parentContextIds": []
  }
}
```

The schema rules are:

- `id`, `displayName`, and `editor` are nonempty scalar strings.
- `editor` is resolved through the existing allowlisted behavior boundary.
- `members` contains at least two unique paths and unique roles.
- `categoryId` identifies the category in which the composite row is shown.
- `orderAnchor` names one member in that category and determines the projected
  row position.
- Empty `componentIds` means any component with the complete matching member
  set; an explicit list narrows application.
- `parentContextIds` is empty for intrinsic groups and identifies contributed
  surfaces such as grid placement when present.
- Members may originate in different documentation categories when the named
  editing task is genuinely cross-cutting. For example, R2024a places
  `ColumnSortable` under `UIFigure-based Apps Only`, but the Inspector projects
  it into the `Columns` row in `Table`. The overlay never changes the member's
  underlying category metadata.
- One effective property path cannot belong to more than one composite row.
- Missing or omitted members cause the template not to match; they do not cause
  a partial row.
- Source-only properties that are absent from the runtime catalog remain
  independent read-only rows.

The first artifact should contain only the four initial Phase 6.9 slices. Add
follow-up candidates one vertical slice at a time after their concrete editor
and validation behavior are defined.

## Runtime representation

Add a typed `InspectorRowDefinition` runtime value with stable ID, display name,
editor identifier, ordered member path/role records, matching scope, and order
anchor. Store the loaded templates in `ComponentRegistry`; do not hard-code
component IDs or member paths in `MatlabAppClassDesigner`.

An `InspectorSurfaceBuilder` consumes the effective property states and the
matching row templates. It performs these steps:

1. Match complete templates against the selected component and parent context.
2. Replace matched member states with one composite row state at the anchor's
   category/order position.
3. Project every unmatched property state to an implicit one-member row.
4. Preserve source-only states as implicit read-only rows.
5. Reject overlapping matched templates as a catalog/runtime invariant failure.

The property set returned by the registry, model validation, Preview, and
source generation remains unchanged. Only the Inspector projection changes.

## Inspector row contract

Generalize the current single-path row binding to own an ordered member-state
array. A row receives:

- its `InspectorRowDefinition`;
- each member's definition, effective/default/raw value, explicitness, and
  editability;
- the complete effective candidate snapshot for related-property validation;
- the existing atomic batch-commit callback.

All row editors submit a property-change array. A singleton editor may submit a
one-element array. An inline composite editor such as `Font Style` may submit a
one-property batch when one state button changes. A modal editor stages any
number of member changes and submits them together on Apply. Sharing a row does
not require every user gesture to rewrite every member.

Editability remains member-specific. For example, one source-backed font style
expression disables only its own state button. A dialog that requires a
complete candidate may disable its single launch button when a required member
is unknown. Unsupported values must remain visible and source-preserved.

Transient drafts and validation results use the stable row ID plus member path,
not a single primary path. A property-path or cell-coordinate error is routed
to the corresponding child control; otherwise the composite editor host shows
the existing pale-red/error-tooltip fallback.

## Initial implementation sequence

1. Freeze the development/runtime JSON schema and four initial composite-row
   records. Update generation and strict loader fixtures without changing the
   expanded property set.
2. Add typed runtime definitions and `InspectorSurfaceBuilder`. Prove singleton
   fallback, deterministic ordering, parent-context matching, and overlap
   rejection without constructing UI controls.
3. Generalize `InspectorPropertyRow` and Inspector synchronization from one
   property state to ordered member states. Route both singleton and composite
   changes through the batch callback while preserving existing adapters.
4. Migrate `uitable.Data`, `ColumnName`, and `RowName` to one `Data & Names` row.
   Remove the duplicate launch rows and retain the existing atomic dialog.
5. Implement one `Columns` row for the column-settings dialog, including the
   table-wide `ColumnRearrangeable` control, and one `Items` row whose paired
   dialog can stage both `Items` and `ItemsData`.
6. Add the inline `Font Style` adapter with bold and italic state buttons.
   Synchronize and enable the buttons independently; preserve char/string and
   logical/on-off boundary conversions already audited for each property.
7. Promote high-confidence follow-up groups one feature-sized slice at a time.
   Do not add a row template until its row name, controls, error routing, and
   commit semantics are reviewed.
8. Run catalog/schema, surface-projection, hidden Inspector construction,
   atomic history, Preview-refresh-count, and source round-trip tests. Manual
   visible-window inspection remains opt-in under `VISUAL_VERIFICATION.md`.

## Acceptance criteria

- `uitable` exposes one `Data & Names` row and one `Columns` row, with no
  duplicate member launch buttons.
- Each Items/ItemsData pair exposes one `Items` row and commits both values as
  one candidate when both changed.
- Components with both font-style properties expose one `Font Style` row whose
  bold and italic controls remain independently editable.
- Catalog parity tests prove that grouping changes no effective property path,
  type contract, disposition, Preview policy, or generated source ownership.
- One accepted modal Apply creates one history record, one validation pass, one
  Preview refresh, and one Inspector synchronization.
- Unknown composite editor IDs, duplicate member paths, overlapping templates,
  missing anchors, invalid placement categories, and invalid context matches
  fail closed.
- Unsupported/source-backed members remain readable and are never converted to
  literals merely because another member is editable.
