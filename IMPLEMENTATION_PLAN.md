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
7. Save to a new path by default until safe round-trip behavior is established.

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

The first version should prioritize clear selection and property editing over visual polish. Delete must always be an explicit command. Save must be disabled when fatal validation or generation diagnostics exist. The save dialog must let users select `CRLF` or `LF` for new output; opened source retains its detected convention by default.

## Proposed project structure

```text
MatlabAppClassDesigner.m
+macd/
  +model/
  +source/
  +ui/
  +validation/
tests/
  fixtures/
  unit/
```

Package boundaries may be adjusted during the first implementation slice, but parser and generator code must remain independent of live editor UI handles.

## Implementation phases

### Phase 1: Model and new-app generation

- [x] Define diagnostics, source spans, property entries, component records, the document model, and the component registry.
- [x] Create an empty AppBase model with a root `uifigure`.
- [x] Generate a runnable minimal class.
- [x] Validate class names, component names, hierarchy, safe literals, generated UTF-8 without BOM output, host-default line endings, and GPL notices.

Phase 1 uses a data-driven boundary between component records and typed component
definitions. A component record stores a factory name, declared MATLAB type,
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
heterogeneous, such as component creation arguments, or where a later phase has
not yet defined the concrete model type.

Parsed expressions also have a representation distinct from safe literal values.
They can therefore remain source-backed and read-only in later phases instead of
being coerced into a value or silently discarded. Source spans, diagnostics,
unknown regions, original text, and pending edits already have dedicated model
locations for the read-only parser and localized round-trip work in Phases 2 and 3.

### Phase 2: Read-only source parsing

- [x] Add a representative AppBase fixture.
- [x] Parse class inheritance, component declarations, factory calls, hierarchy, and simple assignments.
- [x] Produce explicit warnings for unsupported constructs.
- [x] Verify that parsing does not execute input code.

Phase 2 uses a lexical scanner to identify statement boundaries without evaluating
the source. It handles quoted text, line and block comments, balanced delimiters,
and continuations before the AppBase parser recognizes its limited structural
subset. `AppSourceParser` retains the original decoded source, file path, line
ending convention, component and property source spans, typed unknown source
regions, and diagnostics in the shared document model.

Opened source files must be valid UTF-8. The parser reports invalid UTF-8 as a
blocking error and does not create editable component records, preventing a
lossy write-back. It retains the source file's detected line-ending convention
(`CRLF`, `LF`, or `None`) for future round-trip output. New documents use CRLF
on Windows and LF on Linux or macOS; the future save dialog will let the user
choose either convention for new output.

The parser accepts only Registry-supported direct factory calls and direct
`app.Component.Property = value` assignments. A conservative literal parser
accepts text, logicals, real numeric matrices, and row cell arrays; all other
values remain read-only source expressions. Assignments found before a supported
component creation are retained as unknown regions instead of being mistaken for
initialization, which prevents callback behavior from overriding the initial UI
model. The parser reads files as bytes and never instantiates or executes the
input class.

### Phase 3: Safe round-trip generation

- [x] Preserve exact source when no edits are made.
- [x] Implement localized changes for supported property assignments.
- [x] Add safe insertion of generated components.
- [x] Add conservative deletion with ownership checks.
- [x] Compare original and generated source before saving.

Phase 3 adds `RoundTripGenerator`, which treats parsed source as immutable until
an editable literal changes. It keeps no-edit output byte-for-byte identical,
uses existing source spans for direct-assignment replacements, and exposes the
rewritten `GeneratedText` alongside `OriginalText` for save-time diff preview.
Generated components are inserted only after complete parsed declaration and
creation anchors are found. Explicit deletion is limited to non-root leaf
components with fully owned declaration, creation, and property spans; any
additional source reference blocks generation with an actionable diagnostic.

### Phase 4: Editor shell

- [x] Implement the main AppBase editor class.
- [x] Connect New and Open workflows.
- [x] Add hierarchy selection, preview rendering, property inspection, and diagnostics.

Phase 4 adds `MatlabAppClassDesigner`, a programmatic AppBase editor shell.
Its New and Open commands converge on `DocumentModel`; Open remains a parser-only
workflow. The shell displays a component hierarchy, a registry-only preview that
never constructs the opened class, read-only property inspection, structured
diagnostics, validation, Save As, and an original-versus-generated source view.

### Phase 4.5: Standard MATLAB R2024 component catalog (complete)

- [x] Register the standard persistent MATLAB R2024 AppBase component catalog:
  common controls, containers, navigation and data controls, axes,
  instrumentation components, HTML component, menus, context menus, and toolbar
  tools.
- [x] Include R2024a `uicolorpicker` support and style metadata for components
  whose factory has multiple creation forms.
- [x] Record programmatic-only axes and parent-dependent components as metadata
  so later UI and generation phases can apply their special construction rules.
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
- [x] Add a manual screenshot-comparison procedure for all fixtures and the
  editor itself in `VISUAL_VERIFICATION.md` while preview fidelity work remains
  active.

Dedicated editing and generation semantics for style-specific constructors,
tree-node/menu/toolbar hierarchy, programmatic-only axes, and full inspector
property type metadata remain later-phase work. They do not limit the Phase 4.5
registry, parsing, or Safe Preview coverage recorded above.

### Phase 5: Canvas editing

#### Objective

Turn the Phase 4 Safe Preview into an editing canvas without weakening the
source-preserving boundary. Every canvas action must first mutate the shared
`DocumentModel`; the hierarchy, inspector, preview, validation, and source
generators then consume that model. Preview graphics handles are disposable UI
state and must never be treated as the source of document state.

The first Phase 5 slice covers ordinary persistent visual components that have
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
   `Metadata.Category`; the palette lists only the Phase 5-eligible factories.
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
   diagnostics to a later layout-aware phase; never coerce or rewrite the grid
   definition.

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
   conservative deletion paths; Phase 5 must add focused round-trip tests for
   palette-created components, position edits, grid-layout edits, undo, and
   redo, proving localized source diffs.

#### Tests and visual verification

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
4. Run the relevant MATLAB tests through the interactive licensed account, then
   follow `VISUAL_VERIFICATION.md` for new-app absolute and grid examples and
   for at least one parsed fixture. Confirm selection visibility, no callback
   execution, source-coordinate geometry, grid span behavior, Delete/Undo/Redo,
   and an intentional unsupported-component message.

#### Delivery sequence

1. Land the model creation, mutation, validation, and reversible-history layer
   with unit tests.
2. Land the palette, commands, and selection synchronization on the Safe
   Preview, with construction/destruction editor tests.
3. Land absolute geometry editing and its scale-aware tests.
4. Land grid row/column/span controls and boundary tests.
5. Finish round-trip coverage, manual visual verification, and an end-to-end
   MATLAB test run before marking Phase 5 complete.

### Phase 6: Integration hardening

- Run unit, round-trip, and generation tests.
- Verify generated MATLAB syntax using available MATLAB tooling.
- Verify warnings, save guards, encoding, line endings, and Git diff readability.
- Test new-app and existing-app workflows with the same model and generator.

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

The MVP is complete when a user can:

1. Create and save a runnable AppBase `.m` class with supported components.
2. Open a representative existing AppBase `.m` class without executing it.
3. Inspect its hierarchy and supported properties.
4. Make at least one safe property edit and obtain a localized text diff.
5. Add and delete a supported component where source ownership is unambiguous.
6. Receive actionable warnings instead of source loss for unsupported constructs.
7. Save UTF-8 without BOM source using a chosen line-ending convention that remains reviewable in Git.

## Known risks

- MATLAB does not expose a general-purpose, stable public API for rewriting every MATLAB syntax form.
- Programmatic AppBase classes can construct components dynamically, making complete static recovery impossible.
- Previewing arbitrary input by execution would introduce side effects and security risks.
- Grid layout behavior differs substantially from absolute positioning.
- Source formatting can be damaged if edits are not anchored to exact source spans.

These risks are handled by a deliberately limited syntax contract, source-span-based edits, non-executing previews, explicit diagnostics, and conservative save blocking.
