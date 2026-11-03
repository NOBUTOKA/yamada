# yamada Roadmap

This roadmap contains unfinished work for the public development version of `yamada`. Each section is an independent, reviewable task rather than part of a numbered delivery hierarchy. The order below does not promise delivery order.

The [product specification](SPECIFICATION.md) remains authoritative for current behavior. A roadmap item becomes part of the supported public contract only after its implementation, tests, and user documentation are complete.

## Add Component-Reference Property Editors

Ninety-five audited component-reference surfaces, including `ContextMenu`, `Parent`, and `SelectedTab`, are currently visible but read-only with the `deferredComponentReference` reason.

- Define an allowlisted selector contract for each safely editable reference family and its permitted target types.
- Validate references against document identity, hierarchy, parent rules, and source ownership before committing them.
- Keep cyclic, ambiguous, expression-backed, or unsupported references read-only with actionable diagnostics.
- Cover Inspector interaction, atomic history, Safe Preview, and localized source generation for every enabled reference family.

## Expose Property Reset in the Inspector

`DocumentModel.resetProperty` and reversible reset history already exist, but the Inspector has no per-property reset action.

- Show reset availability from the effective property state without obscuring explicit, default, and source-backed values.
- Route reset through the existing model transaction and undo/redo history.
- Disable reset when source ownership or the reset policy does not permit a safe change, and explain the reason inline.
- Test singleton and composite Inspector rows, Preview refresh, source removal, and undo/redo restoration.

## Expose Every Supported Construction Style in the Palette

The catalog selects style-specific property surfaces from creation arguments, but the palette does not provide a dedicated construction choice for every audited factory style.

- Add clear palette choices for supported styles without duplicating factory definitions in MATLAB code.
- Seed the correct creation arguments, defaults, display names, icons, and parent eligibility from the catalog.
- Verify insertion, Inspector projection, Safe Preview, generation, and round-trip behavior for each exposed style.

## Support Programmatic Axes Construction and Editing

Programmatic-only Cartesian, geographic, and polar axes are cataloged and source-preserved, but their specialized construction and editing paths remain restricted.

- Define safe creation arguments, permitted parents, Preview behavior, and geometry rules for each axes family.
- Add palette and Inspector surfaces only where source generation is deterministic.
- Preserve unsupported axes expressions and runtime-only state without executing the input application.
- Add construction/destruction, generation, and opened-source round-trip tests.

## Recognize Axes Configuration Function Calls

Recognize axes configuration expressed through functions such as `ylabel(ax, ...)`, `xlabel`, `title`, `xlim`, and related calls, alongside direct property assignments. This is separate future work from the current performance changes.

- Audit applicable functions, overloads, target ownership, returned handles, and effects on axes or child text objects.
- Preserve recognized and unsupported forms without executing user code; expose editing and insertion where source ownership and deterministic generation can be established.
- Integrate recognized calls into setting order, effective state, localized validation, Preview, and atomic Undo/Redo without treating them as arbitrary property assignments.

## Support Native Menu, Toolbar, and Tree-Node Hierarchies

Native menus, toolbar tools, and tree nodes are represented in parsed source but do not yet have complete insertion and hierarchy-editing workflows.

- Define parent-specific insertion, ordering, reparenting, and deletion rules.
- Provide hierarchy-first editing where a canvas representation would be misleading or unavailable.
- Preserve callback and nonliteral source while editing only unambiguously owned declarations, construction calls, and assignments.
- Verify undo/redo, diagnostics, generation, and no-edit source preservation for each hierarchy family.

## Edit Application Menu Bars and Context Menus

Provide a dedicated editing workflow for menu bars, submenus, context menus, toolbars, and their items in the application being edited. This builds on the native hierarchy operations above; it does not change the editor's own menus.

- Present a hierarchy-focused editor for adding and arranging menu and toolbar items, editing supported labels and other literal properties, and choosing which components own a context menu.
- Define the supported menu and tool properties, parent rules, and component references in the catalog and model before enabling each editing control.
- Keep callbacks, expressions, and source whose ownership is ambiguous visible but read-only. Do not execute the opened application or its callbacks.
- Route edits through validated, atomic document transactions so Undo/Redo, Safe Preview limitations, diagnostics, and source generation stay consistent.
- Test new and opened applications with nested menus, context-menu assignment, toolbar items, unsupported source, and no-edit round trips.

## Generate Documented Event Argument Types

Status: planning only. Callback method generation currently uses an untyped `event` argument.

Data flow: release-specific audited callback contracts -> catalog promotion -> validated PropertyDefinition/ComponentRegistry projection -> DocumentModel method stub construction -> NewAppGenerator/RoundTripGenerator output. The popup remains a thin command view; ValueSchema continues to describe callback binding values, not the event argument passed to a handler.

### Audit and define callback signature metadata

- Extend per-property records and `schema.json` under `dev/component-data/R2024a`. Record a distinct `callbackSignature` contract with event representation, verified fully qualified class name where applicable, verified shape if available, audit status and release-specific source evidence. Field names are proposed schema design, not existing runtime fields.
- Key contracts by concrete component variant/style and callback property; account for effective parent-context projection where applicable. Do not assume that a shared callback name implies the same argument contract across components.
- Distinguish verified object types, verified non-object/empty event data, and unresolved documentation. Unknown event data remains untyped; do not replace it with a universal `event.EventData` base class or presume every event is scalar.
- For example, audit `uibutton-push` / `ButtonPushedFcn` against the R2024a official contract and installed public `matlab.ui.eventdata.ButtonPushedData` class. Verify `ValueChangedFcn`, `ValueChangingFcn`, CreateFcn/DeleteFcn and inherited callbacks independently instead of inferring types from property names.

Checkpoint: review the callback/variant inventory and evidence for representative Button, state-button, numeric/text edit-field, slider, table, tree and figure callbacks. Missing evidence is explicitly unresolved. No opened application or user callback may execute during discovery or audit.

### Promote and validate the new metadata

- Extend the promotion/projection pipeline under `dev/component-data`, including `PromoteGroupingToRuntimeCatalog.ps1`, and any intervening grouping artifacts that otherwise drop the contract. Preserve per-variant overrides when reusable property groups are expanded; do not infer one common signature from group ID.
- Regenerate `resources/component-catalog/R2024a`; update the catalog schema and strict metadata allowlists/validation in ComponentCatalogLoader. Keep older catalogs with absent optional contracts loadable, and review schema versioning.
- Expose the validated contract through PropertyDefinition and the existing `getEffectiveCallbacks` projection. Reject malformed qualified type names, unsupported contract shapes and signatures attached to noncallback properties. Treat class names as validated data, never as expressions to evaluate.
- Keep callback binding editability, Inspector rows and Safe Preview policy unchanged. Documentation evidence stays in the development audit surface; runtime metadata carries only the reviewed generation contract it needs.

Checkpoint: test promotion reproducibility, ledger/catalog parity, concrete styles and parent projection, unknown/absent contracts, and malformed-metadata rejection. Catalog loading/discovery must not instantiate input apps or execute callbacks.

### Use the contract in generated method stubs

- Change DocumentModel.applyCallbackAction's stub construction to obtain the effective callback definition and emit the verified `event` type/shape in its arguments block. Keep the current untyped argument for unresolved contracts.
- Preserve concise English method doc-comments and current app-class validation. Verify CallbackSourceEdits.methodText and both generators retain event validation when the output class name changes through Save As.
- Apply this only to newly generated methods. Do not add validation to existing user methods on Open/Reload/Save or rewrite their bodies. Preserve atomic edits, collision checks, source preflight, complete method deletion and Undo/Redo.

Checkpoint: generated Button handlers have the audited event type; differing and unknown callback contracts produce their respective correct signatures. Test Add/Delete/Undo/Redo, source preservation, Save/reparse and Save As with existing bodies. Run catalog/loader, callback model/generation, parser and round-trip suites, then the full escalated MATLAB suite. Any runtime event-type checks use only trusted test fixtures, never the user's opened application.

## Avoid Duplicated Component Words in Handler Names

Status: agreed naming/data policy, implementation pending. This roadmap update does not implement the schema, ledger population or generation changes.

Current code uses ComponentNameRewriter.defaultHandler to concatenate the component name and callback name with `Fcn` removed, bound the identifier length, and feed collision handling. DocumentModel uses this helper both for Add and for identifying which default handler names follow an explicit component rename. Both consumers must agree on the same naming policy.

| Approach | Benefit | Limitation / decision |
| --- | --- | --- |
| Runtime prefix/substring detection from the component name or declared class | Little added data; can suggest candidates | Spelling does not establish event meaning; mutable component names and new variants make outcomes unstable. Do not use as the runtime rule. |
| A special-case list inside generation code | Small initial implementation | Duplicates declarative inventory and is disconnected from variant contracts. Do not use as the source of truth. |
| Reviewed per-variant/per-callback handler suffix in the development ledger, promoted into the catalog | Explicit, reviewable meaning and predictable behavior | Requires schema/promotion support and auditing. Recommended. |

Store the desired final suffix, rather than a string to search for and remove. Place `handlerSuffix` directly on each callback property record in the development ledger, alongside `callbackSignature` and `valueContract`. Do not introduce a `generationPolicy` wrapper or a naming `reason` field. The suffix is a yamada generation choice, independent of the documented event signature and accepted binding values. Promote it under the same name into runtime property metadata.

Populate `handlerSuffix` for every callback entry in every concrete ledger variant, including inherited callbacks and entries whose resulting names stay unchanged. For example, explicitly record `ValueChanged` for ValueChangedFcn, `Create` for CreateFcn and `Delete` for DeleteFcn, as well as `Pushed` for ButtonPushedFcn. Do not use omitted fields to mean "keep the current name" in the maintained ledger. Absent-field fallback to the existing naming rule is only a compatibility path for older or external catalogs, not the normal representation of unchanged entries. Invalid or empty supplied suffixes must be rejected, not treated as absent.

Do not directly hand-edit generated runtime JSON. Automatic class-prefix matching may help produce audit candidates, but review determines the promoted policy.

Proposed examples, scoped to the indicated component/callback pair:

| Component / callback | Reviewed suffix | Result for the component name shown |
| --- | --- | --- |
| Push button / ButtonPushedFcn | Pushed | HogeButton -> HogeButtonPushed; Button2 -> Button2Pushed |
| Menu / MenuSelectedFcn | Selected | FileMenu -> FileMenuSelected |
| State button / ValueChangedFcn | ValueChanged | HogeButton -> HogeButtonValueChanged |
| Figure or axes / ButtonDownFcn | ButtonDown | PlotAxes -> PlotAxesButtonDown |
| Figure / WindowButtonDownFcn | WindowButtonDown | MainFigure -> MainFigureWindowButtonDown |
| Figure / SizeChangedFcn | SizeChanged | MainFigure -> MainFigureSizeChanged |

`Button` in ButtonPushedFcn names the component kind; `Button` in an axes/figure ButtonDownFcn identifies the mouse button event and must remain. Never delete arbitrary matching substrings from a callback name, or inspect the user's chosen component name to decide which part is redundant. The popup's callback property name and generated binding remain unchanged; only the new handler method name uses the reviewed suffix.

Implementation sequence and checkpoints:

1. Audit the naming policy alongside the callback signature metadata audit above and extend the relevant ledger/runtime schemas and promotion path alongside its metadata promotion work. Accept only nonempty valid suffix identifiers. Populate direct `handlerSuffix` fields for all ledger callback entries, including unchanged-name and inherited entries; verify completeness during development-ledger audit/promotion while runtime loading retains the absent-field fallback for older catalogs. Do not silently introduce a new rule for `Callback`-ending property names. Checkpoint: enumerate every callback entry across all variants and confirm a nonempty suffix, exact ledger-to-catalog propagation, no wrapper/reason fields, compatibility fallback for absent fields, and rejection of invalid/empty fields. Review the trim/preserve matrix, arbitrary component names, styles and inherited callbacks. Entries that preserve the old naming result must be explicit too.
2. Make the shared default-name resolver consume the effective definition's suffix. Update both Add and component-rename default-name recognition. Retain existing valid-name/length bounds, reserved-name checks and collision numbering (`_2`, etc.). Plan conservative recognition of both legacy and new default stems for explicit rename operations, under the existing ownership/reference checks; preserve custom and shared handlers. Never bulk-migrate names on Open/Reload or Save. Checkpoint: Button/HogeButton/Button2 names, menu and mouse-event cases, collisions, maximum-length identifiers, pending edits, legacy/new defaults and custom names remain predictable without changing unrelated source.
3. Test generation, explicit rename, Add/Delete/Undo/Redo, Save/reopen and callback body preservation. Update source/model/rename expectations for the new default naming convention and document compatibility behavior. Checkpoint: relevant catalog, loader, discovery, callback-generation, ComponentRenameTest and round-trip suites pass, followed by full escalated MATLAB verification when implementation begins.

## Add Range and Multiple Selection

The editor currently tracks one selected component ID. Establish a selection model that can represent several components before adding group edit commands.

- Support a drag-selection rectangle in Safe Preview and Shift-based range selection in the hierarchy view. Define Ctrl/Command selection toggling and a stable anchor for repeated range extensions.
- Keep selected component IDs, the active component, hierarchy highlighting, and Preview/HTML-overlay highlighting synchronized. Selection alone must not modify the document or mark it dirty.
- Define how nested components, overlapping bounds, hidden tabs, scrolling, and clicks on empty space affect selection. Avoid selecting a descendant twice when an ancestor is selected for a later group operation.
- Keep the existing Inspector and single-component geometry tools tied to the active component until group editing has its own validated behavior.
- Test mouse and keyboard selection in both views, selection after hierarchy refresh and document replacement, and interaction with Grid Layout overlays.

## Verify Packaging and End-to-End Workflows

- Verify catalog and HTML-overlay resource discovery from the distributed layout, not only from a repository checkout.
- Complete new-app and existing-app workflows through the shared model, Preview, validation, generator, diff, Save, and Save As paths.
- Verify recoverable save targets, save/reopen behavior, UTF-8 without BOM, preserved CRLF/LF conventions, and cleanup of every UI fixture.
- Add the end-to-end checks required before publishing a versioned release.

## Package a Public Release as a MATLAB Toolbox

Create a MATLAB Toolbox (`.mltbx`) only after the editor reaches the quality bar for a versioned public release and the release-blocking workflows above pass.

- Define stable Toolbox metadata, including its identifier, semantic version, summary, author, license, minimum MATLAB release, and supported platforms.
- Add a reproducible packaging script based on `matlab.addons.toolbox.ToolboxOptions` and `matlab.addons.toolbox.packageToolbox` rather than relying only on manually saved packaging-project state.
- Include the runtime MATLAB source, the release-specific component catalog, `EditorInteractionOverlay.html`, the license, and public documentation; exclude repository metadata, development-only catalog tooling, tests, and build output.
- Decide whether the first package launches through the `yamada()` command only or also exposes an App Gallery entry, and document the supported entry point.
- Analyze required files and products, then declare only verified MATLAB-release and platform compatibility. Initially treat R2024a as the sole supported release unless additional releases have been tested.
- Install the built package into an isolated MATLAB environment and verify that the installed copy, rather than the source checkout, launches successfully; discovers its catalog and HTML overlay; completes representative New, Open, Save, and Save As workflows; and uninstalls cleanly.
- Publish the `.mltbx` and release notes with the corresponding tagged release only after the package artifact and installation smoke tests pass.

## Offer an Explicit Save As Line-Ending Choice

New documents currently use the host-default line ending, while opened documents preserve detected CRLF or LF source.

- Optionally expose CRLF and LF choices in Save As without changing the default behavior.
- Keep the chosen convention explicit in generated-source Preview and file tests.
- Do not normalize an opened file silently.
