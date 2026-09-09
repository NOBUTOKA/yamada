# yamada Roadmap

This roadmap contains unfinished work for the public development version of
`yamada`. Each section is an independent, reviewable task rather than part of a
numbered delivery hierarchy. The order below does not promise delivery order.

The [product specification](SPECIFICATION.md) remains authoritative for current
behavior. A roadmap item becomes part of the supported public contract only after
its implementation, tests, and user documentation are complete.

## Add Component-Reference Property Editors

Ninety-five audited component-reference surfaces, including `ContextMenu`,
`Parent`, and `SelectedTab`, are currently visible but read-only with the
`deferredComponentReference` reason.

- Define an allowlisted selector contract for each safely editable reference
  family and its permitted target types.
- Validate references against document identity, hierarchy, parent rules, and
  source ownership before committing them.
- Keep cyclic, ambiguous, expression-backed, or unsupported references read-only
  with actionable diagnostics.
- Cover Inspector interaction, atomic history, Safe Preview, and localized source
  generation for every enabled reference family.

## Expose Property Reset in the Inspector

`DocumentModel.resetProperty` and reversible reset history already exist, but the
Inspector has no per-property reset action.

- Show reset availability from the effective property state without obscuring
  explicit, default, and source-backed values.
- Route reset through the existing model transaction and undo/redo history.
- Disable reset when source ownership or the reset policy does not permit a safe
  change, and explain the reason inline.
- Test singleton and composite Inspector rows, Preview refresh, source removal,
  and undo/redo restoration.

## Expose Every Supported Construction Style in the Palette

The catalog selects style-specific property surfaces from creation arguments, but
the palette does not provide a dedicated construction choice for every audited
factory style.

- Add clear palette choices for supported styles without duplicating factory
  definitions in MATLAB code.
- Seed the correct creation arguments, defaults, display names, icons, and parent
  eligibility from the catalog.
- Verify insertion, Inspector projection, Safe Preview, generation, and round-trip
  behavior for each exposed style.

## Support Programmatic Axes Construction and Editing

Programmatic-only Cartesian, geographic, and polar axes are cataloged and
source-preserved, but their specialized construction and editing paths remain
restricted.

- Define safe creation arguments, permitted parents, Preview behavior, and
  geometry rules for each axes family.
- Add palette and Inspector surfaces only where source generation is
  deterministic.
- Preserve unsupported axes expressions and runtime-only state without executing
  the input application.
- Add construction/destruction, generation, and opened-source round-trip tests.

## Support Native Menu, Toolbar, and Tree-Node Hierarchies

Native menus, toolbar tools, and tree nodes are represented in parsed source but
do not yet have complete insertion and hierarchy-editing workflows.

- Define parent-specific insertion, ordering, reparenting, and deletion rules.
- Provide hierarchy-first editing where a canvas representation would be
  misleading or unavailable.
- Preserve callback and nonliteral source while editing only unambiguously owned
  declarations, construction calls, and assignments.
- Verify undo/redo, diagnostics, generation, and no-edit source preservation for
  each hierarchy family.

## Harden Save, Save As, and Editor Close

Implement save safety around an explicit document-dirty state.

- Closing the editor with unsaved changes must present Save, Discard, and Cancel.
- Cancel, a canceled Save As, validation failure, or write failure must leave the
  editor and document open.
- Save As must request Replace or Cancel before writing an existing target.
- A normal Save to the already confirmed current path must not repeatedly request
  overwrite confirmation.
- Keep dialog and filesystem decisions injectable so automated tests can exercise
  clean close, canceled close, save-before-close, discard, replacement, and
  failed-write paths without manual UI interaction.

### Implementation Plan

1. Add conservative dirty-state tracking to `DocumentModel`.
   - Expose a publicly readable, privately writable `IsDirty` flag and retain a
     private saved-history checkpoint only while its identity remains certain.
   - Mark a new unsaved document dirty and a successfully parsed file clean.
   - Mark every recorded edit dirty. After a successful Save or Save As, record
     the current history index as the saved checkpoint and clear `IsDirty`.
   - After Undo, clear `IsDirty` only when the resulting history index exactly
     matches a still-valid saved checkpoint. Undoing past that checkpoint remains
     dirty. Redo always marks the document dirty, even when it returns to the
     saved history index.
   - Adjust the checkpoint only when history trimming preserves its identity.
     Invalidate it after an ambiguous history truncation or branch replacement so
     uncertain cases remain dirty. Preview, selection, validation, diagnostics,
     and Diff Preview must not change dirty state.
2. Refactor Save and Save As into operations that return whether saving completed.
   - Route an untitled document through Save As, and update the path, generated
     source snapshot, saved checkpoint, status, and title only after a successful
     write.
   - Ask Replace or Cancel when Save As targets an existing file. Do not ask again
     for an ordinary Save to the already confirmed current path.
   - Treat a canceled path dialog, replacement refusal, validation error, or write
     failure as an unsuccessful save that preserves the current document and its
     dirty state.
3. Introduce an injectable document-lifecycle service.
   - Keep the production implementation on native New/Open/Save As and confirmation
     dialogs while allowing tests to script dialog answers, selected paths, file
     existence, and write success or failure.
   - Use one shared guard for New, Open, and the figure's `CloseRequestFcn`. A clean
     document continues immediately; a dirty document offers Save, Discard, and
     Cancel. Continue only after Discard or a successful Save.
   - Select the requested class name or file before invoking the guard so canceling
     the initial New/Open dialog has no side effects. Construct or parse the
     replacement before swapping it into the editor so a failure retains the
     current document.
   - Prevent recursive close handling while preserving prompt-free programmatic
     deletion for application cleanup and automated tests.
4. Reflect dirty state in a stable editor title.
   - Format titles as `UntitledApp* - Yet Another MATLAB App Designer Alternative`
     or `ExampleApp.m* - Yet Another MATLAB App Designer Alternative`, omitting
     `*` when the document is clean.
   - Centralize title refresh after New, Open, edits, Undo, Redo, Save, and Save As.
     Give the editor figure a stable `Tag` and migrate tests away from exact title
     matching because the visible title will become document-dependent.
5. Verify the complete lifecycle before removing this roadmap item.
   - Add model tests for new/open state, edits, successful saves, Undo to the saved
     checkpoint, Undo past it, Redo through it, branch replacement, and history
     trimming.
   - Add UI tests for every Save/Discard/Cancel path across New, Open, and Close;
     Save As replacement; canceled and failed writes; title-marker transitions;
     clean close; and prompt-free test cleanup.
   - Run the complete MATLAB R2024a unit suite with no failed or incomplete tests,
     update the public behavior and architecture documentation, and then delete
     this entire roadmap section, including this implementation plan.

## Verify Packaging and End-to-End Workflows

- Verify catalog and HTML-overlay resource discovery from the distributed layout,
  not only from a repository checkout.
- Complete new-app and existing-app workflows through the shared model, Preview,
  validation, generator, diff, Save, and Save As paths.
- Verify recoverable save targets, save/reopen behavior, UTF-8 without BOM,
  preserved CRLF/LF conventions, and cleanup of every UI fixture.
- Add the end-to-end checks required before publishing a versioned release.

## Package a Public Release as a MATLAB Toolbox

Create a MATLAB Toolbox (`.mltbx`) only after the editor reaches the quality bar
for a versioned public release and the release-blocking workflows above pass.

- Define stable Toolbox metadata, including its identifier, semantic version,
  summary, author, license, minimum MATLAB release, and supported platforms.
- Add a reproducible packaging script based on `matlab.addons.toolbox.ToolboxOptions`
  and `matlab.addons.toolbox.packageToolbox` rather than relying only on manually
  saved packaging-project state.
- Include the runtime MATLAB source, the release-specific component catalog,
  `EditorInteractionOverlay.html`, the license, and public documentation; exclude
  repository metadata, development-only catalog tooling, tests, and build output.
- Decide whether the first package launches through the `yamada()` command only
  or also exposes an App Gallery entry, and document the supported entry point.
- Analyze required files and products, then declare only verified MATLAB-release
  and platform compatibility. Initially treat R2024a as the sole supported
  release unless additional releases have been tested.
- Install the built package into an isolated MATLAB environment and verify that
  the installed copy, rather than the source checkout, launches successfully;
  discovers its catalog and HTML overlay; completes representative New, Open,
  Save, and Save As workflows; and uninstalls cleanly.
- Publish the `.mltbx` and release notes with the corresponding tagged release
  only after the package artifact and installation smoke tests pass.

## Build a Grid Layout Visual Editor

Inspector editing of a grid child's `Layout.Row` and `Layout.Column` remains the
safe fallback. The visual editor will add direct manipulation of the selected
`uigridlayout` and take ownership of the deferred `RowHeight` and `ColumnWidth`
track-list properties.

- Show an editor-owned overlay with row and column boundaries, track labels, child
  occupancy, and selected-child spans. Nested grids must edit only the selected
  grid's immediate tracks and children.
- Support fixed numeric sizes, `"fit"`, weighted values such as `"1x"`, and mixed
  R2024a track lists while preserving order and source representation.
- Add, remove, resize, and reorder tracks through one validated, atomic, undoable
  transaction that includes any required child-placement adjustments.
- Support dragging a child between cells and resizing its occupied span while
  continuing to store placement through `Layout.Row` and `Layout.Column`.
- Reject destructive or ambiguous changes instead of silently moving, clipping,
  or deleting children.
- Keep expression-backed or otherwise unsupported track definitions read-only;
  never evaluate, coerce, or rewrite them.
- Reuse the existing model, validation, Safe Preview, source-span generation,
  selection overlay, and history boundaries without interacting with the editor's
  own internal Grid Layouts.
- Test fixed, `"fit"`, weighted, mixed, nested, spanned, and expression-backed
  grids, including failed-edit atomicity and byte-identical no-edit output.

## Offer an Explicit Save As Line-Ending Choice

New documents currently use the host-default line ending, while opened documents
preserve detected CRLF or LF source.

- Optionally expose CRLF and LF choices in Save As without changing the default
  behavior.
- Keep the chosen convention explicit in generated-source Preview and file tests.
- Do not normalize an opened file silently.
