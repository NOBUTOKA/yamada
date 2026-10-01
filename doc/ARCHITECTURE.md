# yamada Architecture

This document is a developer reference for the architecture implemented in the
current `yamada` source tree. It describes stable responsibilities, data flow,
and extension boundaries; it is not a delivery plan. See the
[product specification](../SPECIFICATION.md) for supported public behavior and
the [roadmap](../ROADMAP.md) for unfinished work.

## Architectural Principles

- Ordinary MATLAB `.m` class files are the persistent source of truth. The
  project does not read or write the private `.mlapp` format.
- New and opened applications converge on the same `DocumentModel`, registry,
  validation, Inspector, Preview, and generation pipeline.
- Opening a source file is a static operation. The input class, its constructor,
  callbacks, helper methods, and arbitrary expressions are never executed.
- Preview handles, Inspector controls, hierarchy nodes, and HTML overlay state are
  disposable views. Only model state is eligible for source generation.
- Existing source is changed through owned source spans. Unsupported or ambiguous
  source is preserved and can block an unsafe edit or save.
- Component and property capabilities are declarative JSON data. Executable
  behavior is selected only through fixed MATLAB allowlists.

## System Map

```text
New App ──> NewAppFactory ───────────────┐
                                         v
Open App ─> AppSourceParser ───────> DocumentModel
                                         │
                    ┌────────────────────┼────────────────────┐
                    v                    v                    v
          ComponentRegistry       ModelValidator        Editor views
          + R2024a catalog   + PropertyBatchValidator   hierarchy/Inspector
                    │                    │               Preview/diagnostics
                    └────────────────────┼────────────────────┘
                                         v
                              RoundTripGenerator
                                ├─ NewAppGenerator
                                └─ source-span edits
                                         │
                                         v
                                  diff and save
```

The main application class, [`yamada.m`](../yamada.m), coordinates these layers.
Parsing, model mutation, validation, rendering, and generation remain separate so
none of them must infer document state from live UI handles.

Save, Save As, New, Open, and editor close pass through the injected
[`DocumentLifecycleService`](../+macd/+ui/DocumentLifecycleService.m). Its native
implementation uses MATLAB dialogs and binary UTF-8 output; tests replace its
dialog, existence, and write callbacks to cover cancellation and write failures.
Only a successful write updates the file path, generated snapshot, and model save
checkpoint. The editor title is derived from the document identity and `IsDirty`.

## Package Responsibilities

| Path | Responsibility |
| --- | --- |
| [`yamada.m`](../yamada.m) | Application shell, commands, selection, view synchronization, and save coordination |
| [`+macd/+model`](../+macd/+model) | Document instance state, catalog value objects, property transactions, and undo/redo history |
| [`+macd/+catalog`](../+macd/+catalog) | Strict JSON loading and allowlisted behavior-identifier validation |
| [`+macd/+source`](../+macd/+source) | Lexical scanning, conservative parsing, literal encoding, new-source generation, and localized round trips |
| [`+macd/+validation`](../+macd/+validation) | Document invariants and typed candidate-property validation |
| [`+macd/+ui`](../+macd/+ui) | Safe Preview and Inspector presentation/adapters |
| [`resources/component-catalog/R2024a`](../resources/component-catalog/R2024a) | Runtime component, property, grouping, ordering, context, and Inspector-row data |
| [`resources/EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html) | Transparent HTML/SVG pointer and selection layer for the canvas |
| [`dev/component-data`](../dev/component-data) | Audited source data, design artifacts, and reproducible catalog-generation scripts |
| [`tests`](../tests) | Unit tests and preserved AppBase input fixtures |

## Shared Document Model

[`DocumentModel`](../+macd/+model/DocumentModel.m) is the authoritative in-memory
state for both new and parsed applications. It owns:

- class name, file path, encoding, and line-ending policy;
- exact original text and the latest generated text;
- the ordered component collection and root component identity;
- diagnostics, unknown source regions, and pending source edits; and
- bounded undo/redo history, including a conservative saved-history checkpoint
  and public dirty-state flag.

[`ComponentRecord`](../+macd/+model/ComponentRecord.m) represents one component
instance. It stores stable identity, MATLAB property name, factory, declared type,
creation arguments, parent/child IDs, origin, source spans, and ordered
`PropertyEntry` objects. Parent relationships use stable model IDs rather than
Preview handles or hierarchy nodes.

[`PropertyEntry`](../+macd/+model/PropertyEntry.m) keeps document state separate
from catalog capability state. A supported value is either:

- a parsed or generated literal that the model may edit; or
- a source-backed expression that remains read-only and retains its exact source.

Model mutators implement insertion, leaf deletion, individual and batch property
changes, reset, undo, and redo. A batch is preflighted before mutation and becomes
one history entry. Parsed deletion also retains enough intent for undo to restore
the source-generation state.

## Component Catalog and Capability Resolution

[`ComponentRegistry`](../+macd/+model/ComponentRegistry.m) is the runtime query
boundary. `createDefault` loads the packaged R2024a catalog through
[`ComponentCatalogLoader`](../+macd/+catalog/ComponentCatalogLoader.m).

The schema-version 2 manifest references:

- concrete component variants;
- reusable property groups;
- category-order profiles;
- declarative Inspector composite-row templates; and
- direct-parent context rules.

`ComponentDefinition` describes one concrete factory variant, including creation
arguments, declared MATLAB type, allowed parents, palette metadata, Preview
outline shape, and resize constraints. Variant selection prefers an exact
creation-argument match, then the most specific prefix, then an unstyled default.

`PropertyDefinition` describes one property capability. It includes the property
path, default, editability, category and order, typed value schema, style scope,
Preview/reset policies, audit disposition, and symbolic editor and validator IDs.
It never stores an instance value.

`ParentContextRule` composes the effective property surface from the selected
component and its direct parent. For example, a Grid Layout parent suppresses
absolute `Position` and contributes `Layout.Row` and `Layout.Column`. All
consumers obtain this effective surface through
`ComponentRegistry.getEffectiveProperties`.

Catalog JSON is data, not executable configuration. Loader validation rejects
unknown fields, broken references, duplicate ownership, invalid ordering, and
unknown behavior identifiers. `PropertyBehaviorRegistry` contains the finite
allowlists that bridge symbolic catalog IDs to project-owned MATLAB code.

## New and Open Workflows

### New documents

`NewAppFactory.createEmpty` creates a `DocumentModel` with one generated root
`uifigure`. Subsequent palette insertion asks the registry for the selected
variant and allowed parent, seeds required creation arguments and layout defaults,
then records the insertion in model history.

### Opened documents

`AppSourceParser.parseFile` reads source as bytes, requires valid UTF-8, detects
the existing line-ending convention, and retains the exact decoded source.
`MatlabLexicalScanner` first identifies safe statement boundaries around strings,
comments, continuations, and balanced delimiters. The parser then recognizes the
supported AppBase subset:

- class inheritance;
- component property declarations;
- direct registered factory calls;
- parent relationships; and
- direct component property assignments with supported literals.

`MatlabLiteralParser` interprets only the conservative literal subset. Callback
values, arbitrary expressions, unsupported statements, and uncertain regions are
retained as source-backed data or `UnknownSourceRegion` records. Parsing never
uses `eval` and never constructs the opened application.

## Editing and View Synchronization

The editor uses stable component IDs for hierarchy selection and Preview mapping.
After an accepted model command, `yamada.refreshShell` rebuilds or synchronizes
the hierarchy, palette, diagnostics, Safe Preview, Inspector, and command state.

Insertion eligibility is determined from catalog metadata and the selected or
nearest eligible parent. Deletion is explicit and model-validated. Absolute
canvas gestures keep a temporary candidate rectangle in editor state and commit
one `Position` change on pointer release. A selected Grid Layout child instead
uses the active-grid overlay: its cell-snapped draft is owned by HTML and a
release sends a declarative move or span candidate for MATLAB-side validation.
`GridChildPlacementPlanner` accepts only an editable literal placement of an
immediate child, rejects new overlap and out-of-range targets, and returns one
change set for `DocumentModel.applyGridLayoutEdit`.

The model, not the Preview, owns source-coordinate geometry. The editor converts
between the fitted Preview scale and source pixels and applies the catalog's
component/style-specific resize constraint before committing a candidate.

## Property Inspector

The Inspector begins with `DocumentModel.getEffectivePropertyStates`, which joins
catalog definitions with explicit instance entries. Source-only assignments that
are outside the effective catalog surface are appended as read-only rows instead
of being dropped.

[`DefaultValueProvider`](../+macd/+ui/+inspector/DefaultValueProvider.m) resolves
implicit values without changing the document. It first uses catalog or MATLAB
class metadata and then, when required, constructs one hidden, editor-owned
fixture for the allowlisted factory and direct-parent context. The result is
cached by MATLAB release and catalog surface. This controlled probe never
constructs the application being edited.

[`InspectorSurfaceBuilder`](../+macd/+ui/+inspector/InspectorSurfaceBuilder.m)
projects atomic property states into deterministic singleton or declarative
composite rows. Composite rows change presentation only; underlying property
contracts remain independent.

`RowHeight` and `ColumnWidth` have the `gridTrackList` editor capability, which
marks them for the canvas overlay rather than a native Inspector row. The normal
Grid Layout Inspector retains `RowSpacing`, `ColumnSpacing`, `Padding`,
`BackgroundColor`, `Visible`, and `Scrollable`; the child Inspector retains
`Layout.Row` and `Layout.Column` as the exact-value fallback.

[`PropertyEditorFactory`](../+macd/+ui/+inspector/PropertyEditorFactory.m) maps an
allowlisted editor ID to a native control or project-owned dialog. Editors submit
one or more changes through `PropertyTransaction`. The editor validates the
complete candidate state with `PropertyBatchValidator`, reconciles dependent
values such as `Items`/`ItemsData`/`Value`, and calls
`DocumentModel.setPropertyBatch` only after validation succeeds. An accepted
batch produces one history record and one shell refresh.

## Safe Preview and Canvas Overlay

[`PreviewRenderer`](../+macd/+ui/PreviewRenderer.m) destroys stale editor-owned
controls and rebuilds a Preview from the model hierarchy. It creates only
registered factories, applies editable literal values permitted by each
`PreviewPolicy`, skips source expressions and callbacks, and reports individual
construction or assignment failures as non-executing diagnostics. Native menu and
toolbar families are currently not rendered on the Preview canvas.

The outer Preview panel keeps a light native heading; its child is a dark-gray
scroll host. The renderer adds a padded dark content panel so all four edges of
the figure remain distinct from the scroll bars at their limits. Two fixed dark
dividers mark the viewport boundary next to visible native scroll tracks while
the canvas extends beyond the viewport. The renderer places an unscaled canvas
at the root `UIFigure.Position(3:4)` client-area size, uses the figure's
supported `Color`. The scroll content encompasses the figure and visible
component bounds, with room for resize handles. The transparent HTML overlay
is a sibling of the figure frame in that content, so component outlines remain
selectable outside a shrunken figure. The canvas itself continues to clip native
controls at the actual UIFigure boundary. The overlay's `surfaceBounds` describes
its extent in canvas pixels; SVG viewBox and HTML layer offsets preserve those
coordinates when the editing area extends beyond the canvas. All pointer events,
hit targets, and Grid Layout measurements use canvas-local
pixels. Editor window resizing repositions the fixed-size canvas without
changing the document. The frame gives the canvas a one-pixel border on each
side. Eight root resize handles remain available when the root has an editable
literal Position, including an empty document. West and south drags also update
the screen origin to anchor the opposite edge; source-backed positions remain
noneditable. A disposable HTML guide is placed in the scroll content during a
root drag, so its dashed proposed bounds can extend beyond the current canvas.
The guide disappears when the gesture ends; the overlay shows no size label.

The renderer returns a map from stable component IDs to disposable Preview
handles. `yamada` uses this map to build the transparent
[`EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html)
`uihtml` layer. MATLAB sends source-derived component outlines, selection state,
and Tab Group information to the overlay. For the nearest selected Grid Layout,
`GridLayoutOverlayDataBuilder` also publishes versioned public Preview geometry,
track headers, immediate-child occupancy, and editability. The HTML/SVG layer
owns pointer capture, outlines, resize handles, tab-selection hit targets, and
temporary grid drafts, then sends declarative pointer or grid actions back to
MATLAB. It never mutates the document directly. MATLAB rejects actions with a
stale revision, a mismatched active grid, unsupported source ownership, or an
invalid final placement.

Tab content geometry is published only after observed layout values stabilize.
Inactive-tab child outlines are omitted, and the active tab selection remains
disposable Preview state unless a supported model property is explicitly edited.

### Grid Layout Visual Editor

The editor follows one model-to-canvas-to-model flow. `DocumentModel` holds
track values and child placements. `PreviewRenderer` draws disposable MATLAB
controls from that model. `GridLayoutOverlayDataBuilder` combines model values
with the controls' realized geometry into a versioned payload. The HTML overlay
draws the grid UI and sends a proposed action to `yamada`, which validates it
and commits one model change before rebuilding the Preview. The Inspector edits
ordinary component properties alongside this canvas workflow. Preview and HTML
are disposable views of the document state.

#### Selection and editing context

`SelectedComponentId` drives the hierarchy and Inspector; the nearest selected
Grid Layout (`ActiveGridId`) drives track controls. Selection targets for visible
grid-managed children are published independently of the active grid. Otherwise
an opened document, which initially selects `UIFigure`, could not select a grid
child from the canvas. Selecting a nested Grid Layout enters that grid's immediate
tracks and children. Transparent targets are painted from outer to inner grids
in one background layer so descendants win hit testing without covering active
child controls or track settings. Selecting a child changes view state only.

#### Track and child edits

The Inspector remains focused on the selected component. `RowHeight` and
`ColumnWidth` use the compact canvas settings controls; spacing and padding stay
in the ordinary Inspector. Track editing uses explicit Fit, Fixed, and Flexible
modes instead of dragging a boundary, because a pixel drag would silently
convert a fit or weighted track to a fixed size. The HTML popover owns only the
draft. MATLAB validates the submitted action and `DocumentModel.applyGridLayoutEdit`
commits a structural edit with all affected child placements as one Undo step.
Expression-backed tracks or placements remain locked when source ownership
cannot be proved.

Inserting or deleting a track remaps explicit immediate-child placements in
the same transaction. Deleting a track occupied by a single-track child is
rejected rather than moving or deleting that child implicitly. Existing
overlaps are preserved, while a canvas drop that would create a new overlap
is rejected; exact Inspector placement remains available for intentional
overlap.

#### Geometry and interaction

R2024a exposes the grid and rendered controls' public geometry, but not the
realized rectangle of every track. `GridLayoutOverlayDataBuilder` reconstructs
track boundaries from literals, spacing, and settled Safe Preview measurements.
For `fit` measurements it prefers a direct child's `OuterPosition`, which can
include decorations omitted from its control-body `Position`; selection hit
targets still use the visible child's ordinary bounds. This distinction matters
for controls such as Range Slider, whose narrow body understates the height
required by its row. `OuterPosition` is still not a grid-cell measurement, so
this reconstruction is not guaranteed to align every separator exactly. When
geometry is ambiguous, the builder withholds geometry-dependent editing instead
of publishing a plausible but incorrect boundary. Adding invisible nested
`uigridlayout` controls as cell probes was tested and rejected: in a populated
R2024a grid they changed the native layout and did not reliably occupy the
requested cell.

An unoccupied `fit` track can have zero extent without losing its logical index.
The overlay keeps its settings control addressable and supplies a temporary drop
band during a child move; that band changes neither the Preview grid nor source.
Span-handle drags begin from the handle even when it overlaps spacing or
padding. The moving edge snaps at the midpoint between valid track edges in
either direction, independently of the perpendicular axis.

#### Preview updates and Tab visibility

Preview geometry may change after an initial Open or Tab switch. The editor
publishes an initial overlay and schedules a bounded refresh after visible grid
and child rectangles stabilize, including when no grid is selected. On a Tab
switch it immediately removes controls belonging to the hidden Tab, then
refreshes settled geometry. Visibility must be checked through every enclosing
Tab Group; a selected grid on a hidden Tab does not remain active on the canvas.

## Validation and Diagnostics

`ModelValidator` checks document-wide invariants: valid and unique identifiers,
one registered root, resolvable parents, allowed hierarchy relationships,
effective property applicability, editable/source-backed consistency, typed
property values, and supported geometry.

`PropertyBatchValidator` validates one complete candidate property state. This is
important for dependent contracts such as limits and values or item labels, item
data, multiselect mode, and selection. Validation returns user-facing messages;
document validation publishes structured `Diagnostic` objects with severity,
code, component identity, and source span where available.

Errors block unsafe generation or Save. Warnings can describe state that is
preserved but cannot be edited or rendered. The diagnostics drawer, status line,
generators, and tests consume the same diagnostic model.

## Generation, Diff, and Save

`RoundTripGenerator` is the editor's generation entry point.

- If a document has no original source, it delegates to `NewAppGenerator`, which
  owns the complete minimal AppBase class skeleton and deterministic component
  construction order.
- For an opened document, no-edit generation returns `OriginalText` unchanged.
  Edited literal assignments replace only owned `SourceSpan` ranges. New
  components require unambiguous declaration and creation anchors. Deletion is
  limited to owned non-root leaves with no unknown external reference.
- Edits are rejected if required spans are missing, deletion ownership is
  ambiguous, or calculated edits overlap.

Diff Preview compares `OriginalText` with the generated candidate before writing.
The application enables in-place Save only after Open or Save As establishes a
confirmed path and validation has no errors. Generated text is written as UTF-8
without a BOM. New documents use the host line-ending convention; opened source
preserves detected CRLF or LF text. `SourceWriter` provides the separately tested
byte-level utility for callers that need explicit line-ending normalization.

## Resource and Development-Data Boundary

Runtime code resolves resources relative to the project root:

- `resources/component-catalog/R2024a` is loaded by the registry;
- `resources/EditorInteractionOverlay.html` is loaded by `yamada`; and
- development ledgers and generation scripts under `dev/component-data` are not
  runtime dependencies.

The development ledger is the review surface for catalog research and audit
decisions. Promotion scripts generate the grouped runtime catalog; loader and
baseline tests verify that the promoted variants reconstruct the audited
intrinsic and parent-effective property surfaces without capability drift.

## Extending the Architecture

### Add or change a component or property

1. Update the release-specific audited data under `dev/component-data/R2024a`.
2. Regenerate or promote the runtime catalog rather than adding declarative
   inventory to `ComponentRegistry.m`.
3. Add only allowlisted executable behavior required by a new editor, validator,
   Preview adapter, or reset policy.
4. Test loader failure modes, registry parity, parent-context projection,
   Inspector behavior, Preview safety, validation, and source generation.

### Add an Inspector editor

1. Define a typed value schema and symbolic editor/validator identifiers.
2. Add the identifiers to the finite behavior allowlists.
3. Implement the native adapter or dialog in `+macd/+ui/+inspector`.
4. Commit through `PropertyTransaction` and the shared batch validator; do not
   mutate a component record directly from a UI callback.
5. Preserve source-backed values and test rejected drafts, atomic history,
   Preview refresh, and round-trip output.

### Extend source syntax

Extend the lexical/parser contract and source ownership model together. A syntax
form may be parsed for preservation without becoming editable. Generation must
still prove exact ownership and insertion anchors before rewriting it.

## Verification Boundaries

Tests are organized by architectural boundary:

- parser and lexical tests prove static, non-evaluating recovery;
- model and transaction tests prove atomic mutation and reversible history;
- loader and registry baseline tests prove strict catalog expansion and parity;
- Inspector and editor tests construct real hidden UI fixtures and delete them;
- Preview tests prove allowlisted rendering without input-app execution;
- generation tests cover canonical output, localized edits, source preservation,
  encoding, and line endings; and
- project-convention tests enforce MATLAB documentation, license, encoding, and
  line-ending rules.

Run focused tests for a change before the complete `tests/unit` suite. Current
known failures and unfinished product capabilities belong in
[ROADMAP.md](../ROADMAP.md), not in this architecture reference.
