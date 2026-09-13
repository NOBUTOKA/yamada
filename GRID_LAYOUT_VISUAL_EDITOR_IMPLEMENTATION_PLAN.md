# Grid Layout Visual Editor Implementation Plan

Status: active and incomplete for MATLAB R2024a

This document expands the [Build a Grid Layout Visual Editor](ROADMAP.md#build-a-grid-layout-visual-editor)
roadmap item into an implementation sequence. Keep this file and the roadmap
item until the user explicitly approves completion. Passing automated checks or
finishing the currently listed implementation tasks is not, by itself,
authorization to mark the feature complete or remove either document.

## Implementation Status

The initial implementation is present, but the 2026-09-13 ControlGallery review
reopened geometry measurement and open-time selection. The feature remains open
for the corrective work below, regression coverage, final manual review, and
the user's explicit approval. This status is not a request to remove this plan
or its ROADMAP item.

- [x] Add typed `RowHeight` and `ColumnWidth` editing for fixed, `fit`, and
  weighted tracks through atomic model changes and Undo/Redo.
- [x] Add the HTML track popover with mode/value editing, insertion, deletion,
  Apply, and Cancel.
- [x] Keep spacing, padding, color, visibility, and scrolling in the ordinary
  component-focused Inspector.
- [x] Add grid-child move and span editing for geometry that can be resolved.
- [x] Replace the first shaded overlay with restrained separators and remove
  track reordering from the UI, event contract, planner, tests, and docs.
- [x] Align track controls for the covered `SimpleCalculatorApp` geometry and
  clamp its popover to the Safe Preview in the first correction pass (`03d929f`).
- [x] Stabilize and republish Grid Layout descendant hit targets immediately
  after opening an existing file, without requiring a hierarchy selection
  (`2026-09-14`; synchronous post-`drawnow` overlay publication, with the
  deferred signature extended to Grid Layouts and their direct children).
- [x] Replace labeled row/column headers with compact settings buttons
  that remain reachable for zero-size tracks.
- [x] Make insertion controls state the axis and insertion side without
  truncation.
- [x] Support empty `fit` tracks whose realized size is zero without disabling
  the rest of the grid editor, including using a collapsed track as a move
  destination.
- [ ] Replace mixed-control `fit` reconstruction with direct, non-invasive
  Safe Preview cell measurement in `ControlGalleryApp` and other grids.
- [x] Complete the prior focused and full automated verification, Code Analyzer,
  and rendered MATLAB visual inspection of the compact settings controls.
- [x] Complete the prior narrow-preview and nested-grid review; the separate
  ControlGallery geometry review is reopened below.
- [x] Move compact track settings controls onto an external Safe Preview rail so
  they never cover a Grid Layout child.
- [ ] Republish separators from directly measured Safe Preview cell rectangles;
  retain the completed one-pixel low-contrast dotted styling.
- [x] Give nested Grid Layout child hit targets a depth order so a click selects
  the innermost direct-grid child under the pointer.
- [ ] Re-run focused, full, and rendered `ControlGalleryApp` verification for
  the reopened correction pass.
- [ ] Obtain the user's explicit approval before marking this roadmap item complete.

## Goal

Add direct, source-safe editing for a selected `uigridlayout` without displacing
the Property Inspector for the component selected inside that grid.

The completed workflow must let a user:

- see the active grid's row and column boundaries and selected-child span on the
  Safe Preview without an attention-heavy cell fill;
- click a compact row or column settings button to edit that track through an
  anchored popover;
- choose `fit`, a fixed pixel size, or a weighted `x` size and enter the
  corresponding number without using the Inspector;
- insert and delete tracks when every affected child placement has a
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

The overlay renders compact settings buttons inside the grid edge. The button
does not repeat labels such as `R1`, `fit`, or `2x`; its tooltip and accessible
name identify the axis and index. Clicking it opens a popover whose title and
fields provide that detail:

- a mode choice: `Fit`, `Fixed`, or `Flexible`;
- a numeric value field enabled for `Fixed` and `Flexible`;
- axis-specific structural actions whose full labels state the insertion side,
  such as `Insert Row Above` and `Insert Column Right`, plus Delete;
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

- render the active grid frame, inner bounds, row/column boundaries, compact
  settings buttons, occupancy, and selected-child span;
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

### 1. Establish geometry and value contracts — initial scope complete

- Add focused tests for R2024a realized grid geometry.
- Implement track-token normalization and validation.
- Document and test the canonical edited-source boundary.
- Stop and revise this plan if public geometry cannot support correctly aligned
  headers for the required fixed/fit/weighted/mixed cases.

### 2. Add atomic model operations — complete

- Implement the document-level grid change set and preflight validator.
- Add `grid-layout-edit` history support.
- Cover success, rejection, rollback, dirty state, Undo, and Redo.

### 3. Publish read-only grid overlay data — initial scope complete, follow-up required

- Add `ActiveGridId` derivation and revisioning.
- Extract a MATLAB-side overlay-data builder.
- Render boundaries, settings buttons, locked reasons, and spans in HTML.
- Verify nested-grid isolation and exclusion of the editor's own Grid Layouts.

### 4. Implement track popover editing — initial scope complete, follow-up required

- Add the HTML header popover and keyboard behavior.
- Route `set-track`, insertion, and deletion actions through MATLAB.
- Keep component selection and Inspector drafts unchanged when a header opens or
  an action is rejected.

### 5. Implement child movement and span editing — initial scope complete, follow-up required

- Add cell-snapped draft gestures and span handles.
- Route one semantic candidate on release.
- Cover occupied cells, implicit placement, nested grids, cancellation, and
  stale-event rejection.

### 6. Promote catalog capability and finalize Inspector behavior — complete

- Update audited development data and regenerate/promote the runtime catalog.
- Mark `RowHeight` and `ColumnWidth` as overlay-editable `gridTrackList` values.
- Exclude that editor identifier from native Inspector rows.
- Confirm spacing, padding, color, visibility, scrolling, and contributed parent
  placement properties retain their existing native editors.

### 7. Integrate generation, documentation, and verification — incomplete

- Cover generated apps and parsed existing source.
- Update `README.md`, `SPECIFICATION.md`, and `doc/ARCHITECTURE.md` only when the
  supported behavior is implemented.
- Run focused suites, Code Analyzer for every changed MATLAB file, and the full
  `tests/unit` suite with zero Failed and zero Incomplete results.
- Keep the roadmap item and this plan after verification. Remove them only in a
  later change made after the user explicitly approves completion.

## Verification Matrix

### Model and validation

- fixed, `fit`, weighted, homogeneous, and mixed track lists;
- invalid, empty, nonfinite, zero, negative, malformed, and expression-backed
  values;
- insert/delete placement remapping;
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

## Correction Plan — 2026-09-11 (implemented)

The initial Grid Layout implementation was reviewed against an R2024a Safe
Preview of `SimpleCalculatorApp`. The listed correction work is implemented;
the remaining feature-level gate is expanded verification, manual review, and
explicit user approval. This plan and its ROADMAP item remain until that
approval is given.

The following subsections retain the delivered design and cause record; they
are not pending implementation instructions.

### Confirmed defects and boundaries

- `fit` tracks originally caused MATLAB-side boundary reconstruction to stop, but
  the HTML layer still draws headers at invented fixed offsets. Those headers
  do not identify the realized rows and columns and must not be shown as
  positional controls.
- The track popover originally had a fixed narrow width and one unwrapped action row. Its
  buttons can extend outside both the popover and the Safe Preview.
- The grid frame and child overlays originally used translucent fills that obscure the
  preview. The ordinary view needs only lightweight row and column separators.
- Grid Layout children were excluded from the ordinary absolute-position
  silhouette layer. Their HTML boxes accept pointer input only after they are
  selected, so an unselected child cannot be selected on the canvas.
- Track reordering (`Move Earlier`, `Move Later`, and `move-track`) is outside
  the intended feature. Remove the UI, event contract, controller route,
  planner support, tests, and documentation for it. Insertion and deletion
  remain supported.

### 1. Derive and publish only realized track geometry [implemented]

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

### 2. Simplify the grid overlay and constrain the popover [implemented]

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

### 3. Restore direct child selection in a Grid Layout [implemented]

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

### 4. Remove track reordering end to end [implemented]

- Delete the two popover buttons and all HTML emission of `move-track`.
- Remove `move-track` from `yamada.gridActionEvent` validation and dispatch.
- Remove `GridLayoutStructuralEditPlanner.move` and its focused tests after
  confirming it has no remaining callers.
- Delete or amend every user-facing planning, ROADMAP, specification, and test
  reference that claims tracks can be reordered. Insert and delete semantics
  remain subject to the existing atomic validation rules.

### 5. Required verification and completion gate [partially complete]

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
- Keep this implementation plan and the ROADMAP item after these acceptance
  conditions pass. Do not remove them or call the feature complete until the
  user explicitly instructs that completion may be recorded.

## Follow-up Investigation and Correction Plan — 2026-09-11 (implemented)

This follow-up is based on the supplied `SimpleCalculatorApp` and
`ControlGalleryApp` screenshots, the current MATLAB/HTML event paths, and a
read-only R2024a geometry probe. It supersedes any earlier UI wording that calls
the track controls labeled headers or assumes every nonempty child rectangle is
equal to its complete grid cell.

The five implementation sections below are complete. Their remaining checklist
records the deliberately broader regression and approval gates that still keep
the feature active.

### 1. Make canvas selection independent of active-grid selection [implemented]

#### Confirmed cause

- On file open, `yamada` selects the root `UIFigure`. `ActiveGridId` is derived
  only from `SelectedComponentId`, so the grid-editor payload has no active grid
  until the grid or one of its descendants is selected in the hierarchy.
- `updateInteractionOverlay` excludes children whose parent is a
  `uigridlayout` from the ordinary absolute-position silhouettes. The HTML
  `select-child` hit targets are created only inside `renderGridEditor`, which
  exits when there is no active grid. Together these rules leave grid-managed
  descendants with no canvas hit target immediately after open.
- The ordinary drag-start route also rejects a Grid Layout parent, so selection
  must be a selection-only event and must not reuse absolute-position dragging.

#### MATLAB/controller work

- Publish selection targets for all visible, model-owned components whose
  realized Safe Preview bounds are available, including descendants managed by
  any Grid Layout. Keep this payload independent of `ActiveGridId` and mark
  Grid Layout-managed targets as selection-only.
- Validate the component ID, preview handle, visibility, overlay revision, and
  model ownership before updating `SelectedComponentId`. Selection alone must
  not mutate source, set Dirty, or create an Undo entry.
- After selection, derive the nearest Grid Layout ancestor as the active grid
  and refresh the hierarchy, Inspector, selection outline, and grid overlay.
  Selecting a nested Grid Layout itself must still enter that nested grid.

#### HTML-layer work

- Render transparent selection-only hit targets independently of
  `renderGridEditor`. Keep separators and grid frames out of the hit-test path.
- On the first click, send only the component-selection event. Enable grid move
  or span gestures only after the selected component and active-grid payload
  agree and usable track geometry is present.

### 2. Replace labeled headers with compact in-grid settings buttons [implemented]

#### Confirmed cause

- The current row control has a fixed width of 52 pixels and is positioned at
  `innerBounds.x - 56`. A grid close to the Preview's left edge therefore puts
  the control over the boundary toward the palette. Its `R1 fit` style text also
  consumes width without adding information needed before opening the editor.

#### HTML-layer work

- Replace row and column labels with one compact icon-only settings button per
  track. Use an accessible name and tooltip such as `Edit row 1` or
  `Edit column 2`; retain `Row 1`/`Column 2`, mode, and value inside the popover.
- Place buttons inside the grid bounds: row buttons against the inner left edge
  and column buttons against the inner top edge. Clamp their complete hit boxes
  to the Safe Preview instead of placing any part outside the grid.
- Keep the separators visually primary and the buttons low-contrast until hover,
  focus, or an open popover. Verify that the buttons do not block ordinary child
  selection; where they overlap a child, restrict the button to the smallest
  practical hit box and give the explicit settings control priority only within
  that box.

#### MATLAB payload work

- Publish stable boundary/anchor coordinates and an axis/index accessible label;
  do not make HTML reconstruct an anchor from the track's display text.

### 3. Preserve insertion direction in every button label [implemented]

#### Confirmed cause

- The popover places `Insert Before`, `Insert After`, and `Delete` in three equal
  narrow columns and applies ellipsis. Both insertion actions therefore render
  as the indistinguishable `Insert...` at the supplied window size.

#### HTML-layer work

- Generate semantic labels from the edited axis: `Insert Row Above`, `Insert
  Row Below`, `Delete Row`, or `Insert Column Left`, `Insert Column Right`,
  `Delete Column`.
- Put structural actions in a vertical full-width group, or another responsive
  layout that preserves the complete labels at the minimum supported Preview
  width. Structural action text must wrap if necessary and must never be
  ellipsized.
- Keep Cancel and Apply in a separate footer and rerun focus-order, Enter,
  Escape, and clamping checks at normal and narrow Preview widths.

### 4. Represent an empty zero-height `fit` row as an editable boundary [implemented]

#### Confirmed cause

- For a `fit` axis, the current solver needs enough child-span equality
  equations to reach full rank. An empty `fit` row contributes no child equation,
  so the whole axis becomes ambiguous and the builder returns no track bounds.
- Even if MATLAB publishes a zero-size rectangle, HTML currently requires both
  width and height to be greater than zero before creating its settings control.
  A collapsed row is therefore unreachable after it becomes zero height.

#### MATLAB/model work

- Compute explicit occupancy for every track before solving. An empty literal
  `fit` track with no explicit or conservatively possible implicit occupant is
  allowed to resolve to zero; record that result rather than treating it as a
  missing equation.
- Represent track geometry by ordered start/end boundaries with a nonnegative
  extent. Zero is a valid extent. Do not fail an entire grid merely because one
  track is collapsed; return per-axis/per-track availability and a localized
  reason only for genuinely unresolved geometry.
- Keep zero-size rows editable for `set-track`, insert, and delete, and keep them
  available as child-move drop targets. Dropping a child into an empty `fit` row
  assigns that logical row; the next Safe Preview layout then expands the row to
  the moved child's realized requirement.

#### HTML-layer work

- Draw a zero-height row as a single dotted horizontal separator and anchor its
  compact settings button to that boundary. Do the analogous thing for a
  zero-width column.
- When multiple adjacent zero-size tracks share a boundary, offset or stack
  their buttons deterministically while keeping every track addressable by
  tooltip, keyboard focus, and click.
- During a child drag, give every collapsed track a temporary minimum-size drop
  band centered on its actual zero-size boundary. The band is an editor-only hit
  target and must not change the displayed track extent or generated source.
  For adjacent collapsed tracks, lay out separate ordered drop bands so the
  intended row or column can be selected unambiguously. On hover, identify the
  logical destination; on drop, send its actual axis/index rather than a pixel
  coordinate.
- Remove the positive-width-and-height prerequisite from track-button creation;
  validate finite ordered boundaries instead.

### 5. Replace ControlGallery's conflicting fit-track equalities [implemented]

#### Confirmed cause

- `ControlGalleryApp.FormGrid` has eight `fit` rows. Rows 2, 3, 6, and 7 each
  contain two controls, and rows 1, 4, 5, and 8 contain spanning controls.
- `trackBounds` currently converts every child rectangle into a hard equality
  saying that the sum of its spanned track sizes equals that child's realized
  extent. This is invalid for a `fit` row containing controls with different
  intrinsic sizes: the grid row must accommodate its content, but every child
  rectangle need not equal the row height.
- The R2024a probe confirmed the conflicting inputs in this fixture: row 6 has a
  40-pixel linear gauge and a 60-pixel knob, while row 7 has a 20-pixel lamp and
  a 45-pixel rocker switch. Treating both observations in either row as exact
  equalities produces the displayed `Track boundaries do not agree with realized
  grid geometry` failure and disables the editor.

#### MATLAB geometry work

- R2024a does not expose computed per-track rectangles as a public
  `uigridlayout` property. Safe Preview can directly provide the grid rectangle
  and each rendered child's rectangle, but an empty cell has no rectangle of its
  own. Therefore this is a measurement-and-reconstruction path, not a single
  direct read of every row and column boundary.
- Make stabilized Safe Preview measurements the primary geometry source. After
  `drawnow`, wait until the public grid and child pixel bounds stop changing,
  then read the grid outer/inner rectangles and every immediate child's actual
  rectangle with `getpixelposition`. Do not maintain component-type preferred
  sizes or reproduce MATLAB's internal Grid Layout sizing rules in yamada.
- Separate trustworthy literal constraints from measured rectangles. Fixed
  literals and flexible ratios remain exact constraints. For `fit`, group the
  measured child rectangles by logical row or column and use their actual union
  envelope, rather than adding one equality for every child. Treat that envelope
  first as an observed minimum extent, then promote it to an exact track extent
  only when the measured neighboring positions, total inner extent, literals,
  and spacing corroborate it. Thus row 6 of `ControlGalleryApp` uses one measured
  envelope containing both the gauge and knob instead of contradictory
  `height = 40` and `height = 60` equations.
- Treat spanning children as measured aggregate bounds or validation
  constraints, not automatically as exact equations for every track in the
  span. Resolve a span only when the surrounding measured boundaries, literals,
  spacing, and padding make the result unique; do not insert a
  component-specific estimate.
- Confirm the R2024a empty-`fit` result with focused Safe Preview measurements.
  When a literal `fit` track has no occupant and the measured surrounding
  boundaries identify a collapsed interval, publish its equal start/end
  boundary and logical index. If the public measurements do not uniquely locate
  it, report that track as unresolved instead of inventing a positive height.
- Build a solver result that reports which axis or tracks are resolved. A
  conflicting or insufficient observation must not suppress child selection or
  the independently resolved axis.
- Preserve the no-execution rule: derive only from parsed literals and public
  Safe Preview geometry; do not run callbacks or user constructors.

#### Required tests and completion gate

- [x] Add an open-file regression proving a Grid Layout child can be selected
  with one canvas click while the root `UIFigure` is still the initial selection.
- [x] Add nested-grid selection tests proving that selecting a nested grid enters
  only that grid and that selection-only actions leave history and Dirty unchanged.
- [x] Add payload/static-markup tests for compact in-grid buttons and complete
  axis-specific insertion labels; keep the responsive popover implementation
  free of ellipsis and track-reordering controls.
- [x] Add fixed, flexible, occupied `fit`, empty zero-size, adjacent zero-size,
  padded, and spaced geometry tests based on stabilized Safe Preview pixel
  measurements, with no component-type sizing table.
- [x] Add spanning-track geometry regression coverage based on stabilized Safe
  Preview pixel measurements, without inferring component preferred sizes.
- [x] Add move tests proving a collapsed empty `fit` row and column appear as
  distinct logical drop targets, accept a child, and expand after the resulting
  Safe Preview refresh. Include adjacent collapsed tracks and stale-index
  rejection.
- [x] Parse and render both `SimpleCalculatorApp.m` and
  `ControlGalleryApp.m`; require editable row/column payloads and child selection
  for their nested grids without the geometry warning shown in the screenshots.
- [x] Perform a manual R2024a visual check at the supplied window dimensions and
  a narrower Preview, then run Code Analyzer, focused suites, `git diff --check`,
  encoding/line-ending checks, and the full `tests/unit` suite with zero Failed
  and zero Incomplete results.
- Keep this document and the ROADMAP item after all automated and manual checks
  pass. Mark the feature complete or remove either document only after the user
  gives an explicit instruction to do so.

## Reopened Geometry and Open-Time Selection Plan — historical geometry option, selection partially complete

### 2026-09-14 implementation update

- [x] The first-open selection defect is fixed. `refreshPreview` now publishes
  the overlay again after MATLAB completes an initial `drawnow`; deferred
  stabilization is also scheduled for any document containing a Grid Layout,
  and its signature includes every visible Grid Layout and direct grid child.
  The SimpleCalculator and ControlGallery regressions open the fixture without
  invoking a hierarchy callback; ControlGallery additionally compares the Due
  Date Picker target to its realized Safe Preview rectangle.
- [x] The direct child-probe implementation was evaluated and removed. In an
  already populated R2024a `uigridlayout`, adding a nested GridLayout probe
  changes the native layout and the probe remains at its default `100x100`
  rectangle instead of its requested cell. It is therefore not a non-invasive
  geometry source and must not be used as a fallback.
- [ ] Track-boundary alignment remains open. Select and validate a measurement
  method that does not add, reparent, hide, or otherwise change children of the
  Grid Layout being measured; retain the existing solver until a replacement
  has that evidence.

This plan supersedes the earlier claim that a union of rendered child bounds is
the realized size of every occupied `fit` track. It also supersedes the earlier
open-file selection test as sufficient evidence: that test explicitly invoked
the hierarchy callback before reading the overlay payload and therefore hid the
actual first-open failure. The completed popover, external control rail,
insertion labels, collapsed-track editing semantics, and low-contrast separator
styling remain in scope and do not need redesign.

### Confirmed causes

#### ControlGallery separator drift

- `GridLayoutOverlayDataBuilder.trackBounds` currently treats the union of
  nonspanning child `Position` rectangles as the exact size of an occupied
  `fit` track. That assumption is false for controls whose public `Position`
  describes only their control body rather than all decorations that determine
  the Grid Layout's fit requirement.
- In the rendered `ControlGalleryApp`, row 4 contains a Range Slider. Its public
  rectangle reports a height of `3.000` pixels, while a non-invasive cell probe
  reports the actual row rectangle as `39.766` pixels. The missing `36.766`
  pixels shift every separator below row 4 even though rows 1 through 3 happen
  to align.
- The all-`fit` solver has an additional validation gap: it adds a total-inner-
  extent equation only when flexible tracks exist. Eight child-derived
  equalities can therefore have full rank and be accepted even when their
  heights plus spacing do not cover the realized grid interior.
- The HTML layer is rendering the bounds it receives. Moving the line or adding
  another CSS correction cannot fix this defect; the MATLAB payload itself is
  wrong.

#### Initial open-time selection failure

- Immediately after `ControlGalleryApp` opens, the Due Date Picker hit target is
  published as `[132, 169.655, 150, 22]`. After the preview has settled and the
  overlay is explicitly refreshed, the same public control is
  `[344, 477.048, 300, 22.766]`. Waiting one second does not change the first
  payload because no refresh is scheduled.
- `scheduleOverlayRefresh` currently returns when there is no Tab Group and
  `ActiveGridId` is empty. An opened document initially selects the root
  `UIFigure`, so `ControlGalleryApp` satisfies both sides of that early-return
  condition even though it contains nested Grid Layouts whose child hit targets
  require deferred geometry.
- Even if the timer were started, `activeTabGeometrySignature` currently omits
  nonactive Grid Layouts and their children unless they have an ordinary
  literal `Position`. The signature can therefore look stable before the grid-
  managed controls reach their final positions.
- A later hierarchy selection calls `updateInteractionOverlay` after layout has
  settled, which explains why canvas selection works for the remainder of the
  session. The selection validator and depth ordering are not the first-open
  cause.

### Rejected geometry source: directly overlaid editor-owned cell probes

MATLAB R2024a does not expose realized row and column rectangles as a public
`uigridlayout` property. This proposed replacement was rejected on 2026-09-14:
adding the nested probes after the target grid has real children changes its
layout and does not yield the requested cell rectangle. The following details
are retained only as the rejected experiment record, not as implementation work.

1. Create one empty, invisible, editor-owned nested `uigridlayout` probe for
   each logical row and column of the preview grid. Give each probe zero padding
   and spacing and an explicit `Layout.Row`/`Layout.Column`; row probes span the
   columns and column probes span the rows where practical.
2. Keep probes outside `DocumentModel`, `PreviewHandles`, hierarchy, Inspector,
   selection, serialization, and source generation. Their lifecycle belongs to
   the disposable Safe Preview and ends when that preview is rebuilt.
3. After layout stabilization, read each probe with
   `getpixelposition(..., true)`, convert it once into Preview-panel coordinates,
   and publish its measured axis interval directly as the corresponding track
   bounds.
4. Accept zero width or height as a valid measured interval. R2024a testing
   confirmed that adjacent empty `fit` rows and columns return distinct logical
   probes with zero extents without expanding the grid.
5. Validate count, finiteness, ordering, containment in `InnerPosition`, and
   measured gaps against `RowSpacing`/`ColumnSpacing`. If the probe snapshot is
   not stable or consistent, withhold geometry-dependent editing and retry the
   deferred measurement; do not fall back to child-size inference.

The R2024a spike added probes to every ControlGallery row and column with
`Visible="off"`. The Range Slider rectangle before and after probe creation had
delta `[0, 0, 0, 0]`, while the probes returned the complete eight row heights:
`[16.766, 22.766, 22.766, 39.766, 65.062, 118.594, 86.531, 23.000]`.

### Responsibility split for the rejected experiment (obsolete)

#### MATLAB Safe Preview/UI layer

- Introduce an editor-owned probe registry associated with the current preview
  generation. It creates, caches, validates, and disposes probe handles without
  adding them to the document's component map.
- Have `GridLayoutOverlayDataBuilder` consume a stable probe snapshot rather
  than create UI controls or run `drawnow` itself. Remove the child-envelope
  solver and its fixed/flexible/spanning equation helpers from the track-bound
  publication path once no callers remain.
- Preserve model track kinds, values, editability, and logical indices in the
  payload, but take every displayed rectangle and drop interval from measured
  probes. Source-backed values remain read-only under the existing rules.
- Start deferred overlay stabilization whenever the rendered document contains
  a Grid Layout or Tab Group, regardless of `ActiveGridId`.
- Extend the stabilization signature to include every visible Grid Layout's
  outer/inner rectangle and every visible direct grid child's public rectangle.
  Republish selection targets and active-grid geometry only from the stable
  snapshot.

#### HTML overlay layer

- Continue to render separators, settings-button anchors, collapsed drop bands,
  and child outlines from the versioned MATLAB payload. Do not infer row height
  from a component type or compensate for the Range Slider in JavaScript.
- Keep the existing one-pixel, low-opacity dotted style and external settings
  rails. Once the payload uses probe rectangles, place each separator at the
  midpoint of the measured spacing interval between adjacent probes.
- Retain depth-prioritized selection targets. No new Inspector or native MATLAB
  property panel is introduced.

#### Model and source layers

- No document, parser, generator, Undo/Redo, or track-edit semantic change is
  required. Probes are preview instrumentation only and must never appear in
  generated AppBase source or affect Dirty state.

### Implementation sequence for the rejected experiment (obsolete)

1. Add the probe registry and focused R2024a tests for fixed, flexible,
   decorated-control `fit`, spanning, empty zero-size, adjacent zero-size, and
   nested grids. Prove that adding all probes leaves every pre-existing child
   rectangle unchanged within tolerance.
2. Replace `GridLayoutOverlayDataBuilder`'s track reconstruction input with the
   validated probe snapshot. Remove or quarantine the old child-envelope solver
   so it cannot silently become a fallback.
3. Broaden the deferred layout trigger and geometry signature, then publish one
   new overlay revision only after the opened preview stabilizes.
4. Correct the existing open-file regression test by removing its synthetic
   root hierarchy callback. Compare the first stable hit target with the actual
   Safe Preview control rectangle and select it through the overlay event while
   `UIFigure` is still the untouched initial selection.
5. Add a ControlGallery regression that compares all eight published row bounds
   and both column bounds with independent probe rectangles, specifically
   asserting that row 4 is not the Range Slider's three-pixel body height.
6. Perform an actual R2024a visual review of `ControlGalleryApp` immediately
   after Open and after selecting children in rows 1, 4, 5, 6, and 8. Verify
   separator alignment, one-click selection, nested-grid precedence, settings
   rails, zero-size tracks, and absence of geometry jumps.
7. Run Code Analyzer for every changed MATLAB file, focused geometry and
   interaction suites, `git diff --check`, encoding/line-ending checks, and the
   full `runtests('tests/unit')` suite with zero Failed and zero Incomplete.

### Pending acceptance checklist for the rejected experiment (obsolete)

- [ ] Probe creation is non-invasive for ControlGallery and the focused layout
  matrix.
- [ ] Every published track rectangle comes from a stable Safe Preview probe;
  the child-envelope solver is no longer a geometry fallback.
- [ ] ControlGallery separators align with all eight rows and both columns.
- [x] Grid-managed children are selectable immediately after Open without any
  hierarchy callback or prior component selection (verified 2026-09-14).
- [ ] Empty and adjacent zero-size `fit` tracks remain editable and valid move
  destinations.
- [ ] Focused tests, the full unit suite, Code Analyzer, file-format checks, and
  the manual R2024a review pass.
- [ ] The user explicitly approves marking the roadmap feature complete.
