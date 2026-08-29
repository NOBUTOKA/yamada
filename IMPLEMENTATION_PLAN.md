# Implementation Plan

## Goal

Build a programmatic MATLAB application that provides an App Designer-like visual workflow while keeping ordinary `.m` class files as the source of truth.

The application must support both of these starting points:

1. Create a new `matlab.apps.AppBase` class from an empty canvas or starter template.
2. Open an existing `matlab.apps.AppBase` class, inspect its supported UI structure, and edit it without silently discarding unsupported source code.

Both workflows must converge on the same component model, editor, validation, and source-generation pipeline.

## Design principles

- Keep `.m` source text as the authoritative persistent format.
- Do not use `.mlapp` as an input, output, or internal project format.
- Separate parsing, the editable component model, source generation, and editor UI.
- Preserve the original source for comparison and rollback when opening an existing app.
- Generate readable and localized Git diffs instead of rewriting an entire existing class.
- Report unsupported or ambiguous constructs explicitly and block unsafe edits.
- Do not execute an input class merely to discover or preview its UI.
- Keep the supported component and property definitions extensible.

## User workflows

### Create a new app

1. Choose **New App**.
2. Enter a valid MATLAB class name and choose an empty canvas or starter template.
3. Create an in-memory component model containing a root `uifigure`.
4. Add and configure components in the editor.
5. Validate component names, hierarchy, property values, and generated class structure.
6. Save a minimal runnable `matlab.apps.AppBase` class as a UTF-8 `.m` file.

### Open an existing app

1. Choose **Open App** and select a `.m` file.
2. Read and retain the exact original source.
3. Parse supported declarations, component creation statements, parent relationships, and property assignments.
4. Show supported components in the browser and preview canvas.
5. Show unsupported or ambiguous source regions as warnings.
6. Apply supported edits as source-level changes and preview the resulting diff.
7. Review the generated diff, then save to the opened path only after validation
   succeeds or choose a new path explicitly with Save As.

## Architecture

### Editor application

The main application is a normal `.m` class derived from `matlab.apps.AppBase`. Its responsibilities are UI composition, command handling, selection state, and coordination of the lower layers.

### Source document

The source document retains:

- Original text and file path.
- Encoding and line-ending validation results.
- Source spans for recognized declarations and statements.
- Unknown and unsupported regions.
- Parse and generation diagnostics.
- Pending edits and generated preview text.

### Component model

Each component record should contain at least:

- Stable internal identifier.
- MATLAB property name.
- Component factory, such as `uibutton`.
- MATLAB declared type where known.
- Parent identifier and ordered children.
- Supported property values.
- Source spans associated with the declaration, creation, and assignments.
- Origin: generated, parsed, or template.
- Editability and diagnostic state.

New and opened apps use this same model. A registry maps each supported factory
to a typed `ComponentDefinition`, which owns its MATLAB type, permitted parents,
creation arguments, metadata, and an ordered array of typed
`PropertyDefinition` values describing editable properties and defaults.

### Parser

The initial parser targets common App Designer-exported class structure and conservative programmatic equivalents:

- `classdef` inheritance from `matlab.apps.AppBase`.
- Component declarations in property blocks.
- Component factory calls assigned to `app.Component`.
- Parent components passed to supported factory calls.
- Direct assignments in the form `app.Component.Property = value;`.
- Grid assignments such as `app.Component.Layout.Row` and `.Column`.
- Simple literal values that can be represented without evaluation.

Parsing must account for strings, comments, continuations, and balanced delimiters. Regular expressions may identify candidates but must not be the sole authority for rewriting source.

The parser must not evaluate arbitrary expressions or instantiate the input application. Unsupported expressions remain source-backed, read-only values with diagnostics.

### Source generator

For a new app, the generator owns the entire class skeleton and emits a canonical, minimal AppBase class containing:

- Component property declarations.
- A private `createComponents` method.
- Component creation and supported property assignments.
- A public constructor that calls `registerApp`.
- A public destructor that deletes the `UIFigure`.

For an existing app, the generator applies localized replacements to recognized source spans. It must preserve unrelated methods, callbacks, comments, whitespace, and unknown statements whenever possible.

Insertion and deletion are allowed only when the relevant declaration and initialization ownership can be determined safely. Otherwise, generation stops with an actionable warning.

All generated MATLAB source must use UTF-8 without a BOM, CRLF line endings, and English comments. User app output must not inherit or receive the editor project's GPL notice automatically.

### Preview renderer

The preview renderer creates only registry-approved components from model data inside an editor-owned preview surface. It must not run constructors, callbacks, helper methods, or arbitrary property expressions from an opened app.

Absolute positioning and `uigridlayout` require different editing behavior:

- Absolute children expose move, resize, and `Position` editing.
- Grid children expose row, column, and span editing.
- Unsupported layout combinations remain visible where practical but are not rewritten unsafely.

## Initial editor layout

- Top commands: New, Open, Save As, Validate, and Diff Preview.
- Left side: component palette and component hierarchy.
- Center: editable preview canvas.
- Right side: property inspector.
- Bottom: warnings and errors.

The first version prioritizes clear selection and property editing over visual
polish. Delete is always an explicit command. Save is disabled when fatal
validation or generation diagnostics exist. New output uses the host-default
line ending and opened source retains its detected convention.

## Proposed project structure

```text
yamada.m
+macd/
  +model/
  +source/
  +ui/
  +validation/
tests/
  fixtures/
  unit/
```

Parser and generator code remain independent of live editor UI handles.

## Completed implementation milestones

### Model and new-app generation

- [x] Define diagnostics, source spans, property entries, component records, the document model, and the component registry.
- [x] Create an empty AppBase model with a root `uifigure`.
- [x] Generate a runnable minimal class.
- [x] Validate class names, component names, hierarchy, safe literals, generated UTF-8 without BOM output, host-default line endings, and GPL notices.

The model foundation uses a data-driven boundary between component records and
typed component definitions. A component record stores a factory name, declared MATLAB type,
creation arguments, hierarchy IDs, and an ordered `PropertyEntry` object array.
Property entries use paths such as `Position` or `Layout.Row`; no component class
has a fixed set of MATLAB UI properties. The registry supplies immutable
`ComponentDefinition` objects containing parent rules, typed
`PropertyDefinition` arrays, defaults, creation arguments, and extension
metadata. Consequently, adding a component or property normally requires
registering definition objects, not changing the document or component record
classes.

Homogeneous model collections use typed object arrays rather than cells:
documents contain `ComponentRecord` and `Diagnostic` arrays, component records
contain `PropertyEntry` and `Diagnostic` arrays, and property entries contain
`Diagnostic` arrays. Cells remain only where values are intentionally
heterogeneous, such as component creation arguments, or where the concrete model
type is genuinely undefined.

Parsed expressions also have a representation distinct from safe literal values.
They can therefore remain source-backed and read-only during parsing and editing
instead of being coerced into a value or silently discarded. Source spans,
diagnostics, unknown regions, original text, and pending edits have dedicated
model locations for read-only parsing and localized round-trip generation.

### Read-only source parsing

- [x] Add a representative AppBase fixture.
- [x] Parse class inheritance, component declarations, factory calls, hierarchy, and simple assignments.
- [x] Produce explicit warnings for unsupported constructs.
- [x] Verify that parsing does not execute input code.

The parser uses a lexical scanner to identify statement boundaries without evaluating
the source. It handles quoted text, line and block comments, balanced delimiters,
and continuations before the AppBase parser recognizes its limited structural
subset. `AppSourceParser` retains the original decoded source, file path, line
ending convention, component and property source spans, typed unknown source
regions, and diagnostics in the shared document model.

Opened source files must be valid UTF-8. The parser reports invalid UTF-8 as a
blocking error and does not create editable component records, preventing a
lossy write-back. It retains the source file's detected line-ending convention
(`CRLF`, `LF`, or `None`) for round-trip output. New documents use CRLF on
Windows and LF on Linux or macOS. `SourceWriter` supports either convention.

The parser accepts only Registry-supported direct factory calls and direct
`app.Component.Property = value` assignments. A conservative literal parser
accepts text, logicals, real numeric matrices, and row cell arrays; all other
values remain read-only source expressions. Assignments found before a supported
component creation are retained as unknown regions instead of being mistaken for
initialization, which prevents callback behavior from overriding the initial UI
model. The parser reads files as bytes and never instantiates or executes the
input class.

### Safe round-trip generation

- [x] Preserve exact source when no edits are made.
- [x] Implement localized changes for supported property assignments.
- [x] Add safe insertion of generated components.
- [x] Add conservative deletion with ownership checks.
- [x] Compare original and generated source before saving.

`RoundTripGenerator` treats parsed source as immutable until
an editable literal changes. It keeps no-edit output byte-for-byte identical,
uses existing source spans for direct-assignment replacements, and exposes the
rewritten `GeneratedText` alongside `OriginalText` for save-time diff preview.
Generated components are inserted only after complete parsed declaration and
creation anchors are found. Explicit deletion is limited to non-root leaf
components with fully owned declaration, creation, and property spans; any
additional source reference blocks generation with an actionable diagnostic.

### Editor shell

- [x] Implement the main AppBase editor class.
- [x] Connect New and Open workflows.
- [x] Add hierarchy selection, preview rendering, property inspection, and diagnostics.

`yamada` is a programmatic AppBase editor shell.
Its New and Open commands converge on `DocumentModel`; Open remains a parser-only
workflow. The shell displays a component hierarchy, a registry-only preview that
never constructs the opened class, read-only property inspection, structured
diagnostics, validation, Save As, and an original-versus-generated source view.

### Standard MATLAB R2024 component catalog

- [x] Register the standard persistent MATLAB R2024 AppBase component catalog:
  common controls, containers, navigation and data controls, axes,
  instrumentation components, HTML component, menus, context menus, and toolbar
  tools.
- [x] Include R2024a `uicolorpicker` support and style metadata for components
  whose factory has multiple creation forms.
- [x] Record programmatic-only axes and parent-dependent components as metadata
  so specialized UI and generation paths can apply their construction rules.
- [x] Add and runtime-validate `ControlGalleryApp`, `AxesExplorerApp`,
  `NavigationDataApp`, and `FigureToolsApp` fixtures in addition to the
  representative `SimpleCalculatorApp` fixture.
- [x] Use fixture parsing and Safe Preview tests to improve string and logical
  literal handling, continued factory calls, safe name/value factory arguments,
  nested grids, fitted preview geometry, and self-host parsing.
- [x] Keep callback name/value pairs and other non-literal creation values as
  read-only source while retaining the renderable parts of their component.
- [x] Omit native menus and toolbars from Safe Preview while preserving their
  parsed model/source representation; dialog invocation functions remain out of
  scope because they are not persistent AppBase components.
The audited typed Inspector catalog extends this component inventory without
changing the registry, parsing, or Safe Preview coverage recorded above.

### Canvas editing

#### Objective

Turn the read-only Safe Preview into an editing canvas without weakening the
source-preserving boundary. Every canvas action must first mutate the shared
`DocumentModel`; the hierarchy, inspector, preview, validation, and source
generators then consume that model. Preview graphics handles are disposable UI
state and must never be treated as the source of document state.

The canvas-editing milestone covers ordinary persistent visual components that have
a registry-supported factory, a selected supported parent, and canonical
parent-first construction. It deliberately excludes the root `uifigure`,
native menus/toolbars and their child tools, `uitreenode`, and factory styles or
programmatic-only axes needing dedicated construction rules. Those records
remain parseable and source-preserved, but their insertion or geometry editing
will show an actionable unavailable-state message rather than guessing.

#### Model and edit-history contract

1. Add a model-owned component-creation helper that derives the declared type,
   permitted parent, creation arguments, and safe initial editable properties
   from `ComponentRegistry`. It will create opaque IDs and collision-free MATLAB
   property names deterministically, seed an absolute `Position` for ordinary
   children, and seed `Layout.Row`/`Layout.Column` when the selected parent is a
   `uigridlayout`. The helper must reject ineligible factory/parent combinations
   before mutating the document.
2. Add explicit model operations for insertion, leaf deletion, property changes,
   and component reattachment. `DocumentModel` remains responsible for the
   ordered `Components` collection, the reciprocal parent/child links, and
   `PendingEdits`; UI callbacks must not modify a `ComponentRecord` or its
   `Children` collection directly.
3. Represent each successful operation as a reversible, typed edit record in a
   document-owned history. The record retains the component identity and prior
   state needed to undo/redo: old/new literal values for property edits; parent
   ID and sibling index for insert/delete; and the exact pending-deletion intent
   for parsed leaves. Undoing an insertion removes the generated record without
   adding a deletion intent; undoing a parsed deletion restores the same record
   and removes only its matching intent. Redo reapplies the same operation.
4. Clear the redo branch after a new edit, retain a bounded history, and expose
   `canUndo`/`canRedo`. History is in-memory editor state: it is reset on New and
   Open, and a successful Save establishes the new source baseline and clears
   only history that has been persisted. No source is written by an edit or an
   undo operation.
5. Keep current conservative `RoundTripGenerator` ownership checks unchanged.
   A parsed-component deletion is allowed to enter history but Save/Diff remains
   blocked if its declaration, creation, property, or external-reference checks
   are ambiguous. This preserves the existing safe failure mode.

#### Canvas and palette UI

1. Extend the main editor layout with a categorized palette and an edit command
   surface containing Delete, Undo, and Redo. Categories come from registry
   `Metadata.Category`; the palette lists only canvas-insertion-eligible factories.
   Selection changes recompute enabled state using the selected component and
   registry parent rules.
2. Palette insertion uses the selected component as the parent when valid. If a
   leaf control is selected, it uses the nearest selected ancestor that is a
   permitted parent; if none exists, insertion is disabled and the status line
   explains the valid-parent requirement. This avoids silently moving a
   component to an unrelated container.
3. `PreviewRenderer` returns the existing component-ID-to-preview-handle map to
   the editor. The editor attaches selection and interaction callbacks only to
   those editor-owned handles after each render. A visible selection adornment is
   rendered in preview-surface coordinates; it is rebuilt with the preview and
   never stored in the model or generated source.
4. Clicking a preview component selects its stable ID, synchronizes the
   hierarchy and inspector, and does not invoke an application callback. The
   root surface remains selectable but cannot be deleted or moved by canvas drag.
5. Delete is always explicit: a toolbar/menu command and the Delete key invoke
   the same confirmation-free, model-validated leaf deletion command. It is
   disabled for the root, non-leaves, read-only components, and components whose
   source safety will be known only at generation time; the latter remain
   deletable but surface generator diagnostics before Save.

#### Layout editing semantics

1. Classify a selected component by its immediate model parent, not by the
   preview handle: children of `uigridlayout` use grid editing; all other
   eligible visual children use absolute editing. Do not mix `Position` with
   `Layout.*` for a single command.
2. For absolute children, support drag-to-move and eight-direction resize grips
   on the selection adornment. Convert pointer deltas from scaled preview pixels
   back to source pixels using the renderer's current scale, round to integer
   pixels, constrain width/height to at least one, and clamp the result to the
   editable parent client rectangle. Commit one history record on mouse release,
   not one record per pointer-motion event. The inspector updates `Position` as
   a normal editable literal.
3. For grid children, expose integer Row, Column, RowSpan, and ColumnSpan
   controls in the inspector/command surface. Read and write the existing model
   paths directly (`Layout.Row` and `Layout.Column` accept either scalar or
   two-element span values); do not edit a temporary `Layout` value. Normalize a
   scalar to a one-cell span, reject values below one, and validate placement
   against numeric or currently resolvable grid row/column definitions. Dragging
   grid children is out of scope for this slice, so grid placement remains
   explicit and predictable.
4. If a parsed layout value is a nonliteral expression, retain it read-only and
   disable the relevant editing control. If dimensions use flexible forms that
   cannot be resolved safely (for example `"1x"`, `"fit"`, or expression-backed
   definitions), permit only positive coordinates and defer occupancy/bounds
   diagnostics to the Grid Layout Visual Editor task in
   [ROADMAP.md](ROADMAP.md); never coerce or rewrite the grid definition.

#### Validation, diagnostics, and generation

1. Extend validation with editor-facing diagnostics for invalid insertion parent,
   unsupported palette factory, nonleaf/root deletion, malformed `Position`,
   malformed grid coordinate/span, and grid placement that is provably outside a
   numeric layout. Existing source-generation errors remain authoritative for
   parsed-source ownership.
2. After every committed edit, refresh validation, hierarchy, preview,
   inspector, diagnostics, command enablement, and Save state from the model.
   A failed edit makes no model or history change and reports its reason in the
   status/diagnostics area.
3. Reuse the existing generators. New documents emit added components in normal
   generation order. Parsed documents use the existing anchored insertion and
   conservative deletion paths; focused round-trip tests cover
   palette-created components, position edits, grid-layout edits, undo, and
   redo, proving localized source diffs.

#### Tests and verification

1. Add model tests for deterministic default creation, unique names, allowed
   parents, reversible insertion/deletion, property undo/redo, redo-branch
   clearing, and preservation/removal of matching pending-deletion intents.
2. Add editor interaction tests that construct the editor, `drawnow`, invoke
   callbacks or testable command methods, assert the model and enabled states,
   and delete every fixture. Test absolute coordinate scaling separately from
   the renderer so Safe Preview scaling cannot leak into generated `Position`.
3. Add generator tests for localized `Position`, `Layout.Row`, and
   `Layout.Column` replacements plus insertion/deletion after undo/redo. Keep a
   no-edit parsed-source test byte-for-byte identical.
4. Run the relevant MATLAB tests through the interactive licensed account.
   Cover new-app absolute and grid examples and at least one parsed fixture.
   Verify selection state, no callback execution, source-coordinate geometry,
   grid span behavior, Delete/Undo/Redo, and an intentional
   unsupported-component message.

#### Delivery sequence

1. Land the model creation, mutation, validation, and reversible-history layer
   with unit tests.
2. Land the palette, commands, and selection synchronization on the Safe
   Preview, with construction/destruction editor tests.
3. Land absolute geometry editing and its scale-aware tests.
4. Land grid row/column/span controls and boundary tests.
5. Finish round-trip coverage and an end-to-end MATLAB test run before declaring
   canvas editing complete.

#### Canvas-editing completion record

**Status: complete (assessed 2026-08-11).**

- The model-owned creation, mutation, validation, leaf deletion, and reversible
  history layer is implemented. `ModelTest` covers deterministic insertion,
  allowed parents, seeded grid coordinates, undo/redo, redo-branch clearing,
  pending-deletion restoration, and invalid geometry diagnostics. Focused
  round-trip tests cover localized `Position` and `Layout.Row` edits.
- The editor shell provides the categorized palette with documented component
  display names, insertion by palette double-click, hierarchy selection,
  inspector editing, Delete, Undo, and Redo. Delete, Undo, and Redo are exposed
  through the Edit menu; Undo and Redo are also official MATLAB toolbar tools.
  The keyboard routes are Delete, Ctrl+Z, and Ctrl+R respectively.
- Absolute-layout components support SVG-overlay selection, drag-to-move, and
  eight-direction resizing. Gestures update only disposable preview state until
  mouse release, then commit a single model/history edit in source pixels.
  Component definitions own resize constraints and overlay shapes, so controls
  with fixed dimensions or aspect-ratio constraints are resized without
  repeatedly assigning invalid preview `Position` values.
- Grid children continue to use explicit inspector edits of `Layout.Row` and
  `Layout.Column` (including spans), rather than drag editing. This is the
  completed canvas-editing boundary. Visual grid rearrangement is tracked in
  [ROADMAP.md](ROADMAP.md).
- The integrated `uihtml` SVG interaction layer supplies selection outlines and
  handles without invoking application callbacks. Slider, Switch, and circular
  instrumentation outlines have component-specific interaction geometry. Tab
  Groups expose only their outer frame and tab strip as their own hit targets,
  leaving active-tab content selectable. The overlay selects tabs through its
  own selector and publishes active-tab child geometry only after displayed
  pixel positions have stabilized; inactive-tab child outlines are omitted.
- The canvas-editing implementation was delivered in cohesive commits from
  `481c985` through `d409a02`, including the follow-up fixes for constrained
  controls and tab geometry. The later parser-only commit `4cbd05d` does not
  change the canvas-editing assessment.
- `EditorInteractionTest` constructs and destroys real editor `uifigure`
  fixtures and verifies the palette, hierarchy, inspector, toolbar, Edit menu,
  and tab-selector interaction route. The licensed MATLAB R2024a full suite
  passes **47 tests with zero failures**. Safe Preview remains registry-only and
  does not execute input-app callbacks.

Work beyond this completed boundary, including native hierarchy editing,
factory-style and programmatic-axes construction, and drag-based Grid placement,
is tracked as independent tasks in [ROADMAP.md](ROADMAP.md).

### Typed property editing and component-specific Inspector

This section records the catalog and Inspector architecture that is already in
place.

#### Objective

Replace the current literal-table inspector with a registry-driven property
editor that exposes supported common and component-specific properties even when
the selected instance has no existing assignment. Editing an unassigned property
creates a model-owned assignment; resetting it removes that assignment when
source ownership makes removal safe.

Use the MATLAB R2024a catalog as the versioned scope. Audit the
public properties of every declared component type and factory style, then
explicitly classify relevant appearance, content, state, interaction, layout,
and identification properties as editable, visible read-only, or intentionally
omitted. Callback code and arbitrary expressions remain read-only and must never
be evaluated or installed on Safe Preview handles.

The attached App Designer Button inspector is the first acceptance slice. Its
planned surface includes `Text`, `WordWrap`, horizontal and vertical alignment,
`Icon`, `IconAlignment`, font and color properties, `Visible`, `Enable`,
`Tooltip`, `ContextMenu`, `Position`, `Interruptible`, `BusyAction`,
`HandleVisibility`, and `Tag`, subject to the actual R2024a push/state type.

#### JSON catalog architecture

1. Keep declarative component and property specifications out of
   `ComponentRegistry.m` in the strict versioned JSON catalog under
   `resources/component-catalog/R2024a`. Keep one component file per supported
   variant, shared property-group files for genuinely common capabilities, and
   a `catalog.json` manifest that fixes the schema version, MATLAB release,
   component file list, and deterministic load order. Do not discover catalog
   files implicitly.
2. Add a dedicated `ComponentCatalogLoader` that reads JSON with MATLAB's
   built-in `fileread` and `jsondecode`, validates it, resolves property groups
   and style overrides, normalizes decoded MATLAB values, and constructs typed
   `ComponentDefinition` and `PropertyDefinition` arrays. `ComponentRegistry`
   remains the runtime query/index API; `createDefault` delegates catalog
   construction to this loader instead of containing the standard catalog.
3. Use a small, versioned project schema rather than exposing arbitrary MATLAB
   structures. Reject unknown fields, unsupported schema versions, duplicate
   factories or property paths, missing references, invalid defaults, unknown
   styles, and invalid category/order data. Report the source file and logical
   JSON path for every load error, and fail the entire catalog load rather than
   returning a partially usable registry.
4. Resolve definitions in one documented order: shared property groups first,
   component-local definitions second, and style-specific additions,
   exclusions, or explicit overrides last. Duplicate definitions are errors
   unless the later entry declares an override; do not implement unrestricted
   or recursive inheritance between component files.
5. Store only declarative data in JSON. Editor and validator names are symbolic
   identifiers resolved through MATLAB-owned allowlists; the loader must not use
   `eval`, deserialize function handles, or invoke a function named freely by a
   catalog file. Specialized validation, preview assignment, model mutation,
   and source editing remain project-owned MATLAB code.
6. Use standard JSON values for strings, logicals, finite numbers, arrays, and
   objects. Represent any required MATLAB-specific literal through an explicit,
   schema-approved tagged form that is parsed by the existing safe literal
   boundary; never embed executable MATLAB expressions. Keep audit notes and
   omission reasons as data fields because strict JSON comments are not part of
   the catalog format.
7. Make the loader accept an explicit catalog root for unit fixtures while the
   default application resolves the project-owned packaged resource directory.
   Cache only a fully validated immutable catalog, and provide a deterministic
   reload path for tests and future catalog-version selection.
8. Keep catalog JSON reviewable as UTF-8 text, validate every catalog file in
   tests, and include resources in packaging/deployment checks. Catalog edits
   should normally change one component file or shared group and its focused
   tests rather than a monolithic MATLAB registry method.

#### Parent-dependent property applicability

1. Separate intrinsic component properties from properties contributed or
   suppressed by the direct parent. One typed registry effective-property query
   is shared by insertion, parsing, validation, and the inspector.
2. Represent allowlisted direct-parent contexts declaratively: Grid layout,
   ordinary absolute positioning, and structural parents such as tab groups,
   button groups, trees, menus, and toolbars.
3. A direct `uigridlayout` parent contributes `Layout.Row` and
   `Layout.Column` and suppresses `Position`. An ordinary absolute parent
   contributes `Position` without `Layout.*`. Structural parents expose no
   geometry unless a reviewed rule explicitly declares it.
4. Keep hierarchy, ordering, `SelectedTab`, `SelectedObject`, and comparable
   relationships separate from geometry-property injection.
5. Preserve context-inapplicable opened-source assignments as source-backed
   read-only state; never discard them silently.
6. Freeze intrinsic definitions and representative direct-parent effective
   projections. Compatibility uses the effective surface rather than duplicated
   invalid `Layout.*` entries.
#### Runtime property capability contract

1. Extend `PropertyDefinition` so each loader-created typed definition exposes
   the JSON-declared display name, category and order, value schema, editor kind,
   allowed values or range, default behavior, style applicability, preview
   applicability, validation identifier, audit disposition, and reset policy.
   Consumers use this typed API and do not inspect decoded JSON structures.
2. Resolve intrinsic definitions against the direct-parent context before
   joining them with instance state.
3. Keep `PropertyDefinition` as capability state and `PropertyEntry` as instance
   state. Join definitions with entries in the inspector so unassigned,
   explicitly assigned, and source-backed nonliteral values remain distinct.
4. Audit every catalog factory and supported style against MATLAB R2024a
   property documentation. Record a reason for every read-only or omitted
   candidate; runtime introspection alone must not silently expand the contract.
5. Define separate property surfaces when styles have different declared types,
   including push/state buttons, text/numeric edit fields, slider/range slider,
   tree/check-box tree, gauges, knobs, and switches.
6. Model document-owned handle references separately from literals. Initially
   provide safe selectors for `ContextMenu` and comparable registry-approved
   references; preserve unsupported handle expressions as read-only source.

#### Inspector UI and typed editors

1. Replace the editable three-column `uitable` with a scrollable categorized
   inspector generated from the registry effective-property query. Categories include component-specific
   content, font and color, interactivity, position/layout, callback execution
   control, and identifiers; read-only values and diagnostics remain visible.
2. Provide adapters for text, logical values, enumerations, scalar numbers,
   fixed and variable numeric vectors, colors, string/item lists, file-backed
   icon/image paths, and model-owned references. Free-form MATLAB literal input
   is only an explicit fallback for a supported schema without a richer adapter.
3. Validate before model mutation and show errors beside the property without
   losing the user's editor text. Type, size, range, dependency, and style rules
   come from definitions or named validators, not scattered UI conditionals.
4. Commit successful changes through `DocumentModel.setProperty` and existing
   undo/redo. Coalesce a continuous widget gesture into one history edit; failed
   edits change neither the model nor history.
5. Add per-property reset. Remove a generated or unambiguously owned assignment
   and restore the effective default; disable reset with an explanation for
   ambiguous parsed source. Structural properties such as `Position` may retain
   a seeded editor default instead of becoming absent.
6. Preserve selection, collapsed categories, and scroll position across refreshes
   when selection is unchanged. Inspector controls are never document state.

#### Model, preview, validation, and generation

1. Add model and history operations for property removal/reset. Undo and redo
   restore absent, literal, and source-backed states, including prior source-span
   and editability information where applicable.
2. Seed only structural and intentionally canonical properties on insertion.
   Show other effective defaults from the versioned catalog without creating
   redundant `PropertyEntry` assignments merely by selecting a component.
   Resolve `Position` versus `Layout.*` from the direct parent before seeding.
3. Apply committed preview-safe values through `PreviewRenderer`. On a preview
   mismatch or MATLAB rejection, retain model/source state, report a targeted
   diagnostic, and rebuild disposable preview state without executing callbacks.
4. Use the same schema and parent-context resolver for inspector, parsing, and
   validation. Reject values incompatible with the factory, style, or parent
   while preserving unsupported opened-source assignments.
5. Emit only explicit and structurally required assignments for new apps. For
   parsed apps, insert, replace, or remove only unambiguously owned assignments
   and preserve unrelated source byte-for-byte; ambiguous anchors still block
   the affected edit/save.
6. File-backed editors record a representable source path but do not copy,
   relocate, or embed assets. Explain how relative paths resolve from app source.

#### Delivery sequence

1. [x] Land the versioned JSON schema, loader, allowlisted resolvers, fixture
   catalogs, and fail-closed loader tests.
2. [x] Land declarative parent-context rules and one effective-property resolver.
   Switch insertion, parsing, and validation to it, then freeze intrinsic and
   representative parent-context projections.
3. [x] Migrate the legacy in-code definitions without changing effective behavior,
   removing the hard-coded catalog only after both parity layers pass.
4. [x] Land expanded typed definitions, reusable groups, audit data, and model
   reset/history operations.
5. [x] Land the categorized inspector and common adapters, completing Button end to
   end against the supplied App Designer examples.
6. [x] Expand component families and style-specific audited surfaces.

#### Typed-Inspector implementation record

**Recorded 2026-08-30.**

- The packaged R2024a catalog contains 48 concrete variants for 38 factories.
  The audited development ledger contains 1,825 property contracts: 1,068
  editable, 146 visible read-only, and 611 intentionally omitted. Runtime tests
  compare every variant with that ledger, retain grouping provenance, and prove
  that every property classified as editable resolves to an allowlisted native
  or composite Inspector adapter.
- `ComponentCatalogLoader`, typed `ComponentDefinition` and
  `PropertyDefinition` values, declarative parent-context rules, and
  `ComponentRegistry.getEffectiveProperties` are implemented. Insertion,
  parsing, model validation, default probing, and the Inspector use the shared
  registry surface; `ComponentRegistry.m` contains no standard component
  inventory.
- The native categorized Inspector, implicit runtime defaults, inline rejected
  drafts, atomic property transactions, common adapters, and specialized
  Items/ItemsData, table, column, date, weekday, multiline, color, URL, and
  asset-path editors are implemented. Generated-property reset and reversible
  history exist in `DocumentModel`.
- Style-specific catalog surfaces are audited and selected from creation
  arguments.
- A generated minimal AppBase class passed `checkcode`, constructed successfully,
  completed `drawnow`, remained valid, and was deleted cleanly in MATLAB R2024a.

All unfinished capability, integration, packaging, and test work is maintained as
independent tasks in [ROADMAP.md](ROADMAP.md).

## Test strategy

- Unit tests for lexical scanning, supported literal parsing, registry validation, and source edits.
- Fixture tests for representative App Designer-exported and hand-written AppBase classes.
- Golden tests for newly generated minimal classes.
- No-edit round-trip tests requiring byte-for-byte preservation of existing source.
- Single-edit tests requiring small, expected diffs.
- Failure tests for dynamic construction, complex expressions, duplicate names, unsupported parents, and ambiguous deletion.
- Encoding tests for UTF-8 without BOM and CRLF output.
- License tests ensuring project-owned `.m` files contain the required notice while user app output is left unchanged.

## MVP completion criteria

The MVP capability surface is implemented when a user can:

1. [x] Create and save a runnable AppBase `.m` class with supported components.
2. [x] Open a representative existing AppBase `.m` class without executing it.
3. [x] Inspect its hierarchy and supported properties.
4. [x] Make at least one safe property edit and obtain a localized text diff.
5. [x] Add and delete a supported component where source ownership is unambiguous.
6. [x] Receive actionable warnings instead of source loss for unsupported constructs.
7. [x] Save UTF-8 without BOM source using the document's line-ending convention:
   host default for new documents and detected CRLF/LF for opened source.

**MVP assessment:** the functional criteria above are implemented. Remaining
release-readiness and capability work is tracked in [ROADMAP.md](ROADMAP.md).

## Known risks

- MATLAB does not expose a general-purpose, stable public API for rewriting every MATLAB syntax form.
- Programmatic AppBase classes can construct components dynamically, making complete static recovery impossible.
- Previewing arbitrary input by execution would introduce side effects and security risks.
- Grid layout behavior differs substantially from absolute positioning.
- Source formatting can be damaged if edits are not anchored to exact source spans.

These risks are handled by a deliberately limited syntax contract, source-span-based edits, non-executing previews, explicit diagnostics, and conservative save blocking.
