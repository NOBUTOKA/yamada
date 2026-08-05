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

- Add palette insertion.
- Add movement and resizing for absolute layouts.
- Add row, column, and span editing for grid layouts.
- Add explicit deletion and an undo mechanism or reversible edit history.

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
