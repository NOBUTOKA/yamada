# Grid Layout Visual Editor Implementation Plan

Status: planned for MATLAB R2024a

This document expands the [Build a Grid Layout Visual Editor](ROADMAP.md#build-a-grid-layout-visual-editor)
roadmap item into an implementation sequence. It is intentionally temporary:
after the feature, tests, and public documentation are complete, remove this file
together with the completed roadmap item.

## Goal

Add direct, source-safe editing for a selected `uigridlayout` without displacing
the Property Inspector for the component selected inside that grid.

The completed workflow must let a user:

- see the active grid's row and column boundaries, track labels, occupied cells,
  and child spans on the Safe Preview;
- click an `R1`, `R2`, `C1`, or `C2` header to edit that track through an
  anchored popover;
- choose `fit`, a fixed pixel size, or a weighted `x` size and enter the
  corresponding number without using the Inspector;
- insert, delete, and reorder tracks when every affected child placement has a
  deterministic, validated result;
- drag an immediate child to another cell and resize its row or column span;
- keep `RowSpacing`, `ColumnSpacing`, `Padding`, `BackgroundColor`, `Visible`,
  and `Scrollable` in the ordinary Inspector; and
- retain Inspector editing of a grid child's `Layout.Row` and `Layout.Column` as
  the exact-value fallback.

The visual editor must never execute input application code, infer state from
editor-owned layout containers, or commit a partial multi-component change.

## Confirmed UI Decisions

### Component selection and active-grid selection are separate

`SelectedComponentId` remains the sole selection that drives the hierarchy and
Property Inspector. Add an editor-only `ActiveGridId` that identifies the grid
whose tracks are being visualized.

- When the selected component is a Grid Layout, that component becomes the
  active grid.
- When the selected component is an immediate or nested child of a Grid Layout,
  its nearest Grid Layout ancestor becomes the active grid.
- Clicking a row or column header changes neither `SelectedComponentId` nor the
  Inspector surface.
- For nested grids, only the active grid's immediate tracks and immediate
  children are sent to the overlay. Selecting the nested Grid Layout itself is
  the explicit way to enter it.
- If no model-owned Grid Layout is active, the grid overlay is absent.

This state is disposable view state. It must not be stored in `DocumentModel` or
included in generated source.

### Track editing uses an HTML popover

The overlay renders compact headers such as `R1  fit`, `R2  44 px`, and
`C2  2x`. Clicking a header opens a popover anchored to that header with:

- a mode choice: `Fit`, `Fixed`, or `Flexible`;
- a numeric value field enabled for `Fixed` and `Flexible`;
- `Insert Before`, `Insert After`, `Delete`, and directional reorder actions;
- an impact summary when the action adjusts child placements;
- an inline read-only reason or validation error; and
- explicit Apply and Cancel actions, with Enter applying and Escape or an
  outside click cancelling an uncommitted draft.

The first implementation does not resize tracks by dragging a boundary. Exact
mode/value editing in the header popover is the supported resize interaction.
This avoids silently converting `fit` or weighted tracks into fixed pixels.

### The Inspector stays component-focused

`RowHeight` and `ColumnWidth` use the dedicated grid-overlay surface and do not
produce native Inspector rows after that surface is available. The catalog's
existing `gridTrackList` editor identifier becomes the marker for this
non-Inspector editor surface.

The Grid Layout Inspector continues to use the existing native editors for:

| Property | Inspector presentation |
| --- | --- |
| `ColumnSpacing` | numeric scalar |
| `RowSpacing` | numeric scalar |
| `Padding` | ordinary `numericVector` text editor |
| `BackgroundColor` | color editor |
| `Visible` | on/off editor |
| `Scrollable` | on/off editor |

`Padding` remains a normal four-element vector. Its description or tooltip must
state the MATLAB order `[left bottom right top]`; no dedicated box editor is in
scope.

When the selected Grid Layout is itself nested in another grid, its contributed
`Layout.Row` and `Layout.Column` remain ordinary component-placement properties.
The existing read-only and omitted catalog rows for references, calculated
positions, identifiers, and callbacks are not expanded by this feature.

## Current Architecture and Required Extensions

| Current area | Current behavior | Planned extension |
| --- | --- | --- |
| `yamada.m` | Owns `SelectedComponentId`, builds overlay data, receives HTML events, and commits absolute `Position` gestures | Track `ActiveGridId`, publish grid-editor data, reject stale events, route semantic grid actions through validation, and refresh once after commit |
| `+macd/+ui/PreviewRenderer.m` | Builds registered, editor-owned Safe Preview controls and returns a stable-ID-to-handle map | Continue to own native Preview construction; expose no document mutation and add only geometry support needed by the overlay-data builder |
| `resources/EditorInteractionOverlay.html` | Draws absolute component silhouettes and handles, captures pointer events, and hosts transient Tab Group selectors | Draw grid boundaries, headers, occupancy, span handles, and the header popover; send semantic action payloads to MATLAB |
| `DocumentModel` | Applies single-component property edits and batches as undoable history | Add one preflighted multi-component grid-layout edit that updates the grid and affected child placements atomically |
| `PropertyTransaction` and `PropertyBatchValidator` | Validate one component's candidate property state | Reuse for ordinary properties; add grid-track validation and a separate document-level change set for edits spanning the grid and children |
| `ModelValidator` | Validates effective properties, hierarchy, and grid-child row/column values | Validate track-list syntax, track counts, placement bounds, and post-edit grid invariants |
| component catalog | Marks `RowHeight` and `ColumnWidth` as read-only `gridTrackList` values; spacing and padding are already editable | Promote the two track lists to overlay-editable catalog capabilities while keeping them out of native Inspector rows |
| parser and generators | Preserve expressions, parse supported literals, and replace a changed assignment through its owned source span | Reuse the existing source boundary; reject expression-backed tracks and placements before mutation and cover edited track-list output |

## UI Responsibility Split

### MATLAB UI responsibilities

The native MATLAB UI continues to own:

- the real application shell, hierarchy, palette, commands, status line, and
  diagnostics drawer;
- the Property Inspector and its existing native editors;
- Safe Preview component construction through `PreviewRenderer`;
- the `uihtml` host, its sizing, and its lifetime during Preview rebuilds; and
- visible error/status reporting after MATLAB rejects an overlay action.

MATLAB UI code must not add native row/column editor panels beside the Inspector
and must not replace the header popover with a modal dialog. Routine track
editing stays on the canvas.

### HTML layer responsibilities

`EditorInteractionOverlay.html` owns only disposable canvas interaction state:

- render the active grid frame, inner bounds, row/column boundaries, headers,
  track labels, occupancy, and selected-child span;
- open, position, validate basic field completeness for, and close the anchored
  track popover;
- capture pointer and keyboard gestures for headers, component cell moves, and
  span handles;
- render a temporary candidate and an error/read-only message returned by
  MATLAB; and
- send declarative events containing IDs, indices, modes, values, and gesture
  endpoints.

The HTML layer must not:

- maintain an authoritative copy of the document;
- derive final row/column remapping rules;
- change Preview DOM or MATLAB controls;
- evaluate MATLAB expressions;
- decide whether source-backed state is editable; or
- report success before MATLAB returns refreshed model-derived data.

### Nonvisual MATLAB controller and model responsibilities

Although not a third visible UI surface, this boundary is central to the design.
MATLAB code must:

- derive the active grid from stable model IDs;
- convert model literals and Preview geometry into a versioned overlay payload;
- treat every HTML event as untrusted input and verify its document revision,
  grid ID, component ID, indices, and numeric values;
- normalize supported track literals, compute deterministic placement changes,
  and validate the complete candidate;
- commit the change once through `DocumentModel`, record one history entry, run
  model validation, and refresh the shell once; and
- return unchanged model-derived overlay data after a rejection.

## Overlay Data and Event Contract

Extend `InteractionOverlay.Data` without changing the existing absolute-layout
component contract. Add a versioned `gridEditor` object with at least:

```text
revision
activeGridId
editable
readOnlyReason
outerBounds
innerBounds
rowBoundaries
columnBoundaries
rowTracks[]       index, kind, value, label, editable
columnTracks[]    index, kind, value, label, editable
children[]        id, rowStart, rowEnd, columnStart, columnEnd,
                  bounds, placementMode, selected, editable
draft             optional candidate and validation message
```

Use `kind` values `fit`, `fixed`, and `flexible`. Keep numeric values as JSON
numbers and presentation suffixes (`px`, `x`) in the HTML layer.

Keep the existing `Pointer` event for absolute positioning. Add a separate
`GridAction` event with explicit action names such as:

- `set-track`;
- `insert-track`;
- `delete-track`;
- `move-track`;
- `move-child`; and
- `resize-span`.

Every action includes `revision` and `activeGridId`. MATLAB rejects events from a
stale overlay after selection, undo/redo, or Preview refresh.

## Track-List Representation

Add a UI-independent track-list value object or equivalent helper that accepts
only the R2024a literal families already admitted by the catalog:

- a numeric scalar or row vector for fixed tracks;
- a character or string scalar such as `fit` or `1x`;
- a string row vector for homogeneous text tracks; and
- a row cell array containing supported numeric and text track values.

Normalize each item to a typed token while retaining enough container-form
metadata to produce a natural value after an edit. Validation must reject:

- nonfinite or nonpositive fixed sizes and weights;
- malformed weighted text;
- unsupported string matrices, column cell arrays, nested cells, and arbitrary
  objects; and
- an empty final row or column list.

The source-preservation boundary remains explicit:

- a no-edit round trip stays byte-identical;
- an untouched property assignment keeps its exact source text;
- an edited assignment is encoded canonically through `LiteralEncoder`;
- preserve a homogeneous numeric or string container when the edited result
  remains homogeneous, and use a row cell array for mixed track kinds; and
- expression-backed track lists remain visible but locked and are never replaced
  through the visual editor.

Update the audited development data and promoted runtime catalog together. Set
`RowHeight` and `ColumnWidth` to the `gridTrackList` editor identifier and an
editable audit disposition, then make `InspectorSurfaceBuilder` omit this
dedicated non-native editor from Inspector rows. Do not special-case the two
property paths only in `yamada.m`.

## Geometry and Layout Stabilization

Create a testable MATLAB-side overlay-data/geometry builder rather than adding
more geometry policy directly to `yamada.updateInteractionOverlay`.

The builder must use only:

- model-owned IDs and literal properties;
- public geometry from editor-owned Preview handles;
- the active grid's `Position`/`InnerPosition`, padding, and spacing; and
- realized immediate-child bounds from the Safe Preview.

It must never add measurement controls to the Preview, inspect undocumented
MATLAB internals, or infer application state by running the input class.

Before implementing interaction, add an R2024a geometry spike/test matrix for:

- fixed, `fit`, weighted, and mixed track lists;
- empty tracks;
- single-cell and spanning children;
- padding and nondefault spacing;
- nested grids; and
- grids inside active and inactive tabs.

Prove which track boundaries can be reconstructed exactly from public geometry.
If a boundary cannot be resolved unambiguously, publish a locked track header
with the reason and disable geometry-dependent child dragging for that grid;
exact `Layout.Row`/`Layout.Column` Inspector editing remains available. Do not
display a confidently interactive but misaligned boundary.

Generalize the existing finite geometry-stability polling only as needed for
active grids in Tab Groups. Reuse observed stable public geometry; do not add a
fixed delay.

## Atomic Grid Edit Model

Add a document-level grid change set containing:

- the target Grid Layout ID;
- before/after `RowHeight` and `ColumnWidth` values when changed;
- affected immediate-child IDs; and
- before/after `Layout.Row` and `Layout.Column` values for every affected child.

Add one public `DocumentModel` operation that:

1. verifies that the target and all affected entries still exist and are
   editable;
2. preflights every new value and source-ownership condition;
3. applies all changes with rollback on any failure;
4. records one `grid-layout-edit` history item; and
5. makes Undo and Redo restore the complete before/after snapshots.

Do not implement this by calling `setPropertyBatch` repeatedly, because that
would expose partial state and create multiple Undo steps.

## Structural-Edit Semantics

Use deterministic rules and show their impact in the header popover before
Apply.

### Insert a track

- Insert at a boundary before or after the selected track.
- Placements wholly after the boundary shift by one.
- A contiguous span crossing the insertion boundary expands to include the new
  track.
- The new track defaults to `1x` unless the user chooses `Duplicate Size`.

### Delete a track

- Reject deletion of the final remaining row or column.
- Placements wholly after the deleted track shift by one.
- A multi-track span containing the deleted track shrinks by one.
- Reject the operation when a child occupies only the deleted track; never move
  or delete that child implicitly.
- Reject the operation when an affected placement is implicit,
  expression-backed, outside the effective property surface, or otherwise not
  safely editable.

### Reorder a track

- Treat the moved track as a logical track and remap explicit child placements
  with it.
- Allow the action only when every resulting span remains contiguous.
- Reject moves that would split a span, depend on implicit placement, or require
  choosing among multiple valid remaps.

### Existing overlap

Preserve existing overlapping placements and display their occupancy. A direct
drop that would introduce a new overlap is rejected in the initial
implementation; intentional overlap remains possible through exact Inspector
editing and can be reconsidered separately.

## Child Move and Span Gestures

For an immediate child with editable literal placement:

- dragging the body previews a cell-snapped move while preserving its current
  row and column span;
- dragging a side changes one span axis;
- dragging a corner changes both span axes;
- pointer movement changes HTML draft state only;
- pointer release sends one candidate `GridAction`;
- Escape or pointer cancellation discards the draft; and
- a successful commit becomes one Undo step and restores the same selected
  component in the Inspector.

For a child with no explicit placement, show its realized cell as `implicit`.
Moving it may create explicit `Layout.Row` and `Layout.Column` only when MATLAB
can identify one unambiguous current cell and source insertion ownership.
Structural edits that depend on remapping an implicit child are rejected.

## Implementation Milestones

### 1. Establish geometry and value contracts

- Add focused tests for R2024a realized grid geometry.
- Implement track-token normalization and validation.
- Document and test the canonical edited-source boundary.
- Stop and revise this plan if public geometry cannot support correctly aligned
  headers for the required fixed/fit/weighted/mixed cases.

### 2. Add atomic model operations

- Implement the document-level grid change set and preflight validator.
- Add `grid-layout-edit` history support.
- Cover success, rejection, rollback, dirty state, Undo, and Redo.

### 3. Publish read-only grid overlay data

- Add `ActiveGridId` derivation and revisioning.
- Extract a MATLAB-side overlay-data builder.
- Render boundaries, headers, occupancy, locked reasons, and spans in HTML.
- Verify nested-grid isolation and exclusion of the editor's own Grid Layouts.

### 4. Implement track popover editing

- Add the HTML header popover and keyboard behavior.
- Route `set-track`, insertion, deletion, and reorder actions through MATLAB.
- Keep component selection and Inspector drafts unchanged when a header opens or
  an action is rejected.

### 5. Implement child movement and span editing

- Add cell-snapped draft gestures and span handles.
- Route one semantic candidate on release.
- Cover occupied cells, implicit placement, nested grids, cancellation, and
  stale-event rejection.

### 6. Promote catalog capability and finalize Inspector behavior

- Update audited development data and regenerate/promote the runtime catalog.
- Mark `RowHeight` and `ColumnWidth` as overlay-editable `gridTrackList` values.
- Exclude that editor identifier from native Inspector rows.
- Confirm spacing, padding, color, visibility, scrolling, and contributed parent
  placement properties retain their existing native editors.

### 7. Integrate generation, documentation, and verification

- Cover generated apps and parsed existing source.
- Update `README.md`, `SPECIFICATION.md`, and `doc/ARCHITECTURE.md` only when the
  supported behavior is implemented.
- Run focused suites, Code Analyzer for every changed MATLAB file, and the full
  `tests/unit` suite with zero Failed and zero Incomplete results.
- Remove the completed roadmap item and this temporary plan in the same cohesive
  implementation commit series.

## Verification Matrix

### Model and validation

- fixed, `fit`, weighted, homogeneous, and mixed track lists;
- invalid, empty, nonfinite, zero, negative, malformed, and expression-backed
  values;
- insert/delete/reorder placement remapping;
- span-contiguity enforcement;
- failed-edit rollback and one-step Undo/Redo; and
- conservative dirty-state behavior.

### Overlay and editor interaction

- active-grid derivation without changing component selection;
- row/column header payloads and locked reasons;
- popover Apply, Cancel, Enter, Escape, and outside-click cancellation;
- stale revision and mismatched-ID rejection;
- child move/span gesture commit and cancellation;
- Inspector component and transient draft preservation; and
- nested-grid and active-tab geometry stabilization.

Use deterministic MATLAB tests for the data builder and synthetic
`HTMLEventReceivedFcn` payloads, following the existing overlay tests. Add a
focused manual R2024a check for DOM positioning and keyboard focus because the
current test harness does not directly drive the HTML DOM.

### Preview, parsing, and source generation

- Preview application order for `RowHeight`, `ColumnWidth`, spacing, padding,
  and child placements;
- byte-identical no-edit output;
- canonical changed track-list assignments;
- localized child-placement changes;
- source-backed tracks and placements remaining unchanged and read-only; and
- generated source reopening to the same model state.

### Required completion evidence

- focused suites for new model, validation, overlay, Inspector, Preview, parser,
  and generator behavior pass;
- project-wide `checkcode` reports no new issues in changed MATLAB files;
- `runtests('tests/unit')` ends with zero Failed and zero Incomplete results;
- `git diff --check` passes;
- MATLAB source/tests remain UTF-8 without BOM and CRLF; and
- the final Git history contains cohesive, reviewable feature-sized commits with
  no unrelated user changes.

## Explicit Non-Goals

- Replacing the Property Inspector with an HTML property editor.
- A dedicated visual Padding editor.
- Boundary-drag conversion among `fit`, fixed, and weighted modes.
- Executing application callbacks or constructors to discover layout.
- Editing expression-backed track lists or placements.
- Silently deleting, clipping, moving, or overlapping children.
- Editing the Grid Layouts used internally by the `yamada` application shell.
- Full compatibility with releases other than MATLAB R2024a.

## Correction Plan — 2026-09-11

The initial Grid Layout implementation was reviewed against an R2024a Safe
Preview of `SimpleCalculatorApp`. The feature remains incomplete. This section
supersedes the earlier references to track reordering and establishes the
acceptance conditions required before this plan and its ROADMAP item may be
removed.

### Confirmed defects and boundaries

- `fit` tracks currently cause MATLAB-side boundary reconstruction to stop, but
  the HTML layer still draws headers at invented fixed offsets. Those headers
  do not identify the realized rows and columns and must not be shown as
  positional controls.
- The track popover has a fixed narrow width and one unwrapped action row. Its
  buttons can extend outside both the popover and the Safe Preview.
- The grid frame and child overlays use translucent fills that obscure the
  preview. The ordinary view needs only lightweight row and column separators.
- Grid Layout children are excluded from the ordinary absolute-position
  silhouette layer. Their HTML boxes accept pointer input only after they are
  selected, so an unselected child cannot be selected on the canvas.
- Track reordering (`Move Earlier`, `Move Later`, and `move-track`) is outside
  the intended feature. Remove the UI, event contract, controller route,
  planner support, tests, and documentation for it. Insertion and deletion
  remain supported.

### 1. Derive and publish only realized track geometry

#### MATLAB and model work

- Extend `GridLayoutOverlayDataBuilder` with an R2024a-tested reconstruction
  path that combines the grid interior, Padding, RowSpacing or ColumnSpacing,
  normalized track literals, immediate-child realized bounds, and explicit
  `Layout.Row` and `Layout.Column` spans.
- First add a focused geometry spike and tests for fixed, `fit`, flexible,
  mixed, padded, spaced, single-cell, and spanning layouts. Confirm which
  equations public R2024a geometry makes available before making the solver a
  supported path.
- Solve and validate row and column boundaries against the realized child
  rectangles and total interior extent. Publish bounds only when the result is
  finite, ordered, and unambiguous.
- Keep children in the payload even when a track boundary is unavailable;
  child selection must not depend on track editing geometry.
- When an empty or otherwise ambiguous `fit` track cannot be resolved, publish
  a locked reason and disable geometry-dependent movement. Do not publish a
  fabricated header position.
- Centralize the MATLAB bottom-origin to HTML top-origin conversion in the
  payload contract, including header anchors and separator coordinates, so the
  HTML layer has no fallback positioning policy.

#### HTML work

- Render a row or column header only from a MATLAB-provided realized anchor.
  Column headers align with their actual columns and row headers align with
  their actual rows, including R1 at the top of the grid.
- Remove the current 72-pixel column and 22-pixel row fallback offsets.
- Use the supplied separators and track bounds for cell hit testing and draft
  spans; never estimate a track from header position.

### 2. Simplify the grid overlay and constrain the popover

#### HTML work

- Replace blue translucent grid and child fills with 1-pixel dotted or dashed
  internal row and column separators. Retain at most a restrained outer
  selection outline.
- Display a selected child through its outline and span handles only. Keep a
  transient drag draft visually distinct without tinting the ordinary canvas.
- Remove `Move Earlier` and `Move Later` from the popover.
- Make the popover use `box-sizing: border-box`, a bounded responsive width,
  and grid or wrapping action rows: structural actions separately from
  `Cancel` and `Apply`.
- Position it from the header's bounding rectangle, clamped to the Safe
  Preview. Choose above/below and left/right according to available room so no
  element can cross into the palette or outside the preview host.

#### MATLAB UI work

- Keep the popover in `EditorInteractionOverlay.html` hosted by the existing
  `uihtml` overlay. Do not add a native MATLAB side panel or change the
  component-focused Property Inspector.
- Continue to leave `ColumnSpacing`, `RowSpacing`, and the ordinary four-value
  `Padding` array in the native Inspector.

### 3. Restore direct child selection in a Grid Layout

#### HTML work

- Give every realized immediate child a transparent, explicit selection hit
  target. The first pointer interaction on an unselected child sends a
  selection action rather than attempting a move.
- Enable move and span gestures only for the already selected child and only
  when realized track geometry is available. Preserve Escape and cancellation
  behavior for a draft gesture.
- Keep noninteractive frames and separators out of the hit-test path.

#### MATLAB controller work

- Add a versioned `select-child` GridAction. Validate its revision, active-grid
  ID, child ID, direct-parent relationship, visibility, and Safe Preview
  handle before changing selection.
- Update `SelectedComponentId`, hierarchy selection, Inspector, and overlay
  after a valid selection. Do not mutate the document, create an Undo entry, or
  set Dirty for selection alone.
- Selecting a nested Grid Layout remains the explicit transition into that
  layout: the subsequent overlay refresh makes that nested grid active and
  shows only its immediate tracks and children.

### 4. Remove track reordering end to end

- Delete the two popover buttons and all HTML emission of `move-track`.
- Remove `move-track` from `yamada.gridActionEvent` validation and dispatch.
- Remove `GridLayoutStructuralEditPlanner.move` and its focused tests after
  confirming it has no remaining callers.
- Delete or amend every user-facing planning, ROADMAP, specification, and test
  reference that claims tracks can be reordered. Insert and delete semantics
  remain subject to the existing atomic validation rules.

### 5. Required verification and completion gate

- Add deterministic builder tests that verify R1 through Rn and C1 through Cn
  align with realized R2024a bounds for fixed, `fit`, flexible, mixed, padded,
  spaced, spanning, and nested layouts.
- Add controller tests for valid child selection, stale/mismatched selection
  rejection, hierarchy and Inspector synchronization, and unchanged history
  and Dirty state after selection.
- Add regression coverage showing `move-track` is rejected and has no exposed
  HTML route.
- Perform an R2024a manual visual check with `SimpleCalculatorApp` at the
  supplied window size and a narrower Preview. Confirm that headers align,
  the popover remains inside Safe Preview, dotted separators do not obscure
  content, and each Grid Layout child can be selected by one click.
- Run focused tests, Code Analyzer on all changed MATLAB files, `git diff
  --check`, encoding/line-ending checks, and the full `runtests('tests/unit')`
  suite with zero Failed and zero Incomplete results.
- Keep this implementation plan and the ROADMAP item until all of these
  acceptance conditions have passed. Do not repeat the premature removal that
  was reverted.
