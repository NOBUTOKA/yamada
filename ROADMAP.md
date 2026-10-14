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

Status: completed and verified on MATLAB R2024a, 2026-10-02. All six stages and
the integrated source-reload workflow below have passed their checkpoints.
The typed-event and naming follow-ups below are planned and remain unimplemented.

Use the editor's Hierarchy context menu as the initial entry point for a separate
callback-management popup. Do not add special action rows to the catalog-driven
Properties construction path. This menu belongs to the editor; editing context
menus in the opened application remains the separate task above.

Keep entry points thin: resolve a component ID and invoke a shared command. The
popup owns transient controls, DocumentModel owns validated edits and history,
and the source layer owns parsing and localized rewrites. Safe Preview must never
execute the opened application's callbacks. Review each stage at its checkpoint
before proceeding. The progress notes below identify implemented internal seams;
the original six stage checkpoints are verified in the completion evidence below.

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
Add/Delete binding-plus-method transactions are implemented and verified in Stages 4-5.
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
the active Inspector target. Subsequent UI additions bring the inventory to 119.

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
now invoke source-preflighted model transactions; the UI test inventory is 119.

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
Full-suite and visible workflow verification are complete in Stage 6.

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


Stage 6 completion evidence:

| Stage | Verified behavior | Evidence |
| --- | --- | --- |
| 1 | All catalog variants/parents, supported bindings and explicit unsafe states | CallbackDiscoveryTest, CallbackSourceAnalyzerTest |
| 2 | Native hit targeting, unchanged selection/Inspector, empty/stale/deleted targets and rebuilds | HierarchyContextMenuTest |
| 3 | Modal catalog-ordered rows, availability/reasons, failures, long lists, cleanup and keyboard navigation | CallbackManagerDialogTest, verifyCallbackKeyboard |
| 4 | One atomic history entry, handler collision avoidance, rollback and complete Undo/Redo | CallbackModelTest, CallbackGenerationTest |
| 5 | New/opened generation, complete method deletion, exact preservation, saved bodies and nonexecution | CallbackGenerationTest, source/model suites |
| 6 | Nested mixed fixture, 13-callback scrolling, external editing/reload, selection/lifecycle and visible UI | verifyCallbackWorkflow and full suite |

The final full suite reports 256 Passed, 0 Failed, 0 Incomplete (496.433 seconds).
The final visible workflow also passes actual F5 with Hierarchy and Inspector
focus, external method-body Delete/Undo, unique-name selection preservation,
renamed/deleted targets, newly shared handlers, 2,000 added source-comment lines,
repeated reloads and post-reload Save/reopen. A sentinel proves Safe Preview never
runs handlers. Native Tab/Enter/popup-F5 checks pass separately. Exported root and
shared-handler popup images were reviewed after confirming rendered label text.
README, SPECIFICATION and architecture documentation match the implementation.
The developer verification uses a Windows-only exact-title foreground helper;
it is not an application runtime dependency. Project conventions and updated
UI-selection/three-button toolbar contracts pass.

### Follow-up: Generate documented event argument types (planned)

Status: planning only; the completed six-stage workflow above currently generates
an untyped `event` argument. These follow-ups have not been implemented.

Data flow: release-specific audited callback contracts -> catalog promotion ->
validated PropertyDefinition/ComponentRegistry projection -> DocumentModel method
stub construction -> NewAppGenerator/RoundTripGenerator output. The popup remains
a thin command view; ValueSchema continues to describe callback binding values,
not the event argument passed to a handler.

#### Stage 7: Audit and define callback signature metadata

- Extend per-property records and `schema.json` under
  `dev/component-data/R2024a`. Record a distinct `callbackSignature` contract with
  event representation, verified fully qualified class name where applicable,
  verified shape if available, audit status and release-specific source evidence.
  Field names are proposed schema design, not existing runtime fields.
- Key contracts by concrete component variant/style and callback property; account
  for effective parent-context projection where applicable. Do not assume that a
  shared callback name implies the same argument contract across components.
- Distinguish verified object types, verified non-object/empty event data, and
  unresolved documentation. Unknown event data remains untyped; do not replace it
  with a universal `event.EventData` base class or presume every event is scalar.
- For example, audit `uibutton-push` / `ButtonPushedFcn` against the R2024a official
  contract and installed public `matlab.ui.eventdata.ButtonPushedData` class.
  Verify `ValueChangedFcn`, `ValueChangingFcn`, CreateFcn/DeleteFcn and inherited
  callbacks independently instead of inferring types from property names.

Checkpoint: review the callback/variant inventory and evidence for representative
Button, state-button, numeric/text edit-field, slider, table, tree and figure
callbacks. Missing evidence is explicitly unresolved. No opened application or
user callback may execute during discovery or audit.

#### Stage 8: Promote and validate the new metadata

- Extend the promotion/projection pipeline under `dev/component-data`, including
  `PromoteGroupingToRuntimeCatalog.ps1`, and any intervening grouping artifacts
  that otherwise drop the contract. Preserve per-variant overrides when reusable
  property groups are expanded; do not infer one common signature from group ID.
- Regenerate `resources/component-catalog/R2024a`; update the catalog schema and
  strict metadata allowlists/validation in ComponentCatalogLoader. Keep older
  catalogs with absent optional contracts loadable, and review schema versioning.
- Expose the validated contract through PropertyDefinition and the existing
  `getEffectiveCallbacks` projection. Reject malformed qualified type names,
  unsupported contract shapes and signatures attached to noncallback properties.
  Treat class names as validated data, never as expressions to evaluate.
- Keep callback binding editability, Inspector rows and Safe Preview policy
  unchanged. Documentation evidence stays in the development audit surface;
  runtime metadata carries only the reviewed generation contract it needs.

Checkpoint: test promotion reproducibility, ledger/catalog parity, concrete styles
and parent projection, unknown/absent contracts, and malformed-metadata rejection.
Catalog loading/discovery must not instantiate input apps or execute callbacks.

#### Stage 9: Use the contract in generated method stubs

- Change DocumentModel.applyCallbackAction's stub construction to obtain the
  effective callback definition and emit the verified `event` type/shape in its
  arguments block. Keep the current untyped argument for unresolved contracts.
- Preserve concise English method doc-comments and current app-class validation.
  Verify CallbackSourceEdits.methodText and both generators retain event validation
  when the output class name changes through Save As.
- Apply this only to newly generated methods. Do not add validation to existing
  user methods on Open/Reload/Save or rewrite their bodies. Preserve atomic edits,
  collision checks, source preflight, complete method deletion and Undo/Redo.

Checkpoint: generated Button handlers have the audited event type; differing and
unknown callback contracts produce their respective correct signatures. Test
Add/Delete/Undo/Redo, source preservation, Save/reparse and Save As with existing
bodies. Run catalog/loader, callback model/generation, parser and round-trip suites,
then the full escalated MATLAB suite. Any runtime event-type checks use only
trusted test fixtures, never the user's opened application.

### Follow-up proposal: Avoid duplicated component words in handler names

Status: design recommendation only; no naming implementation changes are included
in this roadmap update. Review this policy before implementing it.

Current code uses ComponentNameRewriter.defaultHandler to concatenate the component
name and callback name with `Fcn` removed, bound the identifier length, and feed
collision handling. DocumentModel uses this helper both for Add and for identifying
which default handler names follow an explicit component rename. Both consumers
must agree on the same naming policy.

| Approach | Benefit | Limitation / decision |
| --- | --- | --- |
| Runtime prefix/substring detection from the component name or declared class | Little added data; can suggest candidates | Spelling does not establish event meaning; mutable component names and new variants make outcomes unstable. Do not use as the runtime rule. |
| A special-case list inside generation code | Small initial implementation | Duplicates declarative inventory and is disconnected from variant contracts. Do not use as the source of truth. |
| Reviewed per-variant/per-callback handler suffix in the development ledger, promoted into the catalog | Explicit, reviewable meaning and predictable behavior | Requires schema/promotion support and auditing. Recommended. |

Store the desired final suffix, rather than a string to search for and remove.
A proposed runtime `handlerSuffix` is independent of `callbackSignature` and
ValueSchema. The development ledger must clearly identify the suffix as a yamada
naming-policy decision, not as a claimed MathWorks callback contract. Put it in a
separate generation-policy field on the audited property record, then promote the
reviewed value beside the signature metadata. Do not directly hand-edit generated
runtime JSON. Automatic class-prefix matching may help produce audit candidates,
but human review determines the promoted policy.

Proposed examples, scoped to the indicated component/callback pair:

| Component / callback | Reviewed suffix | Result for the component name shown |
| --- | --- | --- |
| Push button / ButtonPushedFcn | Pushed | HogeButton -> HogeButtonPushed; Button2 -> Button2Pushed |
| Menu / MenuSelectedFcn | Selected | FileMenu -> FileMenuSelected |
| State button / ValueChangedFcn | ValueChanged | HogeButton -> HogeButtonValueChanged |
| Figure or axes / ButtonDownFcn | ButtonDown | PlotAxes -> PlotAxesButtonDown |
| Figure / WindowButtonDownFcn | WindowButtonDown | MainFigure -> MainFigureWindowButtonDown |
| Figure / SizeChangedFcn | SizeChanged | MainFigure -> MainFigureSizeChanged |

`Button` in ButtonPushedFcn names the component kind; `Button` in an axes/figure
ButtonDownFcn identifies the mouse button event and must remain. Never delete
arbitrary matching substrings from a callback name, or inspect the user's chosen
component name to decide which part is redundant. The popup's callback property
name and generated binding remain unchanged; only the new handler method name
uses the reviewed suffix.

Implementation sequence and checkpoints:

1. Audit the naming policy alongside Stage 7 and extend the relevant ledger/runtime
   schemas and promotion path alongside Stage 8. Accept only nonempty valid suffix
   identifiers. Missing policy keeps the existing callback-derived naming rule;
   do not silently introduce a new rule for `Callback`-ending property names.
   Checkpoint: review the trim/preserve matrix above, arbitrary component names,
   styles, inherited callbacks and absent/invalid overrides.
2. Make the shared default-name resolver consume the effective definition's suffix.
   Update both Add and component-rename default-name recognition. Retain existing
   valid-name/length bounds, reserved-name checks and collision numbering (`_2`,
   etc.). Plan conservative recognition of both legacy and new default stems for
   explicit rename operations, under the existing ownership/reference checks;
   preserve custom and shared handlers. Never bulk-migrate names on Open/Reload or
   Save. Checkpoint: Button/HogeButton/Button2 names, menu and mouse-event cases,
   collisions, maximum-length identifiers, pending edits, legacy/new defaults and
   custom names remain predictable without changing unrelated source.
3. Test generation, explicit rename, Add/Delete/Undo/Redo, Save/reopen and callback
   body preservation. Update source/model/rename expectations for the new default
   naming convention and document compatibility behavior. Checkpoint: relevant
   catalog, loader, discovery, callback-generation, ComponentRenameTest and
   round-trip suites pass, followed by full escalated MATLAB verification when
   implementation begins.

## Reload Source Edited Outside yamada

Status: completed and verified with the callback-management workflow above.

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

Stage 1 progress: reload resolves local dirty state before parsing the replacement.
External changes require Save As to a different canonical path, Discard or Cancel.
Fresh byte snapshots around parsing reject concurrent changes. Failed reads,
parse failures, canceled decisions and failed saves retain the current document.
Successful reload installs clean history, closes stale popup targets and restores
selection by a unique component name. Related lifecycle/UI/convention/selection
checks pass: 24 Passed, 0 Failed, 0 Incomplete.

### Stage 2: Add the three Reload entry points

- Add a Refresh button alongside Undo/Redo in the existing toolbar, a Reload Source
  command in the Edit menu, and F5 handling through the editor keyboard dispatcher.
  Show the shortcut and a tooltip explaining that saved source is reloaded.
- Route all three entries through one command and identical availability rules;
  avoid duplicate execution, reentrant reloads and conflicts with focused controls.

Checkpoint: invoke toolbar, menu and F5 through real UI bindings; verify identical
results and availability for unsaved/new, saved and missing-file documents. Check
keyboard behavior with focus in the hierarchy, Inspector and callback popup.

Stage 2 progress: toolbar Refresh, Edit > Reload Source (F5), and unmodified F5
share one guarded command and availability policy. Callback-popup F5 forwards
to that same command. Binding-level tests cover all three entries; native
Hierarchy/Inspector F5, popup F5 and external-body verification also pass.

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

Stage 3 progress: the native hierarchy/popup workflow now saves an externally
edited method body, invokes popup F5, verifies fresh clean history and popup
invalidation, then Deletes and Undoes the current method body. Safe Preview
nonexecution and lifecycle cleanup pass. Selection preservation, renamed/deleted
components, externally introduced sharing, long-source/repeated reload and further
Save/reopen pass. All 256 full-suite tests, native Tab/Enter/F5 and popup visual
checks pass; the completion evidence is recorded above.


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

## Operate on Components with Their Descendants

Removing a component with children is currently rejected. Treat a selected
container and its entire descendant subtree as one unit when moving, deleting,
copying, cutting, or pasting it.

- Add model operations that collect descendants in stable hierarchy order and
  validate the complete subtree before changing any component or source intent.
- Keep parent-child links, component order, names, internal references, and
  supported layout properties consistent. Define how references from outside
  the subtree are handled; reject operations that cannot preserve them safely.
- Make each subtree move, delete, cut, or paste one atomic Undo/Redo step. A
  failed operation must leave the document, clipboard, and selection intact.
- Extend source generation to insert, relocate, or remove only declarations,
  creation calls, assignments, and other spans whose ownership is proven.
  Preserve unsupported code and callbacks without executing the input app.
- Apply these rules to hierarchy commands and the Copy/Cut/Paste task below;
  test nested containers, mixed generated and opened source, external references,
  failure rollback, Undo/Redo, and save/reopen round trips.

## Reparent Components Between Containers

Allow a component or complete subtree to move from one valid parent to another,
including dragging it between two Grid Layouts in Safe Preview.

- Add a validated reparent operation that rejects cycles, the root component,
  unsupported parent types, ambiguous source ownership, and invalid destinations
  before changing either parent's child list.
- Define placement when moving among absolute-positioned containers and Grid
  Layouts. Update `Position` or `Layout.Row`/`Layout.Column` together with the
  parent change; do not silently discard unsupported layout or source values.
- Expose eligible drop targets and a clear insertion preview in Safe Preview and
  the hierarchy view. Keep existing drag-within-one-parent behavior distinct
  from reparenting, and reject an invalid drop without moving the component.
- Commit the parent change and any placement changes as one undoable operation;
  update selection, Inspector, Safe Preview, diagnostics, and generated source.
- Test transfers between two Grid Layouts, nested containers, absolute/grid
  boundaries, invalid and cyclic drops, subtree moves, Undo/Redo, and opened-
  source round trips without executing the input application.

## Add Component Copy, Cut, and Paste

- Provide Copy, Cut, and Paste through the Edit menu, keyboard shortcuts, and
  context menus on components in the hierarchy view. All three entry points
  must use the same commands and availability rules.
- Use the complete-subtree rules above when a selected component has children.
  Define where each subtree can be pasted and how unique component names and
  identities are assigned.
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

Grid settings button repair (2026-10-03): a grid covering the entire UIFigure
now keeps its row and column settings buttons in the dark editing margin.
The active grid reserves space for the buttons, and headers and popovers use
editing-area bounds rather than figure bounds. Screenshots confirm that the
buttons are visible outside the orange figure handles. The Grid Layout area
profile passed 168/168 tests; all four HTML overlay tests passed, including
settings buttons and popup placement for a grid outside a shrunken figure.

## Offer an Explicit Save As Line-Ending Choice

New documents currently use the host-default line ending, while opened documents
preserve detected CRLF or LF source.

- Optionally expose CRLF and LF choices in Save As without changing the default
  behavior.
- Keep the chosen convention explicit in generated-source Preview and file tests.
- Do not normalize an opened file silently.
