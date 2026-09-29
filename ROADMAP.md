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

## Build a Grid Layout Visual Editor

This item remains active and incomplete. The first implementation and the
follow-up corrections for open-file selection, compact track controls,
zero-size `fit` tracks, and mixed-control `fit` geometry are present. Expanded
regression coverage, final manual review, and explicit user approval remain;
keep this roadmap item and its plan until the user explicitly approves
completion. Passing tests alone must not remove or complete it.

See the [Grid Layout Visual Editor implementation plan](GRID_LAYOUT_VISUAL_EDITOR_IMPLEMENTATION_PLAN.md)
for completed work, confirmed causes, the MATLAB-versus-HTML responsibility
split, the current correction plan, and the verification gates.

- Keep the Property Inspector component-focused. Edit `RowHeight` and
  `ColumnWidth` from compact in-grid settings buttons, while leaving spacing,
  padding, color, visibility, and scrolling in the Inspector.
- Make canvas selection of Grid Layout descendants available immediately after
  opening an existing file, independently of which grid is active.
- Show lightweight row and column separators and keep controls and move drop
  targets reachable for zero-height or zero-width tracks without fabricating
  positive geometry.
- Support fixed, `fit`, weighted, mixed, nested, spanning, empty, and
  expression-backed cases conservatively and source-safely.
- Keep insert and delete atomic and undoable; track reordering is not part of
  this feature.
- Validate `SimpleCalculatorApp` and `ControlGalleryApp`, including nested grids,
  followed by manual R2024a review and the full unit suite.

## Show Safe Preview at the UIFigure's Actual Pixel Size

Safe Preview currently fits the root `UIFigure.Position(3:4)` into the editor
panel and scales pixel-positioned children. Replace this fitted view with a
one-to-one pixel canvas; resizing the editor window must not change the edited
root figure size or scale its preview components.

- Put a canvas with the root UIFigure's client-area width and height inside a
  dark scrollable Preview host. Keep a visible boundary between the canvas and
  the area outside the figure. Center the canvas when it fits; provide horizontal
  and vertical scrolling when it extends beyond the host.
- Render supported components at their model pixel positions without a fit
  scale. Keep the Safe Preview boundary: do not execute opened app code or imply
  that unsupported runtime behavior is reproduced.
- Move the interaction overlay, component hit targets, resize handles, and Grid
  Layout geometry to a consistent canvas coordinate system so scrolling and
  editor-window resizing do not offset interactions.
- Add handles for changing the root UIFigure width and height. Commit supported
  literal `Position` edits through the document model, preserving its screen
  origin and providing Undo/Redo and generated-source updates. Disable the
  handles with a clear reason when the root size is not safely editable.
- Add a small UI fixture (for example, 320 x 240 pixels) that fits inside the
  normal Preview viewport and a large UI fixture (for example, 1200 x 900
  pixels) that overflows it in both directions. Give each fixture identifiable
  controls near its edges; include a layout-managed child to exercise geometry.
- Use both fixtures to verify one-to-one canvas dimensions, dark outside area,
  scroll reachability, selection and dragging after scrolling, root resize,
  Undo/Redo, generation, and reopen behavior. Also check narrow and enlarged
  editor windows, then run focused UI tests and the full R2024a unit suite.

## Offer an Explicit Save As Line-Ending Choice

New documents currently use the host-default line ending, while opened documents
preserve detected CRLF or LF source.

- Optionally expose CRLF and LF choices in Save As without changing the default
  behavior.
- Keep the chosen convention explicit in generated-source Preview and file tests.
- Do not normalize an opened file silently.
