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

## Edit Application Menu Bars and Context Menus

Provide a dedicated editing workflow for menu bars, submenus, context menus,
toolbars, and their items in the application being edited. This builds on the
native hierarchy operations above; it does not change the editor's own menus.

- Present a hierarchy-focused editor for adding and arranging menu and toolbar
  items, editing supported labels and other literal properties, and choosing
  which components own a context menu.
- Define the supported menu and tool properties, parent rules, and component
  references in the catalog and model before enabling each editing control.
- Keep callbacks, expressions, and source whose ownership is ambiguous visible
  but read-only. Do not execute the opened application or its callbacks.
- Route edits through validated, atomic document transactions so Undo/Redo,
  Safe Preview limitations, diagnostics, and source generation stay consistent.
- Test new and opened applications with nested menus, context-menu assignment,
  toolbar items, unsupported source, and no-edit round trips.

## Add Hierarchy Context Menus and Callback Management

Use the editor's Hierarchy context menu as the initial entry point for a separate
callback-management popup. Do not add special action rows to the catalog-driven
Properties construction path. This menu belongs to the editor; editing context
menus in the opened application remains the separate task above.

Keep entry points thin: resolve a component ID and invoke a shared command. The
popup owns transient controls, DocumentModel owns validated edits and history,
and the source layer owns parsing and localized rewrites. Safe Preview must never
execute the opened application's callbacks. Review each stage at its checkpoint
before proceeding. The progress notes below identify implemented internal seams;
the user-facing workflow is not complete until all stages pass.

### Agreed interaction contract and implementation order

- Keep right-click targeting independent of selection: opening the menu for an
  unselected component must leave Hierarchy selection, Properties and Safe Preview
  unchanged. The popup operates on that explicit context target.
- Add creates a binding and an empty method together. Delete removes the binding
  and the full method body together. Disable both actions when either operation
  cannot be proven safe; show the reason in the popup.
- Implement callback-management Stages 1-5, then the three Reload Source stages
  below. Finish callback-management Stage 6 with the combined external-edit/reload
  workflow. Review each checkpoint before advancing; a passing callback-only
  workflow does not establish that source reload is complete.
- Keep Properties catalog construction unchanged. The menu and popup resolve
  commands; DocumentModel owns transactions; source analysis/generation owns
  binding and method spans; document lifecycle owns reload and replacement.

### Stage 1: Define callback discovery and editing contracts

- Derive callback names from effective catalog metadata for the concrete component
  style and parent context; exclude callback execution-control properties. Inspect
  the loader/registry projection and add a narrow discovery API if needed, without
  a parallel hard-coded callback list or changes to literal property editing.
- Define absent/empty, safely editable, and preserved unsupported/ambiguous binding
  states, with explicit reasons for unavailable operations.
- Define Add as generating a uniquely named empty handler method and its binding
  in one edit. Define Delete as removing both the binding and the complete handler
  method in one edit. Prove method ownership and absence of other references before
  enabling deletion; shared handlers or ambiguous references are unsafe. Editing
  method bodies inside yamada remains outside this task.
- Define supported binding forms, source spans, and method/assignment insertion
  anchors. Read existing expressions without evaluation; refuse ambiguous ownership.

Checkpoint: review discovery and Add/Delete semantics using new components, direct
assignments, createCallbackFcn bindings, empty assignments, constructor bindings,
anonymous functions, shared handlers, and repeated/conditional assignments.
Confirm unsupported forms have diagnostics and no-edit source remains exact.

Stage 1 progress: effective callback discovery and immutable CallbackState results
are implemented. CallbackSourceAnalyzer recognizes direct createComponents bindings
using createCallbackFcn(app, @Method, true) or @app.Method, explicit empty bindings,
and whole instance-method spans with nested blocks. Conditional/repeated/constructor
bindings, arbitrary anonymous functions, shared/missing handlers, indirect access,
dynamic dispatch, and unproven block structures return unsupported with a reason.
Add/Delete semantics remain binding-plus-method transactions for subsequent stages.
Tests cover the state table, multiline source, no-edit generation, and a sentinel
side effect proving that parsing/analysis/generation do not run the callback.

### Stage 2: Add the editor Hierarchy context menu

- Add a native menu with Manage Callbacks... as its first command. Provide a shared
  command/availability seam for future entries without implementing deferred
  copy/cut/paste operations in this feature.
- Right-click targets the clicked node's component ID without changing selection.
  Keep the context target separate from SelectedComponentId and do not refresh the
  Inspector or Preview selection. Empty space must not reuse a stale target.
  Disable the command for missing targets or callback-free components.
- Account for node reconstruction, deletion, document replacement, and cleanup.
  Keep editor menu handles out of ComponentRecord and generated application source.

Checkpoint: test selected/unselected, root/nested, callback-free, and empty-space
clicks; verify unchanged selection/Inspector/Preview, context-target identity and menu
availability after rebuild/Open/New, and cleanup. Menu access must not dirty the
document or create history. Validate native hit targeting before building on it.

Stage 2 progress: a shared native HierarchyContextMenu adapter captures the clicked
node from ContextMenuOpeningFcn.InteractionInformation.Node without touching
selection. Command dispatch validates the captured document and component again;
empty space, reset/rebuild, deleted targets and replaced documents invalidate it.
Native chooseContextMenu tests prove unselected-node and root targeting preserves
selection. The editor command now opens the independent popup without changing
the active Inspector target. Subsequent UI additions bring the inventory to 114.

### Stage 3: Build the independent callback popup

- Follow existing modal-dialog lifecycle conventions. Show the target name and a
  scrolling list of callback name, Add, and Delete, with keyboard navigation.
- Enable Add only when creating both binding and method is safe; enable Delete only
  when removing both binding and method is safe. Disable both buttons for any
  callback that cannot be edited safely and explain why, including shared methods
  or uncertain references. Existence alone must not imply safe deletion.
- Route actions through narrow shared commands and refresh from authoritative
  model state after success. Each Add/Delete applies immediately as one undoable
  operation; Close only closes the popup. Failures must not partially update rows.
- Reuse/focus an existing popup and close it when its document or target expires.

Checkpoint: hidden-dialog tests verify catalog coverage/order across variants,
button states, unsupported explanations, long lists, focus, repeated opening,
closing and failure display. Verify the lifecycle independently of source editing.

Stage 3 progress: CallbackManagerDialog now shows the target name and scrollable
catalog-ordered callback rows with mutually exclusive Add/Delete availability and
unsupported-reason tooltips. Commands revalidate state, refresh after success,
and report failures without optimistic changes. The editor reuses the popup for
the same target, closes it on document replacement/cleanup, and refreshes or closes
it when the target expires. Hidden-dialog and real editor-menu tests pass. Actions
now invoke source-preflighted model transactions; the UI test inventory is 114.

### Stage 4: Implement atomic callback model operations

- Add dedicated DocumentModel operations rather than bypassing read-only checks in
  setProperty/resetProperty. Preflight target identity, supported callback, binding
  ownership, safe anchors, and handler-name collisions before any mutation.
- Record binding and generated-handler changes as one transaction. Preserve exact
  prior entries, full method text and source metadata for Undo/Redo, not only values.
- Delete the owned binding and complete handler method atomically, including its
  body and owned help. Preserve other bindings/methods; block both actions when
  sharing, indirect references, or ambiguous source prevent proving safety.
  Reject stale/repeated requests safely. Coordinate dirty state, diagnostics,
  source preview, and refresh through yamada without unnecessary tree rebuilding.

Checkpoint: test Add/Delete, collisions, shared methods, invalid/stale targets,
rollback, saved checkpoints and complete Undo/Redo restoration. One click produces
one history entry; rejected edits leave model, history and dirty state unchanged.

Stage 4 progress: DocumentModel.applyCallbackAction now prepares immutable typed
CallbackEdit intentions and records before/after snapshots as one history step.
Generated names avoid source tokens, pending handlers and reserved names. Delete
retains the original binding/method spans and source snapshot; Delete/Add and
Undo/Redo preserve complete original bodies without mutating OriginalText.
Unsupported, shared, stale and repeated requests are rejected before mutation.
Complete generation is preflighted before recording history; failures restore
intentions, diagnostics and source preview. Popup actions are connected, and
callback history refreshes generated source on Undo/Redo without changing selection.

### Stage 5: Extend callback parsing and source generation

- Extend NewAppGenerator and RoundTripGenerator to emit owned callback bindings
  and generated stubs; the existing literal-only rewrite path is insufficient.
- Add English method help and practical arguments blocks to generated stubs using
  the supported handler signature contract. Do not add the editor's GPL notice
  to user output.
- Preserve unrelated methods, bodies, comments and unsupported source. Delete both
  the owned parsed binding and its complete method using validated spans, with no
  partial deletion when either is unsafe. Validate nonoverlapping edits and safe
  insertion anchors before committing; preflight failure must roll back model edits.
- Coordinate pending additions/removals across repeated generation and Save/reparse
  so assignments and methods are not duplicated. Keep Safe Preview inert.

Checkpoint: verify new-app generation and opened-source round trips for supported
forms, multiline assignments, collisions, shared handlers, Add/Delete/Undo/Redo,
and Save/reopen. Confirm exact no-edit preservation and unchanged unrelated source.
Use a callback with a sentinel side effect to confirm parsing, editing, generation
and Safe Preview never execute it.

Stage 5 progress: canonical and round-trip generators now emit managed bindings
and complete method stubs, remove original binding/method spans, and combine shared
insertion anchors. Newly inserted components in opened apps receive bindings beside
their initialization. Generated app argument types follow the current class name.
Tests cover repeated generation, new and opened source, multiple callbacks, complete
body deletion, saved externally edited bodies, side-effect nonexecution, rollback,
and full-source Undo restoration. Real popup Add/Delete/Undo tests also pass.
Full-suite and visible workflow verification remain Stage 6 work.

### Stage 6: Integrate and validate the complete workflow

- Use small and large fixtures: a minimal button application and a nested mixed-
  component application with shared handlers, unsupported forms, and a sufficiently
  long callback list to exercise scrolling.
- Test selection, component deletion, Open/New, Undo/Redo outside the popup, and
  repeated cleanup without stale menu/dialog handles. Update UI test-selection
  contracts when adding tests.
- Verify toolbar Refresh, Edit-menu Reload Source and F5 after externally saving
  a callback body in MATLAB. Confirm refreshed ownership, Add/Delete availability,
  complete body deletion, clean history, and popup invalidation; include dirty/disk
  conflict cancellation and failed reload without losing the current document.
- Update specification and user documentation after implementation, including
  Add/Delete semantics and unsupported cases. Any future Properties shortcut must
  invoke the shared command outside catalog-driven property-row construction.

Checkpoint: run relevant parser/model/generator/dialog/editor suites, then the full
MATLAB suite through the escalated interactive-account verification path. Review
Passed/Failed/Incomplete results and perform a visible right-click/popup usability
check. Commit cohesive passing implementation units separately as they complete.


## Reload Source Edited Outside yamada

Support editing callback bodies in MATLAB while the application remains open in
yamada. Reload reads the saved file on disk; unsaved MATLAB editor buffers are not
part of this operation. Implement this as an independent lifecycle feature and
include it in callback-workflow integration verification.

### Stage 1: Define safe reload and external-change handling

- Reload the current document's FilePath without an Open dialog. Disable the
  command when no saved path exists; report missing/unreadable files and parse
  failures without replacing the current document or history.
- Reuse DocumentLifecycleService policy seams, but do not blindly call the current
  Open/replace sequence: it parses before a guard that may save over the same file.
- Compare the on-disk source with the loaded/saved snapshot. For local dirty state,
  request Save/Discard/Cancel; when disk also changed, do not offer an ordinary
  same-path Save that would silently overwrite the external edit. Offer a clearly
  explained separate-file save, discard-and-reload, or cancel, and define how the
  original reload target is retained if Save As changes the document path.
- Resolve the user's choice before preparing the final reload snapshot. After any
  save, read and parse fresh source rather than installing an earlier parsed copy.
  Detect a file changed again during the operation and abort/retry safely.
- Atomically replace only after successful parsing. Start clean history with no
  Undo into the old source snapshot; invalidate source spans, drafts and popup
  targets. Preserve selection by unique component identity/name where possible,
  falling back to the root if the component disappeared.

Checkpoint: test clean/dirty documents, disk changes, cancellation, Save failure,
Save As, missing/unreadable files, parse errors and changes during reload. Confirm
no external edits are silently overwritten, failures retain current state, and
fresh method bodies and spans are visible after a successful reload.

### Stage 2: Add the three Reload entry points

- Add a Refresh button alongside Undo/Redo in the existing toolbar, a Reload Source
  command in the Edit menu, and F5 handling through the editor keyboard dispatcher.
  Show the shortcut and a tooltip explaining that saved source is reloaded.
- Route all three entries through one command and identical availability rules;
  avoid duplicate execution, reentrant reloads and conflicts with focused controls.

Checkpoint: invoke toolbar, menu and F5 through real UI bindings; verify identical
results and availability for unsaved/new, saved and missing-file documents. Check
keyboard behavior with focus in the hierarchy, Inspector and callback popup.

### Stage 3: Verify the external MATLAB editing workflow

- Save an app with generated callbacks, edit and save a handler externally, reload
  in yamada, and perform further Add/Delete and Save/reopen operations. Verify the
  edited body survives unrelated changes and Delete removes the current body.
- Test renamed/deleted components, shared methods introduced externally, long
  source files, repeated reloads, popup cleanup and reset Undo/Redo availability.
- Document disk-versus-editor-buffer behavior, dirty-state choices, history reset
  and the Refresh/Edit/F5 entry points. Update test-selection contracts as needed.

Checkpoint: run lifecycle, interaction, parser and round-trip suites, followed by
full escalated MATLAB verification and a visible MATLAB/yamada editing check.
Record Passed/Failed/Incomplete results and commit passing feature units separately.


## Add Range and Multiple Selection

The editor currently tracks one selected component ID. Establish a selection
model that can represent several components before adding group edit commands.

- Support a drag-selection rectangle in Safe Preview and Shift-based range
  selection in the hierarchy view. Define Ctrl/Command selection toggling and
  a stable anchor for repeated range extensions.
- Keep selected component IDs, the active component, hierarchy highlighting,
  and Preview/HTML-overlay highlighting synchronized. Selection alone must not
  modify the document or mark it dirty.
- Define how nested components, overlapping bounds, hidden tabs, scrolling,
  and clicks on empty space affect selection. Avoid selecting a descendant twice
  when an ancestor is selected for a later group operation.
- Keep the existing Inspector and single-component geometry tools tied to the
  active component until group editing has its own validated behavior.
- Test mouse and keyboard selection in both views, selection after hierarchy
  refresh and document replacement, and interaction with Grid Layout overlays.

## Add Component Copy, Cut, and Paste

- Provide Copy, Cut, and Paste through the Edit menu, keyboard shortcuts, and
  context menus on components in the hierarchy view. All three entry points
  must use the same commands and availability rules.
- Define how a selected component and its descendants are copied, where they
  can be pasted, and how unique component names and identities are assigned.
- Validate the destination's parent rules and source ownership before changing
  the document. Keep unsupported or ambiguous source structures unchanged.
- Make each paste or cut one atomic, undoable edit, and update selection, the
  Inspector, Safe Preview, diagnostics, and generated source consistently.
- Test the three UI entry points, nested components, invalid destinations,
  repeated pastes, cancellation or failure, undo/redo, and opened-source
  round trips without executing the input application.

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

## Show Safe Preview at the UIFigure's Actual Pixel Size

The implementation uses a one-to-one pixel canvas instead of fitting the root
`UIFigure.Position(3:4)` into the editor panel. Keep this acceptance checklist
until the actual-size behavior has been reviewed and the item is closed out.
Resizing the editor window must not change the edited root figure size or scale
its preview components.

- Put a canvas with the root UIFigure's client-area width, height, and Color
  inside a scrollable Preview host with a dark-gray background and a light
  native heading. Keep a visible but subdued boundary between the canvas and
  the area outside the figure, including beside scroll bars during scrolling
  and at the far scroll limits.
  Center the editing area when it fits; provide horizontal and vertical
  scrolling when it extends beyond the host.
- Include visible component bounds in the scrollable editing area after a
  figure shrink. Draw selectable outlines outside the actual-size canvas so
  stranded components can be dragged back into the figure; recompute the
  editing area after moves and Undo/Redo.
- Render supported components at their model pixel positions without a fit
  scale. Keep the Safe Preview boundary: do not execute opened app code or imply
  that unsupported runtime behavior is reproduced.
- Move the interaction overlay, component hit targets, resize handles, and Grid
  Layout geometry to a consistent canvas coordinate system so scrolling and
  editor-window resizing do not offset interactions.
- Add eight handles for changing the root UIFigure width and height, including
  an empty new figure and while a child is selected. Commit supported literal
  `Position` edits through the document model, anchoring the opposite edge when
  resizing from the left or bottom and providing Undo/Redo and generated-source
  updates. Show a dashed guide for the proposed bounds during each drag,
  without a numeric size label. Disable the handles when the root size is not
  safely editable.
- Add a small UI fixture (for example, 320 x 240 pixels) that fits inside the
  normal Preview viewport and a large UI fixture (for example, 1200 x 900
  pixels) that overflows it in both directions. Give each fixture identifiable
  controls near its edges; include a layout-managed child to exercise geometry.
- Use both fixtures to verify one-to-one canvas dimensions, dark outside area,
  scroll reachability, selection and dragging after scrolling, root resize,
  Undo/Redo, generation, and reopen behavior. Also check narrow and enlarged
  editor windows, then run focused UI tests and the full R2024a unit suite.

Implementation evidence (2026-10-01): the 320 x 240 and 1200 x 900 fixtures
render at their model sizes; screenshots show the figure Color, subdued dark-gray
surround, root handles, and both scroll bars on the large fixture. Automated
checks cover canvas-local geometry after scrolling, root resize, Undo/Redo,
generation, and reopen. The R2024a full suite passed 221/221 tests, and the
HTML overlay tests passed 3/3. A final interactive window-resize visual check
remains for review; MATLAB batch-mode screenshots do not exercise native window
layout updates reliably.

Follow-up visual check (2026-10-01): the large fixture shows fixed dark
separators between the still-visible UIFigure and both native scroll tracks
before reaching the far edges. Dark padding remains visible at the far scroll
limits. The small fixture keeps the separators hidden, and the heading uses
the native light background with dark text. The R2024a full suite passed
221/221 tests. One nonfatal MATLAB internal scroll callback warning appeared
once during an existing Grid interaction test; it did not affect the results.

Further visual and interaction check (2026-10-01): an empty new figure now
publishes root overlay data, and all eight orange handles remain visible with
a child selected. The canvas has a one-pixel gray frame on every side. South
and southwest drags update the root origin and size while anchoring the
opposite edges; Undo restores the previous Position. The R2024a full suite
passed 221/221 tests, and the three HTML overlay tests passed. The earlier
internal scroll callback warning did not recur in this run.

Root drag guide check (2026-10-01): the small fixture screenshot shows a
dashed candidate boundary across the canvas and dark surrounding area, with
no numeric label. The large fixture interaction test confirms that the guide
is present during northeast and southwest drags and removed afterward. The
R2024a full suite passed 221/221 tests; the three HTML overlay tests passed.

Oversized-figure shrink check (2026-10-01): shrinking the large fixture from
1200 x 900 to 320 x 240 keeps stranded component outlines reachable by
scrolling on the dark surround. The button, panel, and label can be dragged
back inside the actual-size figure; the editing extent shrinks afterward.
Undo/Redo restores both component positions and the corresponding extent.
Screenshots were checked before the full suite. Geometry is also republished
after shell construction so opened Grid Layout children use settled positions.
The R2024a full suite passed 222/222 tests; the three HTML overlay tests passed.

## Offer an Explicit Save As Line-Ending Choice

New documents currently use the host-default line ending, while opened documents
preserve detected CRLF or LF source.

- Optionally expose CRLF and LF choices in Save As without changing the default
  behavior.
- Keep the chosen convention explicit in generated-source Preview and file tests.
- Do not normalize an opened file silently.
